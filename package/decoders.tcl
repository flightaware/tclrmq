package provide rmq 1.3.5

namespace eval rmq {

	proc dec_field_table {data _bytes} {
		upvar $_bytes bytes

		# will build up a dict of key-value pairs
		set fieldD [dict create]

		# field-table: long-uint *field-value-pair
		# field-value-pair: field-name field-value
		# field-name: short-string
		binary scan $data Iu len
		::rmq::debug "Field table is $len bytes"
		set data [string range $data 4 end]

		set bytesProcessed 4
		while {$bytesProcessed < $len + 4} {
			# first, get the short string for the key
			set key [::rmq::dec_short_string $data bytes]
			set data [string range $data $bytes end]
			incr bytesProcessed $bytes

			# next, get the field value type and field value
			binary scan $data a1 valueType
			set data [string range $data 1 end]

			set decoder [::rmq::dec_field_value_type $valueType]
			if {[llength $decoder] > 1} {
				set value [{*}$decoder $data bytes]
			} else {
				set value [$decoder $data bytes]
			}
			incr bytesProcessed [expr {1 + $bytes}]
			set data [string range $data $bytes end]

			# put the key-value pair into the dict
			dict set fieldD $key $value
		}

		set bytes $bytesProcessed
		return $fieldD
	}

	proc dec_generic {spec data _bytes} {
		upvar 2 $_bytes bytes

		binary scan $data $spec value

		switch $spec {
			c -
			cu {
				set bytes 1
			}

			S -
			Su {
				set bytes 2
			}

			I -
			Iu -
			f {
				set bytes 4
			}

			W -
			Wu -
			d {
				set bytes 8
			}
		}

		return $value
	}

	proc dec_field_array {data _bytes} {
		error "Field array decoder not implemented"
	}

	proc dec_decimal_value {data _bytes} {
		error "Decimal value decoder not implemeneted"
	}

	proc dec_byte {data _bytes} {
		return [::rmq::dec_generic c $data $_bytes]
	}

	proc dec_short {data _bytes} {
		return [::rmq::dec_generic S $data $_bytes]
	}

	proc dec_ushort {data _bytes} {
		return [::rmq::dec_generic Su $data $_bytes]
	}

	proc dec_long {data _bytes} {
		return [::rmq::dec_generic I $data $_bytes]
	}

	proc dec_ulong {data _bytes} {
		return [::rmq::dec_generic Iu $data $_bytes]
	}

	proc dec_long_long {data _bytes} {
		return [::rmq::dec_generic W $data $_bytes]
	}

	proc dec_ulong_long {data _bytes} {
		return [::rmq::dec_generic Wu $data $_bytes]
	}

	proc dec_float {data _bytes} {
		return [::rmq::dec_generic f $data $_bytes]
	}

	proc dec_double {data _bytes} {
		return [::rmq::dec_generic d $data $_bytes]
	}

	proc dec_field_value_type {valueType} {
		# need to dispatch based on value type
		switch $valueType {
			"t" -
			"b" {
				return "::rmq::dec_generic c"
			}

			"B" {
				return "::rmq::dec_generic cu"
			}

			"U" {
				return "::rmq::dec_generic S"
			}

			"u" {
				return "::rmq::dec_generic Su"
			}

			"I" {
				return "::rmq::dec_generic I"
			}

			"i" {
				return "::rmq::dec_generic Iu"
			}

			"L" {
				return "::rmq::dec_generic W"
			}

			"l" {
				return "::rmq::dec_generic Wu"
			}

			"f" {
				return "::rmq::dec_generic f"
			}

			"d"   {
				return "::rmq::dec_generic d"
			}

			"D" {
				return "::rmq::dec_decimal_value"
			}

			"s" {
				return ::rmq::dec_short_string
			}

			"S" {
				return ::rmq::dec_long_string
			}

			"A" {
				return ::rmq::dec_field_array
			}

			"T" {
				return "::rmq::dec_generic Wu"
			}

			"F" {
				return ::rmq::dec_field_table
			}

			"V" {
				return ::rmq::dec_no_field
			}
		}
	}

	proc dec_short_string {data _bytes} {
		upvar $_bytes bytes

		# starts with a byte for the length
		binary scan $data cu len

		# then need to read the actual string
		set str [string range $data 1 $len]

		# book-keeping the number of bytes processed
		set bytes [expr {1 + $len}]

		return $str
	}

	proc dec_long_string {data _bytes} {
		upvar $_bytes bytes

		# starts with 4 bytes for the length
		binary scan $data Iu len

		# then need to read the full string
		set str [string range $data 4 [expr {4 + $len}]]

		# book-keeping the number of bytes processed
		set bytes [expr {4 + $len}]

		return $str
	}

	proc dec_decimal_value {data _bytes} {
		upvar $_bytes bytes

		# starts with a byte specifying the number of
		# decimal digits to come
		binary scan $data cu scale

		# now can read the rest of the data
		binary scan $data @1Iu value

		# always read a byte + a long-unint
		set bytes 5

		# need to turn the value into a decimal
		# with scale digits after the decimal point
		if {$scale == 0} {
			return $value
		} else {
			set numDigits [string length $value]
			set beforeDec [expr {$numDigits - $scale}]

			set beforeDecStr [string range $value 0 [expr {$beforeDec - 1}]]
			set afterDecStr [string range $value $beforeDec end]

			if {$afterDecStr eq ""} {
				return $beforeDecStr
			} else {
				return "${beforeDecStr}.${afterDecStr}"
			}
		}
	}

	proc dec_method {mClass mID} {
		# TODO: use constants instead of raw ints
		if {$mClass eq $::rmq::CONNECTION_CLASS} {
			return "connection[::rmq::dec_connection_method $mID]"
		} elseif {$mClass eq $::rmq::CHANNEL_CLASS} {
			return "channel[::rmq::dec_channel_method $mID]"
		} elseif {$mClass eq $::rmq::EXCHANGE_CLASS} {
			return "exchange[::rmq::dec_exchange_method $mID]"
		} elseif {$mClass eq $::rmq::QUEUE_CLASS} {
			return "queue[::rmq::dec_queue_method $mID]"
		} elseif {$mClass eq $::rmq::BASIC_CLASS} {
			return "basic[::rmq::dec_basic_method $mID]"
		} elseif {$mClass eq $::rmq::CONFIRM_CLASS} {
			return "confirm[::rmq::dec_confirm_method $mID]"
		} elseif {$mClass eq $::rmq::TX_CLASS} {
			return "tx[::rmq::dec_tx_method $mID]"
		}
	}

	proc dec_connection_method {mID} {
		if {$mID eq $::rmq::CONNECTION_START} {return Start}
		if {$mID eq $::rmq::CONNECTION_START_OK} {return StartOk}
		if {$mID eq $::rmq::CONNECTION_SECURE} {return Secure}
		if {$mID eq $::rmq::CONNECTION_SECURE_OK} {return SecureOk}
		if {$mID eq $::rmq::CONNECTION_TUNE} {return Tune}
		if {$mID eq $::rmq::CONNECTION_TUNE_OK} {return TuneOk}
		if {$mID eq $::rmq::CONNECTION_OPEN} {return Open}
		if {$mID eq $::rmq::CONNECTION_OPEN_OK} {return OpenOk}
		if {$mID eq $::rmq::CONNECTION_CLOSE} {return Close}
		if {$mID eq $::rmq::CONNECTION_CLOSE_OK} {return CloseOk}
	}

	proc dec_channel_method {mID} {
		if {$mID eq $::rmq::CHANNEL_OPEN} {return Open}
		if {$mID eq $::rmq::CHANNEL_OPEN_OK} {return OpenOk}
		if {$mID eq $::rmq::CHANNEL_FLOW} {return Flow}
		if {$mID eq $::rmq::CHANNEL_FLOW_OK} {return FlowOk}
		if {$mID eq $::rmq::CHANNEL_CLOSE} {return Close}
		if {$mID eq $::rmq::CHANNEL_CLOSE_OK} {return CloseOk}
	}

	proc dec_exchange_method {mID} {
		if {$mID eq $::rmq::EXCHANGE_DECLARE} {return Declare}
		if {$mID eq $::rmq::EXCHANGE_DECLARE_OK} {return DeclareOk}
		if {$mID eq $::rmq::EXCHANGE_DELETE} {return Delete}
		if {$mID eq $::rmq::EXCHANGE_DELETE_OK} {return DeleteOk}
		if {$mID eq $::rmq::EXCHANGE_BIND_OK} {return BindOk}
		if {$mID eq $::rmq::EXCHANGE_UNBIND_OK} {return UnbindOk}
	}

	proc dec_queue_method {mID} {
		if {$mID eq $::rmq::QUEUE_DECLARE} {return Declare}
		if {$mID eq $::rmq::QUEUE_DECLARE_OK} {return DeclareOk}
		if {$mID eq $::rmq::QUEUE_BIND} {return Bind}
		if {$mID eq $::rmq::QUEUE_BIND_OK} {return BindOk}
		if {$mID eq $::rmq::QUEUE_UNBIND} {return Unbind}
		if {$mID eq $::rmq::QUEUE_UNBIND_OK} {return UnbindOk}
		if {$mID eq $::rmq::QUEUE_PURGE} {return Purge}
		if {$mID eq $::rmq::QUEUE_PURGE_OK} {return PurgeOk}
		if {$mID eq $::rmq::QUEUE_DELETE} {return Delete}
		if {$mID eq $::rmq::QUEUE_DELETE_OK} {return DeleteOk}
	}

	proc dec_basic_method {mID} {
		if {$mID eq $::rmq::BASIC_QOS} {return Qos}
		if {$mID eq $::rmq::BASIC_QOS_OK} {return QosOk}
		if {$mID eq $::rmq::BASIC_CONSUME} {return Consume}
		if {$mID eq $::rmq::BASIC_CONSUME_OK} {return ConsumeOk}
		if {$mID eq $::rmq::BASIC_CANCEL} {return CancelRecv}
		if {$mID eq $::rmq::BASIC_CANCEL_OK} {return CancelOk}
		if {$mID eq $::rmq::BASIC_PUBLISH} {return Publish}
		if {$mID eq $::rmq::BASIC_RETURN} {return Return}
		if {$mID eq $::rmq::BASIC_DELIVER} {return Deliver}
		if {$mID eq $::rmq::BASIC_GET} {return Get}
		if {$mID eq $::rmq::BASIC_GET_OK} {return GetOk}
		if {$mID eq $::rmq::BASIC_GET_EMPTY} {return GetEmpty}
		if {$mID eq $::rmq::BASIC_ACK} {return AckReceived}
		if {$mID eq $::rmq::BASIC_REJECT} {return Reject}
		if {$mID eq $::rmq::BASIC_RECOVER_ASYNC} {return RecoverAsync}
		if {$mID eq $::rmq::BASIC_RECOVER} {return Recover}
		if {$mID eq $::rmq::BASIC_RECOVER_OK} {return RecoverOk}
		if {$mID eq $::rmq::BASIC_NACK} {return NackReceived}
	}

	proc dec_confirm_method {mID} {
		if {$mID eq $::rmq::CONFIRM_SELECT} {return Select}
		if {$mID eq $::rmq::CONFIRM_SELECT_OK} {return SelectOk}
	}

	proc dec_tx_method {mID} {
		if {$mID eq $::rmq::TX_SELECT} {return Select}
		if {$mID eq $::rmq::TX_SELECT_OK} {return SelectOk}
		if {$mID eq $::rmq::TX_COMMIT} {return Commit}
		if {$mID eq $::rmq::TX_COMMIT_OK} {return CommitOk}
		if {$mID eq $::rmq::TX_ROLLBACK} {return Rollback}
		if {$mID eq $::rmq::TX_ROLLBACK_OK} {return RollbackOk}
	}

	proc dec_content_header {data} {
		::rmq::debug "Decode content header"

		# the class ID field
		set cID [::rmq::dec_short $data _]

		# TODO: validate that the class ID matches the
		# frame class ID and respond with a 501 if not

		# unused weight field
		set data [string range $data 2 end]
		set weight [::rmq::dec_short $data _]

		# TODO: validate that the weight field is 0

		# body size for the content body frames to come
		set data [string range $data 2 end]
		set bodySize [::rmq::dec_ulong_long $data bytes]
		::rmq::debug "Content header class ID $cID with a body size of $bodySize"

		# lastly, parse the property flags field
		set data [string range $data $bytes end]
		set flags [::rmq::dec_ushort $data _]

		# if the last bit (0) is set, more property flags remain
		# so combine them all together
		set propFlags $flags
		while {$flags & (1 << 0)} {
			::rmq::debug "More than the typical number of property flags!"
			set data [string range $data 2 end]
			set flags [::rmq::dec_ushort $data _]
			#lappend propFlags $flags
		}

		set data [string range $data 2 end]
		set propList $data

		# the property flags indicate which fields are included
		# in the property list, so need to find that out now
		# so we know which decoders to apply to the propList blob
		set propsSet [list]
		dict for {bitNum propName} $::rmq::PROPERTY_BITS {
			if {$propFlags & (1 << $bitNum)} {
				lappend propsSet $propName
			}
		}

		set propsD [dict create]
		foreach propSet $propsSet {
			set decoder "::rmq::dec_[dict get $::rmq::PROPERTY_TYPES $propSet]"
			dict set propsD $propSet [$decoder $propList bytes]
			set propList [string range $propList $bytes end]
		}

		# return a dict of all the data
		return [dict create classID $cID bodySize $bodySize properties $propsD]
	}
}

# vim: ts=4:sw=4:sts=4:noet
