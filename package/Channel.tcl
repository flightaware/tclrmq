package provide rmq 1.3.1

package require TclOO

namespace eval rmq {
	namespace export Channel
}

oo::class create ::rmq::Channel {
	# channel is always attached to a connection object
	# and always has an unsigned int for referring to it
	variable connection
	variable num

	# track whether the channel is open or not
	variable opened

	# track whether the channel is active or not
	# as controlled by Channel flow methods
	variable active

	# track whether the channel is closing or not
	variable closing

	# metadata from Connection.Close
	variable closeD

	# whether the channel is in confirm mode
	# and, if so, the publish number of the next message
	variable confirmMode
	variable publishNumber

	# can set a callback for when the channel is open or closed
	# or when the channel receives an error code
	variable openCB
	variable closedCB
	variable errorCB

	# more general way of setting a callback on any other method
	variable callbacksD

	constructor {connectionObj {channelNum ""} {shouldOpen 1}} {
		set connection $connectionObj
		if {$channelNum eq "" || $channelNum <= 0} {
			set num [$connection getNextChannel]
		} else {
			set num $channelNum
		}

		# store the channel number in the connection
		# so that responses for this channel can be
		# received accordingly
		$connection saveChannel $num [self]

		# not opened yet
		set opened 0

		# not yet active
		set active 0

		# not closing
		set closing 0

		# no closing metadata yet
		set closeD [dict create]

		# not in cofirm mode
		set confirmMode 0

		# callbacks for major channel events
		set openCB ""
		set closedCB ""
		set errorCB ""

		# callbacks for all other methods
		# maps a string of the method to its callback
		set callbacksD [dict create]

		# handling for Basic method callbacks
		set methodData [dict create]
		set frameData [dict create]
		set receivedData ""
		array set consumerCBs {}
		set consumerCBArgs [list]
		set lastBasicMethod ""

		# send the frame to open the channel if specified
		if {$shouldOpen} {
			my channelOpen
		}
	}

	method active? {} {
		return $active
	}

	method closeChannel {} {
		set opened 0
		set active 0
		set closing 0

		if {$closedCB ne ""} {
			$closedCB [self] $closeD
		}
	}

	method closeConnection {} {
		$connection closeConnection
	}

	method closing? {} {
		return $closing
	}

	method callback {methodName args} {
		if {[dict exists $callbacksD $methodName]} {
			[dict get $callbacksD $methodName] [self] {*}$args
		}
	}

	method contentBody {data} {
		::rmq::debug "Channel $num processing a content body frame"

		# add the current blob of data to the receivedData variable
		append receivedData $data

		# validate that the frameData variable actually contains
		# the key we are looking for and, if not, respond with an
		# appropriate error code
		if {![dict exists $frameData bodySize]} {
			# Error code 406 means a precondition failed
			::rmq::debug "Frame data dict does not contain expected bodySize variable"
			return [$connection send [::rmq::enc_frame 406 0 ""]]
		} else {
			::rmq::debug "Expecting [dict get $frameData bodySize] bytes of data"
		}

		if {[string length $receivedData] == [dict get $frameData bodySize]} {
			::rmq::debug "Received all the data for the content, invoking necessary callback"

			# reset all variables used to keep track of consumed data
			set consumerCBArgs [list $methodData $frameData $receivedData]

			set methodData [dict create]
			set frameData [dict create]
			set receivedData ""

			# invoke the callback
			if {$lastBasicMethod eq "deliver"} {
				set cTag [dict get [lindex $consumerCBArgs 0] consumerTag]
				$consumerCBs($cTag) [self] {*}$consumerCBArgs
			} elseif {$lastBasicMethod eq "get"} {
				my callback basicDeliver {*}$consumerCBArgs
			} elseif {$lastBasicMethod eq "return"} {
				my callback basicReturn {*}$consumerCBArgs
			} else {
				::rmq::debug "Received enqueued data ($consumerCBArgs) but no callback set"
			}
		} else {
			::rmq::debug "Received [string length $receivedData] bytes so far"
		}
	}

	method contentHeader {headerD} {
		::rmq::debug "Channel $num processing a content header frame: $headerD"
		set frameData $headerD
	}

	method errorHandler {errorCode data} {
		::rmq::debug "Channel error handler with code $errorCode and data $data"

		if {$errorCB ne ""} {
			$errorCB [self] $errorCode $data
		}
	}

	method getCallback {amqpMethod} {
		if {[dict exists $callbacksD $amqpMethod]} {
			return [dict get $callbacksD $amqpMethod]
		}
	}

	method getChannelNum {} {
		return $num
	}

	method getConnection {} {
		return $connection
	}

	method getConsumerCallbackArgs {} {
		return $consumerCBArgs
	}

	method getFrameData {} {
		return $frameData
	}

	method getMethodData {} {
		return $methodData
	}

	method getReceivedData {} {
		return $receivedData
	}

	method open? {} {
		return $opened
	}

	#
	# alias for setCallback method
	#
	method on {amqpMethod cb} {
		dict set callbacksD $amqpMethod $cb
	}

	method onConnect {cb} {
		set openCB $cb
	}

	method onConnected {cb} {
		set openCB $cb
	}

	method onOpen {cb} {
		set openCB $cb
	}

	method onOpened {cb} {
		set openCB $cb
	}

	method onClose {cb} {
		set closedCB $cb
	}

	method onClosed {cb} {
		set closedCB $cb
	}

	method onError {cb} {
		set errorCB $cb
	}

	method removeCallback {amqpMethod} {
		dict unset callbacksD $amqpMethod
	}

	method removeCallbacks {} {
		set callbacksD [dict create]
		array unset consumerCBs
		array set consumerCBs {}
	}

	method setCallback {amqpMethod cb} {
		dict set callbacksD $amqpMethod $cb
	}
}

##
##
## AMQP Channel Methods
##
##
oo::define ::rmq::Channel {
	method channelClose {{data ""} {replyCode 200} {replyText "Normal"} {cID 0} {mID 0}} {
		::rmq::debug "Channel.Close"
		dict set closeD data $data replyCode $replyCode replyText $replyText \
				 classID $cID methodID $mID
		set closing 1

		if {$data eq ""} {
			# need to send a Channel.Close frame
			set rCode [::rmq::enc_short $replyCode]
			set rText [::rmq::enc_short_string $replyText]
			set cID [::rmq::enc_short $cID]
			set mID [::rmq::enc_short $mID]

			set methodData "${replyCode}${replyText}${cID}${mID}"
			set methodData [::rmq::enc_method $::rmq::CHANNEL_CLASS $::rmq::CHANNEL_CLOSE $methodData]
			$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodData]
		} else {
			# received a Channel.Close frame
			set replyCode [::rmq::dec_short $data _]
			set replyText [::rmq::dec_short_string [string range $data 2 end] bytes]
			set data [string range $data [expr {2 + $bytes}] end]
			set classID [::rmq::dec_short $data _]
			set methodID [::rmq::dec_short [string range $data 2 end] _]

			# send Connection.Close-Ok
			my sendChannelCloseOk

			# invoke channel closed callback
			::rmq::debug "Channel.CloseOk \[$num\] (${replyCode}: $replyText) (classID $classID methodID $methodID)"
		}
	}

	method channelCloseOk {data} {
		::rmq::debug "Channel.CloseOk"
		my closeChannel
	}

	method channelFlow {data} {
		::rmq::debug "Channel.Flow"
		set active [::rmq::dec_byte $data _]
		my sendChannelFlowOk
	}

	method channelFlowOk {data} {
		set active [::rmq::dec_byte $data _]
		::rmq::debug "Channel.FlowOk (active $active)"
	}

	method channelOpen {} {
		::rmq::debug "Channel.Open channel $num"

		set payload [::rmq::enc_short_string ""]
		set payload [::rmq::enc_method $::rmq::CHANNEL_CLASS $::rmq::CHANNEL_OPEN $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $payload]
	}

	method channelOpenOk {data} {
		::rmq::debug "Channel.OpenOk channel $num"
		set opened 1
		set active 1

		if {$openCB ne ""} {
			$openCB [self]
		}
	}

	method sendChannelCloseOk {} {
		set methodData [::rmq::enc_method $::rmq::CHANNEL_CLASS $::rmq::CHANNEL_CLOSE_OK ""]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodData]
		my closeChannel
	}

	method sendChannelFlow {flowActive} {
		::rmq::debug "Sending Channel.Flow (active $flowActive)"

		set payload [::rmq::enc_byte $flowActive]
		set payload [::rmq::enc_method $::rmq::CHANNEL_CLASS $::rmq::CHANNEL_FLOW $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $payload]
	}

	method sendChannelFlowOk {} {
		::rmq::debug "Sending Channel.FlowOk (active $active)"

		set payload [::rmq::enc_byte $active]
		set payload [::rmq::enc_method $::rmq::CHANNEL_CLASS $::rmq::CHANNEL_FLOW $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $payload]
	}
}

##
##
## AMQP Exchange Methods
##
##
oo::define ::rmq::Channel {
	method exchangeBind {dst src rKey {noWait 0} {eArgs ""}} {
		::rmq::debug "Channel $num Exchange.Bind"

		# there's a reserved short field
		set reserved [::rmq::enc_short 0]

		# name of the destination exchange to bind
		set dst [::rmq::enc_short_string $dst]

		# name of the source exchange to bind
		set src [::rmq::enc_short_string $src]

		# routing key for the binding
		set rKey [::rmq::enc_short_string $rKey]

		# whether or not to wait on a response
		set noWait [::rmq::enc_byte $noWait]

		# additional args as a field table
		set eArgs [::rmq::enc_field_table $eArgs]

		# build up the payload to send
		set payload "${reserved}${dst}${src}${rKey}${noWait}${eArgs}"
		set methodLayer [::rmq::enc_method $::rmq::EXCHANGE_CLASS \
			$::rmq::EXCHANGE_BIND $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method exchangeBindOk {data} {
		::rmq::debug "Channel $num Exchange.BindOk"

		# nothing really passed into this method
		my callback exchangeBindOk ""
	}

	method exchangeDeclare {eName eType {eFlags ""} {eArgs ""}} {
		::rmq::debug "Channel $num Exchange.Declare"

		# there's a reserved short field
		set reserved [::rmq::enc_short 0]

		# need the exchange name and type
		set eName [::rmq::enc_short_string $eName]
		set eType [::rmq::enc_short_string $eType]

		# set the series of flags (from low-to-high)
		# passive, durable, auto-delete, internal, no-wait
		set flags 0
		foreach eFlag $eFlags {
			set flags [expr {$flags | $eFlag}]
		}
		set flags [::rmq::enc_byte $flags]

		# possible to have a field table of arguments
		set eArgs [::rmq::enc_field_table $eArgs]

		# build up the payload to send
		set payload "${reserved}${eName}${eType}${flags}${eArgs}"
		set methodLayer [::rmq::enc_method $::rmq::EXCHANGE_CLASS \
			$::rmq::EXCHANGE_DECLARE $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name exchangeDeclareOk
	#
	method exchangeDeclareOk {data} {
		::rmq::debug "Channel $num Exchange.DeclareOk"

		set eDeclareCB [my getCallback exchangeDeclareOk]
		if {$eDeclareCB ne ""} {
			$eDeclareCB [self]
		}
	}

	method exchangeDelete {eName {inUse 0} {noWait 0}} {
		::rmq::debug "Channel $num Exchange.Delete"

		# reserved short field
		set reserved [::rmq::enc_short 0]

		# set the exchange name
		set eName [::rmq::enc_short_string $eName]

		# set the bit fields for in-use and no-wait
		set flags 0
		if {$inUse} {
			set flags [expr {$flags | 1}]
		}

		if {$noWait} {
			set flags [expr {$flags | 2}]
		}
		set flags [::rmq::enc_byte $flags]

		# now can package this up and send
		set payload "${reserved}${eName}${flags}"
		set methodLayer [::rmq::enc_method $::rmq::EXCHANGE_CLASS \
			$::rmq::EXCHANGE_DELETE $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name exchangeDeleteOk
	#
	method exchangeDeleteOk {data} {
		::rmq::debug "Channel $num Exchange.DeleteOk"

		set eDeleteCB [my getCallback exchangeDeleteOk]
		if {$eDeleteCB ne ""} {
			$eDeleteCB [self]
		}
	}

	method exchangeUnbind {dst src rKey {noWait 0} {eArgs ""}} {
		::rmq::debug "Channel $num Exchange.Unbind"
		# there's a reserved short field
		set reserved [::rmq::enc_short 0]

		# name of the destination exchange to bind
		set dst [::rmq::enc_short_string $dst]

		# name of the source exchange to bind
		set src [::rmq::enc_short_string $src]

		# routing key for the binding
		set rKey [::rmq::enc_short_string $rKey]

		# whether or not to wait on a response
		set noWait [::rmq::enc_byte $noWait]

		# additional args as a field table
		set eArgs [::rmq::enc_field_table $eArgs]

		# build up the payload to send
		set payload "${reserved}${dst}${src}${rKey}${noWait}${eArgs}"
		set methodLayer [::rmq::enc_method $::rmq::EXCHANGE_CLASS \
			$::rmq::EXCHANGE_UNBIND $payload]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method exchangeUnbindOk {data} {
		::rmq::debug "Channel $num Exchange.UnbindOk"

		# nothing really passed into this method
		my callback exchangeUnbindOk ""
	}
}

##
##
## AMQP Queue Methods
##
##
oo::define ::rmq::Channel {
	method queueBind {qName eName {rKey ""} {noWait 0} {qArgs ""}} {
		::rmq::debug "Queue.Bind"

		# deprecated short ticket field set to 0
		set ticket [::rmq::enc_short 0]

		# queue name
		set qName [::rmq::enc_short_string $qName]

		# exchange name
		set eName [::rmq::enc_short_string $eName]

		# routing key
		set rKey [::rmq::enc_short_string $rKey]

		# no wait bit
		set noWait [::rmq::enc_byte $noWait]

		# additional args as a field table
		set qArgs [::rmq::enc_field_table $qArgs]

		# now ready to send the payload
		set methodLayer [::rmq::enc_method $::rmq::QUEUE_CLASS \
			$::rmq::QUEUE_BIND \
			${ticket}${qName}${eName}${rKey}${noWait}${qArgs}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name queueBindOk
	#
	method queueBindOk {data} {
		::rmq::debug "Queue.BindOk"

		# No parameters included
		set qBindCB [my getCallback queueBindOk]
		if {$qBindCB ne ""} {
			$qBindCB [self]
		}
	}

	method queueDeclare {qName {qFlags ""} {qArgs ""}} {
		::rmq::debug "Queue.Declare"

		# a short reserved field
		set reserved [::rmq::enc_short 0]

		# queue name
		set qName [::rmq::enc_short_string $qName]

		# passive, durable, exclusive, auto-delete, no-wait
		set flags 0
		foreach qFlag $qFlags {
			set flags [expr {$flags | $qFlag}]
		}
		set flags [::rmq::enc_byte $flags]

		# arguments for declaration
		set qArgs [::rmq::enc_field_table $qArgs]

		# create the method frame with its payload
		set methodLayer [::rmq::enc_method $::rmq::QUEUE_CLASS \
			$::rmq::QUEUE_DECLARE \
			${reserved}${qName}${flags}${qArgs}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name queueDeclareOk
	#
	method queueDeclareOk {data} {
		# Grab the data from the response
		set qName [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set msgCount [::rmq::dec_ulong $data bytes]
		set data [string range $data $bytes end]

		set consumers [::rmq::dec_ulong $data bytes]

		::rmq::debug "Queue.DeclareOk (name $qName) (msgs $msgCount) (consumers $consumers)"

		set qDeclareCB [my getCallback queueDeclareOk]
		if {$qDeclareCB ne ""} {
			$qDeclareCB [self] $qName $msgCount $consumers
		}
	}

	method queueDelete {qName {flags ""}} {
		::rmq::debug "Queue.Delete"

		set reserved [::rmq::enc_short 0]

		set qName [::rmq::enc_short_string $qName]

		set dFlags 0
		foreach flag $flags {
			set dFlags [expr {$dFlags | $flag}]
		}
		set dFlags [::rmq::enc_byte $dFlags]

		set methodLayer [::rmq::enc_method $::rmq::QUEUE_CLASS \
			$::rmq::QUEUE_DELETE \
			${reserved}${qName}${dFlags}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name queueDeleteOk
	#
	method queueDeleteOk {data} {
		::rmq::debug "Queue.DeleteOk"

		set msgCount [::rmq::dec_ulong $data _]

		set qDeleteCB [my getCallback queueDeleteOk]
		if {$qDeleteCB ne ""} {
			$qDeleteCB [self] $msgCount
		}
	}

	method queuePurge {qName {noWait 0}} {
		::rmq::debug "Queue.Purge"

		# reserved short field
		set reserved [::rmq::enc_short 0]

		# queue name
		set qName [::rmq::enc_short_string $qName]

		# no wait bit
		set noWait [::rmq::enc_byte $noWait]

		set methodLayer [::rmq::enc_method $::rmq::QUEUE_CLASS \
			$::rmq::QUEUE_PURGE \
			${reserved}${qName}${noWait}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name queuePurgeOk
	#
	method queuePurgeOk {data} {
		::rmq::debug "Queue.PurgeOk"

		set msgCount [::rmq::dec_ulong $data _]

		set qPurgeCB [my getCallback queuePurgeOk]
		if {$qPurgeCB ne ""} {
			$qPurgeCB [self] $msgCount
		}
	}

	method queueUnbind {qName eName rKey {qArgs ""}} {
		::rmq::debug "Queue.Unbind"

		# reserved short field
		set reserved [::rmq::enc_short 0]

		# queue name
		set qName [::rmq::enc_short_string $qName]

		# exchange name
		set eName [::rmq::enc_short_string $eName]

		# routing key
		set rKey [::rmq::enc_short_string $rKey]

		# additional arguments
		set qArgs [::rmq::enc_field_table $qArgs]

		# bundle it up and send it off
		set methodLayer [::rmq::enc_method $::rmq::QUEUE_CLASS \
			$::rmq::QUEUE_UNBIND \
			${reserved}${qName}${eName}${rKey}${qArgs}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	#
	# set a callback with the name queueUnbindOk
	#
	method queueUnbindOk {data} {
		::rmq::debug "Queue.UnbindOk"

		# No parameters included
		set qUnbindCB [my getCallback queueUnbindOk]
		if {$qUnbindCB ne ""} {
			$qUnbindCB [self]
		}
	}
}

##
##
## AMQP Basic Methods
##
##
oo::define ::rmq::Channel {
	# housekeeping for the receiving of data
	variable lastBasicMethod
	variable methodData
	variable frameData
	variable receivedData
	variable consumerCBs
	variable consumerCBArgs

	method basicAck {deliveryTag {multiple 0}} {
		::rmq::debug "Basic.Ack"

		set deliveryTag [::rmq::enc_ulong_long $deliveryTag]
		set multiple [::rmq::enc_byte $multiple]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_ACK ${deliveryTag}${multiple}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicAckReceived {data} {
		set deliveryTag [::rmq::dec_ulong_long $data bytes]
		set multiple [::rmq::dec_byte [string range $data $bytes end] _]
		::rmq::debug "Basic.Ack received for $deliveryTag with multiple ($multiple)"

		if {$multiple} {
			set publishNumber [expr {$deliveryTag + 1}]
		} elseif {$publishNumber == $deliveryTag} {
			incr publishNumber
		} else {
			::rmq::debug "Basic.Ack received for $deliveryTag but expecting $publishNumber"
		}

		set bAckCB [my getCallback basicAck]
		if {$bAckCB ne ""} {
			$bAckCB [self] $deliveryTag $multiple
		}
	}

	method basicConsume {callback qName {cTag ""} {cFlags ""} {cArgs ""}} {
		::rmq::debug "Basic.Consume"

		# setup for the callback
		my setCallback basicDeliver $callback
		set consumerCBs($cTag) $callback

		set reserved [::rmq::enc_short 0]
		set qName [::rmq::enc_short_string $qName]
		set cTag [::rmq::enc_short_string $cTag]

		# no-local, no-ack, exclusive, no-wait
		set flags 0
		foreach cFlag $cFlags {
			set flags [expr {$flags | $cFlag}]
		}
		set flags [::rmq::enc_byte $flags]

		set cArgs [::rmq::enc_field_table $cArgs]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_CONSUME \
			${reserved}${qName}${cTag}${flags}${cArgs}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicConsumeOk {data} {
		set cTag [::rmq::dec_short_string $data _]
		::rmq::debug "Basic.ConsumeOk (consumer tag: $cTag)"

		# if just learned the consumer tag, update callbacks array
		if {[info exists consumerCBs("")]} {
			::rmq::debug "With server generated consumer tag, unsetting empty callback key"	
			set consumerCBs($cTag) $consumerCBs("")
			unset consumerCBs("")
		}

		set bConsumeCB [my getCallback basicConsumeOk]
		if {$bConsumeCB ne ""} {
			$bConsumeCB [self] $cTag
		}
	}

	method basicCancel {cTag {noWait 0}} {
		::rmq::debug "Basic.Cancel"

		set cTag [::rmq::enc_short_string $cTag]
		set noWait [::rmq::enc_byte $noWait]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_CANCEL \
			${cTag}${noWait}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]

		# unset any get or deliver callbacks
		array unset consumerCBs $cTag
	}

	method basicCancelOk {data} {
		::rmq::debug "Basic.CancelOk"

		set cTag [::rmq::dec_short_string $data _]

		set bCancelCB [my getCallback basicCancelOk]
		if {$bCancelCB ne ""} {
			$bCancelCB [self] $cTag
		}
	}

	method basicCancelRecv {data} {
		set cTag [::rmq::dec_short_string $data _]

		::rmq::debug "Basic.Cancel received for consumer tag $cTag"

		array unset consumerCBs $cTag

		set bCancelCB [my getCallback basicCancel]
		if {$bCancelCB ne ""} {
			$bCancelCB [self] $cTag
		}
	}

	method basicDeliver {data} {
		::rmq::debug "Basic.Deliver"

		set cTag [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set dTag [::rmq::dec_ulong_long $data bytes]
		set data [string range $data $bytes end]

		set redelivered [::rmq::dec_byte $data bytes]
		set data [string range $data $bytes end]

		set eName [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set rKey [::rmq::dec_short_string $data bytes]

		# save the basic deliver data for passing to the user
		# callback after the body frame is received
		set methodData [dict create \
			consumerTag $cTag \
			deliveryTag $dTag \
			redelivered $redelivered \
			exchange $eName \
			routingKey $rKey]
		set lastBasicMethod deliver
	}

	method basicGet {callback qName {noAck 1}} {
		::rmq::debug "Basic.Get"

		my setCallback basicDeliver $callback
		set lastBasicMethod get

		set reserved [::rmq::enc_short 0]
		set qName [::rmq::enc_short_string $qName]
		set noAck [::rmq::enc_byte $noAck]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_GET \
			${reserved}${qName}${noAck}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicGetEmpty {data} {
		::rmq::debug "Basic.GetEmpty"

		# only have a single reserved parameter

		# save an empty method data dict for this case
		set methodData [dict create]
		set lastBasicMethod get
	}

	method basicGetOk {data} {
		::rmq::debug "Basic.GetOk"

		set dTag [::rmq::dec_ulong_long $data bytes]
		set data [string range $data $bytes end]

		set redelivered [::rmq::dec_byte $data bytes]
		set data [string range $data $bytes end]

		set eName [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set rKey [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set msgCount [::rmq::dec_ulong $data bytes]

		# save the basic get data for passing to the user
		# callback after the body frame is received
		set methodData [dict create \
			deliveryTag $dTag \
			redelivered $redelivered \
			exchange $eName \
			routingKey $rKey \
			messageCount $msgCount]
		set lastBasicMethod get
	}

	method basicQos {prefetchCount {globalQos 0}} {
		::rmq::debug "Basic.Qos"

		# prefetchSize is always 0 for RabbitMQ as any other
		# value is unsupported and will lead to a channel error
		set prefetchSize [::rmq::enc_ulong 0]
		set prefetchCount [::rmq::enc_ushort $prefetchCount]
		set globalQos [::rmq::enc_byte $globalQos]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_QOS \
			${prefetchSize}${prefetchCount}${globalQos}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicNack {deliveryTag {nackFlags ""}} {
		::rmq::debug "Basic.Nack"

		set deliveryTag [::rmq::enc_ulong_long $deliveryTag]

		# multiple, requeue
		set flags 0
		foreach nackFlag $nackFlags {
			set flags [expr {$flags | $nackFlag}]
		}
		set flags [::rmq::enc_byte $flags]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_NACK ${deliveryTag}${flags}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicNackReceived {data} {
		set deliveryTag [::rmq::dec_ulong_long $data bytes]

		# If the multiple field is 1, and the delivery tag is zero,
		# this indicates rejection of all outstanding messages.
		set multiple [::rmq::dec_byte [string range $data $bytes end] _]
		::rmq::debug "Basic.Nack received for $deliveryTag with multiple ($multiple)"

		# there is also a requeue bit in the data but the spec says
		# "Clients receiving the Nack methods should ignore this flag."

		set bNackCB [my getCallback basicNack]
		if {$bNackCB ne ""} {
			$bNackCB [self] $deliveryTag $multiple
		}
	}

	method basicQosOk {data} {
		::rmq::debug "Basic.QosOk"

		# no parameters included
		set bQosCB [my getCallback basicQosOk]
		if {$bQosCB ne ""} {
			$bQosCB [self]
		}
	}

	method basicPublish {data eName rKey {pFlags ""} {props ""}} {
		::rmq::debug "Basic.Publish to exchange $eName w/ routing key $rKey"

		set reserved [::rmq::enc_short 0]
		set eName [::rmq::enc_short_string $eName]
		set rKey [::rmq::enc_short_string $rKey]

		# mandatory, immediate
		set flags 0
		foreach pFlag $pFlags {
			set flags [expr {$flags | $pFlag}]
		}
		set flags [::rmq::enc_byte $flags]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_PUBLISH \
			${reserved}${eName}${rKey}${flags}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]

		# after sending the basic publish method, now need to send the data
		# this requires sending a content header and then a content body
		set bodyLen [string length $data]
		set header [::rmq::enc_content_header $::rmq::BASIC_CLASS $bodyLen $props]
		$connection send [::rmq::enc_frame $::rmq::FRAME_HEADER $num $header]

		# might need to break content up into several frames
		set maxPayload [expr {[$connection getFrameMax] - 8}]
		set bytesSent 0
		while {$bytesSent < $bodyLen} {
			set payload [string range $data $bytesSent [expr {$bytesSent + $maxPayload - 1}]]
			$connection send [::rmq::enc_frame $::rmq::FRAME_BODY $num $payload]
			incr bytesSent $maxPayload
		}
	}

	method basicRecover {reQueue} {
		::rmq::debug "Basic.Recover"
		set reQueue [::rmq::enc_byte $reQueue]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_RECOVER ${reQueue}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicRecoverAsync {reQueue} {
		::rmq::debug "Basic.RecoverAsync (deprecated by Reject/Reject-Ok)"

		set reQueue [::rmq::enc_byte $reQueue]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_RECOVER_ASYNC ${reQueue}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicRecoverOk {data} {
		::rmq::debug "Basic.RecoverOk"

		# no parameters
		set bRecoverCB [my getCallback basicRecoverOk]
		if {$bRecoverCB ne ""} {
			$bRecoverCB [self]
		}
	}

	method basicReject {deliveryTag {reQueue 0}} {
		::rmq::debug "Basic.Reject"

		set deliveryTag [::rmq::enc_ulong_long $deliveryTag]
		set reQueue [::rmq::enc_byte $reQueue]

		set methodLayer [::rmq::enc_method $::rmq::BASIC_CLASS \
			$::rmq::BASIC_REJECT ${deliveryTag}${reQueue}]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method basicReturn {data} {
		::rmq::debug "Basic.Return"

		set replyCode [::rmq::dec_short $data bytes]
		set data [string range $data $bytes end]

		set replyText [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set exchange [::rmq::dec_short_string $data bytes]
		set data [string range $data $bytes end]

		set routingKey [::rmq::dec_short_string $data bytes]

		set methodData [dict create \
			replyCode $replyCode \
			replyText $replyText \
			exchange $exchange \
			routingKey $routingKey]
		set lastBasicMethod return
	}
}

##
##
## AMQP Confirm Methods
##
##
oo::define ::rmq::Channel {
	method confirmSelect {{noWait 0}} {
		::rmq::debug "Confirm.Select"

		set noWait [::rmq::enc_byte $noWait]
		set methodLayer [::rmq::enc_method $::rmq::CONFIRM_CLASS \
			$::rmq::CONFIRM_SELECT $noWait]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD $num $methodLayer]
	}

	method confirmSelectOk {data} {
		::rmq::debug "Confirm.SelectOk (now in confirm mode)"
		set confirmMode 1
		set publishNumber 1

		set cSelectCB [my getCallback confirmSelectOk]
		if {$cSelectCB ne ""} {
			$cSelectCB [self]
		}
	}
}

##
##
## AMQP TX Methods
##
##
oo::define ::rmq::Channel {
	method txSelect {} {
		::rmq::debug "Tx.Select"

		# no parameters for this method
		set methodLayer [::rmq::enc_method $::rmq::TX_CLASS \
			$::rmq::TX_SELECT ""]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD \
			$num $methodLayer]
	}

	method txSelectOk {data} {
		::rmq::debug "Tx.SelectOk"

		# no parameters
		set tSelectCB [my getCallback txSelectOk]
		if {$tSelectCB ne ""} {
			$tSelectCB [self]
		}
	}

	method txCommit {} {
		::rmq::debug "Tx.Commit"

		# no parameters
		set methodLayer [::rmq::enc_method $::rmq::TX_CLASS \
			$::rmq::TX_COMMIT ""]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD \
			$num $methodLayer]
	}

	method txCommitOk {data} {
		::rmq::debug "Tx.CommitOk"

		# no parameters
		set tCommitCB [my getCallback txCommitOk]
		if {$tCommitCB ne ""} {
			$tCommitCB [self]
		}
	}

	method txRollback {} {
		::rmq::debug "Tx.Rollback"

		# no parameters
		set methodLayer [::rmq::enc_method $::rmq::TX_CLASS \
			$::rmq::TX_ROLLBACK ""]
		$connection send [::rmq::enc_frame $::rmq::FRAME_METHOD \
			$num $methodLayer]
	}

	method txRollbackOk {data} {
		::rmq::debug "Tx.RollbackOk"

		# no parameters
		set tRollbackCB [my getCallback txRollbackOk]
		if {$tRollbackCB ne ""} {
			$tRollbackCB [self]
		}
	}
}

# vim: ts=4:sw=4:sts=4:noet
