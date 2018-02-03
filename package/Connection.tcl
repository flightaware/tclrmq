package provide rmq 1.3.1

package require TclOO
package require tls

namespace eval rmq {
	namespace export Connection

	proc debug {msg} {
		if {$::rmq::debug} {
			set ts [clock format [clock seconds] -format "%D %T" -gmt 1]
			puts stderr "\[DEBUG\] ($ts): $msg"
		}
	}

	# return random integer in [start, end]	
	proc rand_int {start end} {
		set range [expr {$start - $end + 1}]
		return [expr {$start + int(rand() * $range)}]
	}
}

oo::class create ::rmq::Connection {
	# TCP socket used for communication with the
	# RabbitMQ server
	variable sock

	# Hostname of the server
	variable host

	# Port of the server
	variable port

	# ::rmq::Login object containing needed credentials
	# for logging into the RabbitMQ server
	variable login

	# boolean tracking whether we are connected
	# this is set to true after performing the handshake
	variable connected

	# whether the connection is blocked
	variable blocked

	# whether to allow for blocked connection notifications
	variable blockedConnections

	# Locale for content
	variable locale

	# whether to allow cancel notifications
	variable cancelNotifications

	# Track the next channel number available
	# to be used for auto generating channels without the
	# client having to specify a number
	variable nextChannel
	variable maxChannels

	# Track the channels by mapping each channel number to
	# the channel object it represents
	variable channelsD

	# Save connection closed meta data when received
	variable closeD

	# Last frame read from the socket
	variable frame

	# Max frame size
	variable frameMax

	# Partial frames can occur, so we buffer them here
	variable partialFrame

	# Timestamp of the last socket activity for heartbeat
	# purposes
	variable lastRead
	variable lastSend

	# Variables for dealing with heartbeats
	# after event loop ID for heartbeat frames
	variable heartbeatSecs
	variable heartbeatID

	# If we periodically poll the socket for EOF to
	# to try and detect inactivity when hearthbeats
	# are disabled save the after event ID
	variable sockHealthPollingID

	# Whether to use TLS for the socket connection
	variable tls
	variable tlsOpts
	
	# Whether to try and auto-reconnect when connection forcibly
	# closed by the remote side or the network
	# Maximum number of exponential backoff attempts to try
	# Maximum retry attempts
	# Are we trying to actively reconnect
	variable autoReconnect
	variable maxBackoff
	variable maxReconnects
	variable reconnecting

	##
	##
	## callbacks
	##
	##
	variable blockedCB
	variable connectedCB
	variable closedCB
	variable errorCB
	variable failedReconnectCB

	constructor {args} {
		array set options {}
		set options(-host) $::rmq::DEFAULT_HOST
		set options(-port) $::rmq::DEFAULT_PORT
		set options(-tls) 0
		set options(-login) [::rmq::Login new]
		set options(-frameMax) $::rmq::MAX_FRAME_SIZE
		set options(-maxChannels) $::rmq::DEFAULT_CHANNEL_MAX
		set options(-locale) $::rmq::DEFAULT_LOCALE
		set options(-heartbeatSecs) $::rmq::HEARTBEAT_SECS
		set options(-blockedConnections) $::rmq::BLOCKED_CONNECTIONS
		set options(-cancelNotifications) $::rmq::CANCEL_NOTIFICATIONS
		set options(-maxTimeout) $::rmq::DEFAULT_MAX_TIMEOUT
		set options(-autoReconnect) $::rmq::DEFAULT_AUTO_RECONNECT
		set options(-maxBackoff) $::rmq::DEFAULT_MAX_BACKOFF
		set options(-maxReconnects) $::rmq::DEFAULT_MAX_RECONNECT_ATTEMPTS
		set options(-debug) 0

		foreach {opt val} $args {
			if {[info exists options($opt)]} {
				set options($opt) $val
			}
		}

		foreach opt [array names options] {
			set [string trimleft $opt -] $options($opt)
		}

		# whether we are in debug mode
		set ::rmq::debug $debug

		# socket variable
		set sock ""
		set tls 0
		array set tlsOpts {}

		# not currently connected
		set connected 0

		# not currently blocked
		set blocked 0

		# no connection closed metadata yet
		set closeD [dict create]

		# map channel number to channel object
		set channelsD [dict create]

		# book-keeping for frame processing
		set partialFrame ""

		# if doing periodic socket polling
		set sockHealthPollingID ""
		
		# whether we are attempting to reconnect
		set reconnecting 0

		# heartbeat setup
		set lastRead 0
		set lastSend 0
		set heartbeatID ""

		# callbacks
		set blockedCB ""
		set connectedCB ""
		set closedCB ""
		set errorCB ""
		set failedReconnectCB ""
	}

	destructor {
		catch {close $sock}
	}

	# attempt to reconnect to the server using
	# exponential backoff
	#
	# this is triggered when the check connection method
	# detects that the socket has gone down
	#
	# if auto reconnection is not desired this method can
	# be called in the closed callback or equivalent place
	method attemptReconnect {} {
		::rmq::debug "Attempting auto-reconnect with exponential backoff"
		set reconnecting 1
		set retries 0
		while {$maxReconnects == 0 || $retries < $maxReconnects} {
			if {[my connect]} {
				set reconnecting 0
				return
			}

			set waitTime [expr {(2**$retries) * 1000 + [::rmq::rand_int 1 1000]}]
			set waitTime [expr {min($waitTime, $maxBackoff * 1000)}]

			incr retries
			::rmq::debug "After $waitTime msecs, attempting reconnect ($retries time(s))..."

			after $waitTime
		}

		::rmq::debug "Unable to successfully reconnect, not attempting any more..."
		if {$failedReconnectCB ne ""} {
			$failedReconnectCB [self]
		}
	}

	#
	# method run periodically to check whether the socket is
	# still connected by catching any error on the eof proc
	#
	method checkConnection {} {
		try {
			eof $sock
			set sockHealthPollingID \
				[after $::rmq::CHECK_CONNECTION [list [self] checkConnection]]
		} on error {result options} {
			::rmq::debug "When testing EOF on socket: '$result'"
			my closeConnection
		}
	}

	#
	# perform all necessary book-keeping to close the Connection
	#
	method closeConnection {{callCloseCB 1}} {
		::rmq::debug "Closing connection"
		try {
			fileevent $sock readable ""
			close $sock
		} on error {result options} {
			::rmq::debug "Close connection error: '$result'"
		}

		# reset all necessary variables
		set connected 0
		set lastRead 0
		set lastSend 0
		set channelsD [dict create]
		after cancel $heartbeatID
		after cancel $sockHealthPollingID

		# if we are reconnecting, do not want to call this
		# too many times so we check the reconnecting flag
		# this way, the first disconnection will invoke this
		# but not every subsequent one
		# then, if reconnects fail, a separate callback is used
		if {$closedCB ne "" && $callCloseCB && !$reconnecting} {
			$closedCB [self] $closeD
		}

		# time to try an auto reconnect is configured to do so
		if {$autoReconnect && !$reconnecting} {
			my attemptReconnect
		}
	}

	#
	# connect - method to perform AMQP handshake
	#  this method performs asynchronous socket IO
	#  to establish a connection with the RabbitMQ
	#  server
	#
	#
	method connect {} {
		# create the socket and configure accordingly
		try {
			if {!$tls} {
				set sock [socket -async $host $port]
			} else {
				::rmq::debug "Making TLS connection with options: [array get tlsOpts]"
				set sock [tls::socket {*}[concat [list -async $host $port] [array get tlsOpts]]]
			}

			# configure the socket
			fconfigure $sock \
				-blocking 0 \
				-buffering none \
				-encoding binary \
				-translation binary

			# since we connected using -async, need to wait for a possible timeout
			# once the socket is connected the writable event will fire and we move on
			# otherwise we use after to trigger a forceful cancel of the connection
			fileevent $sock writable [list set ::rmq::connectTimeout 1]
			set timeoutID [after [expr {$maxTimeout * 1000}] \
								 [list set ::rmq::connectTimeout 1]]
			vwait ::rmq::connectTimeout

			# potentially reconnect after a timeout
			# otherwise, unset the writable handler, cancel the timeout check
			# fconfigure the socket, and move on with something useful
			if {[fconfigure $sock -connecting]} {
				my closeConnection
				set err [fconfigure $sock -error]
				::rmq::debug "Connection timed out (-error $err) connecting to $host:$port"
				if {$autoReconnect && !$reconnecting} {
					after idle [after 0 [list [self] attemptReconnect]]
				}
				return 0
			} else {
				# we're connected, no need to detect timeout 
				fileevent $sock writable ""
				after cancel $timeoutID
			}
		} on error {result options} {
			# when using -async this is reached when a DNS lookup fails
			::rmq::debug "Error connecting to $host:$port '$result'"
			my closeConnection
			return 0
		}

		# mark the object variables for connection status
		set connected 1

		# setup a readable callback for parsing rmq data
		fileevent $sock readable [list [self] readFrame]

		# periodically monitor for connection status if heartbeats
		# disabled
		if {$heartbeatSecs == 0} {
			set sockHealthPollingID \
				[after $::rmq::CHECK_CONNECTION [list [self] checkConnection]]
		}

		# send the protocol header
		my send [::rmq::enc_protocol_header]
		::rmq::debug "Sent protocol header"

		return 1
	}

	method connected? {} {
		return $connected
	}

	method getFrameMax {} {
		return $frameMax
	}

	method getNextChannel {} {
		for {set chanNum 1} {$chanNum <= $maxChannels} {incr chanNum} {
			if {![dict exists $channelsD $chanNum]} {
				return $chanNum
			}
		}

		return -1
	}

	method getSocket {} {
		return $sock
	}

	#
	# set a callback for when the Connection object is blocked
	# by the RabbitMQ server
	#
	method onBlocked {cb} {
		set blockedCB $cb
	}

	#
	# set a callback for when the Connection object is closed
	# by the RabbitMQ server
	#
	method onClose {cb} {
		set closedCB $cb
	}

	#
	# set a callback for when the Connection object is closed
	# by the RabbitMQ server
	#
	method onClosed {cb} {
		set closedCB $cb
	}

	#
	# set a callback for when the AMQP handshake has completed
	# and the Connection object is ready to use, e.g., to create
	# Channel objects
	#
	# this is called when Connection.OpenOk is received
	#
	method onConnected {cb} {
		set connectedCB $cb
	}

	#
	# set a callback for when the Connection object processes a frame
	# with an error code
	#
	method onError {cb} {
		set errorCB $cb
	}

	#
	# set a callback for when an attempt to reconnect to the server
	# fails after the maximum number of retries
	#
	method onFailedReconnect {cb} {
		set failedReconnectCB $cb
	}

	#
	# a core method, called on each frame received
	#
	# if a partial frame is being handled, this is saved in the object
	# otherwise, the frame is deciphered and the appropriate method is
	# dispatched depending on what type of frame is handled
	#
	# the frame header and end byte is removed before the frame data is
	# passed downstream for further processing
	#
	method processFrame {data} {
		if {[string length $data] < 7} {
			::rmq::debug "Frame not even 7 bytes: saving partial frame"
			append partialFrame $data
			return 0
		}

		# read the header to figure out what we're dealing with
		binary scan $data cuSuIu ftype fchannel fsize
		::rmq::debug "Frame type: $ftype Channel: $fchannel Size: $fsize"

		# verify that the channel number makes sense
		if {$fchannel == 0} {
			set channelObj ""
		} elseif {[dict exists $channelsD $fchannel]} {
			# grab the channel object this corresponds to
			set channelObj [dict get $channelsD $fchannel]
		} else {
			# Error code 505 is an unexpected frame error
			::rmq::debug "Channel number $fchannel does not exist"
			my send [::rmq::enc_frame 505 0 ""]
			return 0
		}

		# dispatch based on the frame type
		if {$ftype != $::rmq::FRAME_HEARTBEAT && $fsize == 0} {
			::rmq::debug "Non-heartbeat frame with a payload size of 0"
			return 1
		}

		# make sure the frame ends with the right character
		if {[string range $data end end] != $::rmq::FRAME_END} {
			::rmq::debug "Frame does not end with correct byte value: saving partial frame"
			::rmq::debug "Frame was [string length $data] bytes with claimed $fsize size on channel $fchannel"

			# partial frames are buffered here
			append partialFrame $data
			return 0
		}

		# dispatch on type of payload
		set data [string range $data 7 end-1]
		if {$ftype eq $::rmq::FRAME_METHOD} {
			my processMethodFrame $channelObj $data
		} elseif {$ftype eq $::rmq::FRAME_HEADER} {
			my processHeaderFrame $channelObj $data
		} elseif {$ftype eq $::rmq::FRAME_BODY} {
			$channelObj contentBody $data
		} elseif {$ftype eq $::rmq::FRAME_HEARTBEAT} {
			my processHeartbeatFrame $channelObj $data
		} else {
			my processUnknownFrame $ftype $fchannel $data
		}

		return 1
	}

	method processFrameSafe {data} {
		try {
			my processFrame $data
		} on error {result options} {
			::rmq::debug "processFrame error: $result $options"
		}
	}

	method processHeaderFrame {channelObj data} {
		# Reply code 504 is a channel error
		if {$channelObj eq ""} {
			::rmq::debug "\[ERROR\]: Channel is 0 for header frame"
			return [my send [::rmq::enc_frame 504 0 ""]]
		}

		set headerD [::rmq::dec_content_header $data]
		$channelObj contentHeader $headerD
	}

	method processHeartbeatFrame {channelObj data} {
		# Reply code 501 is a frame error when the channel is not 0
		if {$channelObj ne ""} {
			::rmq::debug "\[ERROR\]: Channel is not 0 for heartbeat"
			return [my send [::rmq::enc_frame 501 0 ""]]
		}

		# otherwise send a heartbeat back
		my sendHeartbeat
	}

	method processMethodFrame {channelObj data} {
		# Need to know the class ID and method ID
		binary scan $data SuSu classID methodID
		set data [string range $data 4 end]
		::rmq::debug "class ID $classID method ID $methodID"

		# dispatch based on class ID
		if {$classID == $::rmq::CONNECTION_CLASS} {
			my [::rmq::dec_method $classID $methodID] $data
		} elseif {$classID in $::rmq::CHANNEL_CLASSES} {
			# all classes other than Connection are handled by a channel
			# object since they all execute in the context of one
			$channelObj [::rmq::dec_method $classID $methodID] $data
		} else {
			my processUnknownMethod $classID $methodID $data
		}
	}

	method processUnknownFrame {ftype channelObj data} {
		::rmq::debug "Processing an unknown frame type $ftype"

		# check if the ftype is a known error code
		if {[dict exists $::rmq::ERROR_CODES $ftype]} {
			# if so, is the error on the connection or the channel
			# if connection, close it down and move on
			# if channel, pass it on to a channel error handler to
			# decide whether the channel needs to be closed or not
			if {$channelObj eq ""} {
				if {$errorCB ne ""} {
					$errorCB [self] $ftype $data
				}
			} else {
				$channelObj errorHandler $ftype $data
			}
		}
	}

	method processUnknownMethod {classID methodID data} {
		# Received an unsupported method
		::rmq::debug "Unsupported class ID $classID and method ID $methodID"
	}

	#
	# fileevent readable handler for the socket connection to the
	# RabbitMQ server
	#
	method readFrame {} {
		if {[eof $sock]} {
			::rmq::debug "Reached EOF reading from socket"
			return [my closeConnection]
		}

		try {
			set data [read $sock $frameMax]
		} on error {result options} {
			::rmq::debug "Error reading from socket"
			return [my closeConnection]
		}

		if {$data ne ""} {
			# mark time for socket read activity
			set lastRead [clock seconds]

			# process frames
			foreach frame [my splitFrames $data] {
				my processFrameSafe $frame
			}
		}
	}

	method reconnecting? {} {
		return $reconnecting
	}

	method removeCallbacks {{channelsToo 0}} {
		# reset all specific callbacks for Connection
		set blockedCB ""
		set connectedCB ""
		set closedCB ""
		set errorCB ""
		set failedReconnectCB ""

		if {!$channelsToo} {
			return
		}
	
		foreach chanObj [dict values $channelsD] {
			$chanObj removeCallbacks
		}
	}

	#
	# remove a Channel object from the Connection
	#
	method removeChannel {num} {
		dict unset channelsD $num
	}

	#
	# add a Channel object to this Connection
	#
	method saveChannel {num channelObj} {
		if {$num > 0} {
			dict set channelsD $num $channelObj
		}
	}

	#
	# send binary data to the RabbitMQ server
	#
	method send {data} {
		try {
			puts -nonewline $sock $data
			set lastSend [clock seconds]
		} on error {result options} {
			::rmq::debug "Error sending to socket"
			my closeConnection
		}
	}

	#
	# send a heartbeat to the RabbitMQ server
	#
	method sendHeartbeat {} {
		set now [clock seconds]
		set sinceLastRead [expr {$now - $lastRead}]
		set sinceLastSend [expr {$now - $lastSend}]
		::rmq::debug "Heartbeat: $sinceLastRead secs since last read and $sinceLastSend secs since last send"

		# despite being able to send data on the socket, if we haven't heard anything
		# from the server for > 2 heartbeat intervals, we need to disconnect
		if {$sinceLastRead > 2 * $heartbeatSecs} {
			::rmq::debug "Been more than 2 heartbeat intervals without socket read activity, shutting down connection"
			return [my closeConnection]
		}

		# since we check whether to send a heartbeat every heartbeatSecs / 2 secs
		# need to check if we'd be over the heartbeat interval at the end of the
		# after wait if we did not send a heartbeat right now
		if {max($sinceLastRead, $sinceLastSend) >= $heartbeatSecs >> 1} {
			::rmq::debug "Sending heartbeat frame: long enough since last send or last read" 
			return [my send [::rmq::enc_frame $::rmq::FRAME_HEARTBEAT 0 ""]]
		}

		# set another timer for this method
		set heartbeatID [after [expr {1000 * $heartbeatSecs / 2}] [list [self] sendHeartbeat]]
	}

	#
	# break the binary data received from the RabbitMQ server
	# into a list of frames
	#
	#
	method splitFrames {data} {
		set frames [list]

		if {$partialFrame ne ""} {
			set data ${partialFrame}${data}
			set partialFrame ""
		}

		# requires at least 8 bytes for a frame
		while {[string length $data] >= 7} {
			# need to get the frame size
			binary scan $data @3Iu fsize
			::rmq::debug "Split frames size $fsize"

			# 8 bytes of the frame is non-payload data
			# 1 byte for type, 2 bytes for channel, 4 bytes for size, 1 byte for frame end
			lappend frames [string range $data 0 [expr {$fsize + 7}]]
			set data [string range $data [expr {$fsize + 8}] end]
		}

		if {$data ne ""} {
			::rmq::debug "Left over data in split frames, adding to the end of the frames"
			lappend frames $data
		}

		::rmq::debug "Received [llength $frames] frames"
		return $frames
	}

	#
	# set TLS options for connecting to RabbitMQ
	# supports all arguments supported by tls::import
	# as detailed at:
	#	http://tls.sourceforge.net/tls.htm
	#
	method tlsOptions {args} {
		if {[llength $args] & 1} {
			return -code error "Require an even number of args"
		}

		# if we reach here, tls is set for when the socket is created
		array set tlsOpts $args
		return [set tls 1]
	}
}

oo::define ::rmq::Connection {
	##
	##
	## AMQP Connection Class Method Handlers
	##
	##

	#
	# Connection.Start - given a frame containing
	#  containing the Connection.Start method, return
	#  a dict of the connection parameters contained
	#  in the server's data
	#
	method connectionStart {data} {
		::rmq::debug "Connection.Start"

		# starts with a protocol major and minor version
		binary scan $data cc versionMajor versionMinor
		if {$versionMajor ne $::rmq::AMQP_VMAJOR || \
			$versionMinor ne $::rmq::AMQP_VMINOR} {
			error "AMQP version $versionMajor.$versionMinor specified by server not supported"
		}
		set data [string range $data 2 end]

		# consists of a field table of parameters
		set connectionParams [::rmq::dec_field_table $data bytesProcessed]

		# and two more strings
		set data [string range $data $bytesProcessed end]

		# then have two longstr to parse
		set mechanisms [::rmq::dec_long_string $data bytesProcessed]
		dict set connectionParams mechanisms $mechanisms
		set data [string range $data $bytesProcessed end]

		set locale [::rmq::dec_long_string $data bytesProcessed]
		dict set connectionParams locale $locale
		set data [string range $data $bytesProcessed end]

		my connectionStartOk $connectionParams
	}

	#
	# Connection.StartOk - given a dict of Connection.Start
	#  parameters, send back a Connection.Ok response
	#  or disconnect and signal an error if anything
	#  goes wrong
	#
	method connectionStartOk {params} {
		::rmq::debug "Connection.StartOk"

		# first need to include the client properties
		set clientProps [dict create]

		# platform
		set valueType [::rmq::enc_field_value long-string]
		set value [::rmq::enc_long_string "Tcl [info tclversion]"]
		dict set clientProps platform "${valueType}${value}"

		# product
		set valueType [::rmq::enc_field_value long-string]
		set value [::rmq::enc_long_string $::rmq::PRODUCT]
		dict set clientProps product "${valueType}${value}"

		# version
		set valueType [::rmq::enc_field_value long-string]
		set value [::rmq::enc_long_string $::rmq::VERSION]
		dict set clientProps version "${valueType}${value}"

		# capabilities dict is not inspected by the broker
		# see https://www.rabbitmq.com/consumer-cancel.html#capabilities
		set capabilities [dict create]

		set valueType [::rmq::enc_field_value boolean]
		set value [::rmq::enc_byte 1]
	
		# connection.blocked (indicates we support connection.blocked methods)
		if {$blockedConnections} {
			dict set capabilities connection.blocked "${valueType}${value}"
		}

		# authetication_failure_closed
		# reuses the boolean valueType
		dict set capabilities authentication_failure_close "${valueType}${value}"

		# basic.nack
		# reuses the boolean valueType
		dict set capabilities basic.nack "${valueType}${value}"

		# whether consumer cancel notifications are supported
		if {$cancelNotifications} {
			dict set capabilities consumer_cancel_notify "${valueType}${value}"
		}

		# add the entire capabilities dict
		set valueType [::rmq::enc_field_value field-table]
		set value [::rmq::enc_field_table $capabilities]
		dict set clientProps capabilities "${valueType}${value}"

		# verify that the mechanism provided by this library supported by server
		if {[string first $::rmq::DEFAULT_MECHANISM [dict get $params mechanisms]] == -1} {
			::rmq::debug "tclrmq mechanism of $::rmq::DEFAULT_MECHANISM not supported by server [dict get $params mechanisms]"
			return [my closeConnection]
		}
		set mechanismVal [::rmq::enc_short_string $::rmq::DEFAULT_MECHANISM]

		# response
		set responseVal [::rmq::enc_long_string [$login saslResponse]]

		# Verify that the locale matches what we support
		if {$locale ne [dict get $params locale]} {
			::rmq::debug "Our locale of $locale not supported by server [dict get $params locale]"
			return [my closeConnection]
		}
		set localeVal [::rmq::enc_short_string $locale]

		# full payload for the frame
		set payload [::rmq::enc_field_table $clientProps]${mechanismVal}${responseVal}${localeVal}
		my send [::rmq::enc_frame 1 0 [::rmq::enc_method 10 11 $payload]]
	}

	method connectionTune {data} {
		::rmq::debug "Connection.Tune"

		set channelMax [::rmq::dec_short $data _]
		if {$channelMax == 0} {
			set maxChannels $::rmq::MAX_CHANNELS
		} else {
			set maxChannels $channelMax
		}

		set sFrameMax [::rmq::dec_ulong [string range $data 2 end] _]
		if {$sFrameMax != 0} {
			set frameMax $sFrameMax
		}

		set heartbeat [::rmq::dec_ushort [string range $data 6 end] _]
		::rmq::debug "Heartbeat interval of $heartbeat secs suggested by the server"
		my connectionTuneOk $channelMax $frameMax $heartbeat
	}

	method connectionTuneOk {channelMax frameMax heartbeat} {
		::rmq::debug "Connection.TuneOk"

		set channelMax [::rmq::enc_short $channelMax]
		set frameMax [::rmq::enc_ulong $frameMax]
		set heartbeat [::rmq::enc_ushort $heartbeatSecs]
		set methodData "${channelMax}${frameMax}${heartbeat}"

		set payload [::rmq::enc_method 10 31 $methodData]
		my send [::rmq::enc_frame 1 0 $payload]

		# after heartbeats have been negotiated, setup a loop to send them
		if {$heartbeatSecs != 0} {
			::rmq::debug "Scheduling first heartbeat check..."
			set heartbeatID [after [expr {1000 * $heartbeatSecs / 2}] [list [self] sendHeartbeat]]
		}

		my connectionOpen
	}

	method connectionSecure {data} {
		::rmq::debug "Connection.Secure"

		set challenge [::rmq::dec_long_string $data _]
		my connectionSecureOk $challenge
	}

	method connectionSecureOk {challenge} {
		::rmq::debug "Connection.SecureOk"

		set resp [::rmq::enc_long_string [$login saslResponse]]
		set payload [::rmq::enc_method 10 21 $resp]
		my send [::rmq::enc_frame 1 0 $payload]
	}

	method connectionOpen {} {
		::rmq::debug "Connection.Open vhost [$login getVhost]"

		set vhostVal [::rmq::enc_short_string [$login getVhost]]
		set reserve1 [::rmq::enc_short_string ""]
		set reserve2 [::rmq::enc_byte 1]
		set payload "${vhostVal}${reserve1}${reserve2}"

		set methodData [::rmq::enc_method 10 40 $payload]
		my send [::rmq::enc_frame 1 0 $methodData]
	}

	method connectionOpenOk {data} {
		# this method signals the connection is ready
		set connected 1

		::rmq::debug "Connection.OpenOk: connection now established"

		# call user supplied callback for when a connection is established
		if {$connectedCB ne ""} {
			$connectedCB [self]
		}
	}

	method connectionClose {{data ""} {replyCode 200} {replyText "Normal"} {cID 0} {mID 0}} {
		dict set closeD data $data replyCode $replyCode replyText $replyText \
						classID $cID methodID $mID

		# if data is blank, we are sending this method
		# otherwise, this message was received
		if {$data eq ""} {
			::rmq::debug "Connection.Close"
			set replyCode [::rmq::enc_short $replyCode]
			set replyText [::rmq::enc_short_string $replyText]
			set classID [::rmq::enc_short $cID]
			set methodID [::rmq::enc_short $mID]

			set methodData "${replyCode}${replyText}${classID}${methodID}"
			set methodData [::rmq::enc_method $::rmq::CONNECTION_CLASS \
				$::rmq::CONNECTION_CLOSE $methodData]
			my send [::rmq::enc_frame $::rmq::FRAME_METHOD 0 $methodData]
		} else {
			set replyCode [::rmq::dec_short $data _]
			set replyText [::rmq::dec_short_string [string range $data 2 end] bytes]
			set data [string range $data [expr {2 + $bytes}] end]
			set classID [::rmq::dec_short $data _]
			set methodID [::rmq::dec_short [string range $data 2 end] _]

			::rmq::debug "Connection.Close (${replyCode}: $replyText) (classID $classID methodID $methodID)"

			# send Connection.Close-Ok
			my sendConnectionCloseOk
		}
	}

	method connectionCloseOk {data} {
		::rmq::debug "Connection.CloseOk"
		my closeConnection 
	}

	method sendConnectionCloseOk {} {
		::rmq::debug "Sending Connection.CloseOk"
		set methodData [::rmq::enc_method $::rmq::CONNECTION_CLASS \
			$::rmq::CONNECTION_CLOSE_OK ""]
		my send [::rmq::enc_frame $::rmq::FRAME_METHOD 0 $methodData]
		my closeConnection
	}

	method connectionBlocked {data} {
		::rmq::debug "Connection.Blocked"

		set blocked 1
		set reason [::rmq::dec_short_string $data _]
		if {$BlockedCB ne ""} {
			$blockedCB [self] $blocked $reason
		}
	}

	method connectionUnblocked {data} {
		::rmq::debug "Connection.Unblocked"

		set blocked 0
		if {$blockedCB ne ""} {
			$blockedCB [self] $blocked ""
		}
	}
}


# vim: ts=4:sw=4:sts=4:noet
