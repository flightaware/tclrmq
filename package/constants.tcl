package provide rmq 1.3.5

namespace eval rmq {
	# Frame types
	set FRAME_METHOD 1
	set FRAME_HEADER 2
	set FRAME_BODY 3
	set FRAME_HEARTBEAT 8
	set FRAME_MIN_SIZE 4096
	set FRAME_END "\xCE"

	# Class names
	set CONNECTION_CLASS 10
	set CHANNEL_CLASS 20
	set EXCHANGE_CLASS 40
	set QUEUE_CLASS 50
	set BASIC_CLASS 60
	set CONFIRM_CLASS 85
	set TX_CLASS 90

	set CHANNEL_CLASSES [list $CHANNEL_CLASS $EXCHANGE_CLASS \
		$QUEUE_CLASS $BASIC_CLASS \
		$CONFIRM_CLASS $TX_CLASS]

	##
	## Methods
	##
	set CONNECTION_START 10
	set CONNECTION_START_OK 11
	set CONNECTION_SECURE 20
	set CONNECTION_SECURE_OK 21
	set CONNECTION_TUNE 30
	set CONNECTION_TUNE_OK 31
	set CONNECTION_OPEN 40
	set CONNECTION_OPEN_OK 41
	set CONNECTION_CLOSE 50
	set CONNECTION_CLOSE_OK 51
	set CONNECTION_BLOCKED 60
	set CONNECTION_UNBLOCKED 61

	set CHANNEL_OPEN 10
	set CHANNEL_OPEN_OK 11
	set CHANNEL_FLOW 20
	set CHANNEL_FLOW_OK 21
	set CHANNEL_CLOSE 40
	set CHANNEL_CLOSE_OK 41

	set EXCHANGE_DECLARE 10
	set EXCHANGE_DECLARE_OK 11
	set EXCHANGE_DELETE 20
	set EXCHANGE_DELETE_OK 21
	set EXCHANGE_BIND 30
	set EXCHANGE_BIND_OK 31
	set EXCHANGE_UNBIND 40
	set EXCHANGE_UNBIND_OK 41

	set QUEUE_DECLARE 10
	set QUEUE_DECLARE_OK 11
	set QUEUE_BIND 20
	set QUEUE_BIND_OK 21
	set QUEUE_UNBIND 50
	set QUEUE_UNBIND_OK 51
	set QUEUE_PURGE 30
	set QUEUE_PURGE_OK 31
	set QUEUE_DELETE 40
	set QUEUE_DELETE_OK 41

	set BASIC_QOS 10
	set BASIC_QOS_OK 11
	set BASIC_CONSUME 20
	set BASIC_CONSUME_OK 21
	set BASIC_CANCEL 30
	set BASIC_CANCEL_OK 31
	set BASIC_PUBLISH 40
	set BASIC_RETURN 50
	set BASIC_DELIVER 60
	set BASIC_GET 70
	set BASIC_GET_OK 71
	set BASIC_GET_EMPTY 72
	set BASIC_ACK 80
	set BASIC_REJECT 90
	set BASIC_RECOVER_ASYNC 100
	set BASIC_RECOVER 110
	set BASIC_RECOVER_OK 111
	set BASIC_NACK 120

	set CONFIRM_SELECT 10
	set CONFIRM_SELECT_OK 11

	set TX_SELECT 10
	set TX_SELECT_OK 11
	set TX_COMMIT 20
	set TX_COMMIT_OK 21
	set TX_ROLLBACK 30
	set TX_ROLLBACK_OK 31

	##
	##
	## Bitmasks
	##
	##
	set EXCHANGE_PASSIVE 1
	set EXCHANGE_DURABLE 2
	# auto-delete and internal should be set to 0
	set EXCHANGE_AUTO_DELETE 4
	set EXCHANGE_INTERNAL 8
	set EXCHANGE_NO_WAIT 16

	set QUEUE_PASSIVE 1
	set QUEUE_DURABLE 2
	set QUEUE_EXCLUSIVE 4
	set QUEUE_AUTO_DELETE 8
	set QUEUE_DECLARE_NO_WAIT 16

	set QUEUE_IF_UNUSED 1
	set QUEUE_IF_EMPTY 2
	set QUEUE_DELETE_NO_WAIT 4

	# no local means the server will not send messages
	# to the connection that published them
	set CONSUME_NO_LOCAL 1
	set CONSUME_NO_ACK 2
	set CONSUME_EXCLUSIVE 4
	set CONSUME_NO_WAIT 8

	set PUBLISH_MANDATORY 1
	set PUBLISH_IMMEDIATE 2

	set NACK_MULTIPLE 1
	set NACK_REQUEUE 2

	# content header flags ordered from high-to-low
	# so the first property is bit 15
	set PROPERTY_CONTENT_TYPE [expr {2**15}]
	set PROPERTY_CONTENT_ENCODING [expr {2**14}]
	set PROPERTY_HEADERS [expr {2**13}]
	set PROPERTY_DELIVERY_MODE [expr {2**12}]
	set PROPERTY_PRIORITY [expr {2**11}]
	set PROPERTY_CORRELATION_ID 1024
	set PROPERTY_REPLY_TO 512
	set PROPERTY_EXPIRATION 256
	set PROPERTY_MESSAGE_ID 128
	set PROPERTY_TIMESTAMP 64
	set PROPERTY_TYPE 32
	set PROPERTY_USER_ID 16
	set PROPERTY_APP_ID 8
	set PROPERTY_RESERVED 4

	##
	## Message Property Types
	##
	# map property name to AMQP type
	set PROPERTY_TYPES [dict create {*}{
			content-type short_string
			content-encoding short_string
			headers field_table
			delivery-mode byte
			priority byte
			correlation-id short_string
			reply-to short_string
			expiration short_string
			message-id short_string
			timestamp timestamp
			type short_string
			user-id short_string
			app-id short_string
			reserved short_string
		}]

	# map property name to bit flag
	set PROPERTY_FLAGS [dict create {*}[subst {
				content-type $::rmq::PROPERTY_CONTENT_TYPE
				content-encoding $::rmq::PROPERTY_CONTENT_ENCODING
				headers $::rmq::PROPERTY_HEADERS
				delivery-mode $::rmq::PROPERTY_DELIVERY_MODE
				priority $::rmq::PROPERTY_PRIORITY
				correlation-id $::rmq::PROPERTY_CORRELATION_ID
				reply-to $::rmq::PROPERTY_REPLY_TO
				expiration $::rmq::PROPERTY_EXPIRATION
				message-id $::rmq::PROPERTY_MESSAGE_ID
				timestamp $::rmq::PROPERTY_TIMESTAMP
				type $::rmq::PROPERTY_TYPE
				user-id $::rmq::PROPERTY_USER_ID
				app-id $::rmq::PROPERTY_APP_ID
				reserved $::rmq::PROPERTY_RESERVED
			}]]

	# map property bit number to property name
	set PROPERTY_BITS [dict create {*}{
			15 content-type
			14 content-encoding
			13 headers
			12 delivery-mode
			11 priority
			10 correlation-id
			9 reply-to
			8 expiration
			7 message-id
			6 timestamp
			5 type
			4 user-id
			3 app-id
			2 reserved
		}]

	##
	## Error handling
	##

	# ERROR_CODES dict maps numeric error codes
	# found in frame type fields to their
	# name
	set ERROR_CODES [dict create {*}{
			200 reply-success
			311 content-too-large
			313 no-consumers
			320 connection-forced
			402 invalid-path
			403 access-refused
			404 not-found
			405 resource-locked
			406 precondition-failed
			501 frame-error
			502 syntax-error
			503 command-invalid
			504 channel-error
			505 unexpected-frame
			506 resource-error
			530 not-allowed
			540 not-implemented
			541 internal-error
		}]

	# CONN_ERRORS is a sorted list of
	# numeric error codes which are connection
	# errors and require closing the socket
	set CONN_ERRORS {
		320
		402
		501
		502
		503
		504
		505
		530
		540
		541
	}

	##
	## Defaults and Misc
	##
	set DEFAULT_HOST "localhost"
	set DEFAULT_PORT 5672
	set DEFAULT_UN "guest"
	set DEFAULT_PW "guest"
	set DEFAULT_VHOST "/"
	set DEFAULT_MECHANISM "PLAIN"
	set DEFAULT_LOCALE "en_US"

	# Max frame size for connection negotiation
	set MAX_FRAME_SIZE 131072

	# A value of 0 means the client does not want heartbeats
	set HEARTBEAT_SECS 60

	# Whether receiving consumer cancels from the server is supported
	set CANCEL_NOTIFICATIONS 1

	# Whether receiving blocked connection notifications is supported
	set BLOCKED_CONNECTIONS 1

	# Channel defaults where a channel max of 0 means no limit imposed
	set MAX_CHANNELS [expr {2**16} - 1]
	set DEFAULT_CHANNEL_MAX 0

	# Auto-reconnect with exponential backoff constants
	set DEFAULT_AUTO_RECONNECT 1
	set DEFAULT_MAX_BACKOFF 64
	set DEFAULT_MAX_RECONNECT_ATTEMPTS 5

	# Timeout threshold in seconds for trying to connect
	set DEFAULT_MAX_TIMEOUT 3

	# How many msecs to check for active connection
	set CHECK_CONNECTION 500

	# Version supported by the library
	set AMQP_VMAJOR 0
	set AMQP_VMINOR 9

	# client properties
	set PRODUCT tclrmq
	set VERSION 1.3.5
}

# vim: ts=4:sw=4:sts=4:noet
