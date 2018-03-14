##
##
## encoders.tcl - procs in the rmq namespace for encoding Tcl values
##	into binary values, i.e., strings of raw bytes, suitable for
##	sending to a RabbitMQ server
##
##	before sending any data across the network, the Tcl representation
##	will pass through a proc contained in this file
##
##
package provide rmq 1.3.5

namespace eval rmq {

	proc enc_frame {ftype channel content} {
		set ftype [::rmq::enc_byte $ftype]
		set channel [::rmq::enc_short $channel]
		set size [::rmq::enc_ulong [string length $content]]
		return ${ftype}${channel}${size}${content}$::rmq::FRAME_END
	}

	proc enc_method {mtype mid content} {
		set mtype [::rmq::enc_short $mtype]
		set mid [::rmq::enc_short $mid]
		return "${mtype}${mid}${content}"
	}

	proc enc_protocol_header {} {
		return "AMQP[binary format c4 {0 0 9 1}]"
	}

	#
	# enc_field_table - given a dict, convert it into a field
	#  table binary string
	#  this proc attempts to convert any values passed to it
	#  using the string is command
	#  integers below 2**16 - 1 will be encoded as a ushort
	#  all other integers as a long with every integer value
	#  assumed to be unsigned
	#  all double values will be converted to a float
	#  booleans are checked after ints and doubles, so a textual
	#  true or false value must be used to get a boolean conversion
	#  strings less than or equal to 128 chars are short strings
	#  all other strings encoded as long strings
	#
	#  takes an optional second argument to ignore certain fields
	#  if the type recognition offered by the proc is insufficient
	#
	proc enc_field_table {fieldD {skipKeys ""}} {
		set fieldStr ""
		dict for {k v} $fieldD {
			if {$k in $skipKeys} {
				set v $v
			} elseif {[string is integer -strict $v]} {
				if {$v <= 2**8 - 1} {
					set v [::rmq::enc_byte $v]
				} elseif {$v <= 2**16 - 1} {
					set v [::rmq::enc_ushort $v]
				} else {
					set v [::rmq::enc_ulong $v]
				}
			} elseif {[string is double -strict $v]} {
				set v [::rmq::enc_float $v]
			} elseif {[string is boolean -strict $v]} {
				set v [::rmq::enc_boolean $v]
			} elseif {[string is alnum $v]} {
				if {[string length $v] <= 128} {
					set v [::rmq::enc_short_string $v]
				} else {
					set v [::rmq::enc_long_string $v]
				}
			}

			append fieldStr "[::rmq::enc_short_string $k]$v"
		}

		set fieldStrLen [::rmq::enc_ulong [string length $fieldStr]]

		return "${fieldStrLen}${fieldStr}"
	}

	#
	# enc_field_value - given a textual description of a field table
	#  data value type, return the binary equivalent
	#
	#  when encoding a field table all field table values must be
	#  prefaced by a byte encoding their data type and this proc helps
	#  while building up a Tcl dict for encoding
	#
	proc enc_field_value {typeDesc} {
		return [binary format a1 [lookup_field_value $typeDesc]]
	}

	proc lookup_field_value {typeDesc} {
		switch $typeDesc {
			boolean {return t}
			short-short-int {return b}
			short-short-unint {return B}
			short-int {return U}
			short-unint {return u}
			long-int {return I}
			long-uint {return i}
			long-long-int {return L}
			long-long-uint {return l}
			float {return f}
			double {return d}
			decimal-value {return D}
			short-string {return s}
			long-string {return S}
			field-array {return A}
			timestamp {return T}
			field-table {return F}
			no-field {return V}
		}
	}

	proc enc_byte {value} {
		return [binary format cu $value]
	}

	proc enc_short_string {str} {
		# Short string consists of OCTET *string-char
		set sLen [string length $str]

		return "[::rmq::enc_byte $sLen][binary format a$sLen $str]"
	}

	proc enc_long_string {str} {
		# Long string consists of long-uint *OCTET
		set sLen [string length $str]

		return "[::rmq::enc_ulong $sLen][binary format a$sLen $str]"
	}

	#
	# enc_field_array - given the name of an array to be upvar'ed in
	#  the proc, convert it to a field array binary string
	#
	proc enc_field_array {_fieldA} {
		error "Need to implement field array encoding"
	}

	proc enc_short {int} {
		return [binary format S $int]
	}

	proc enc_ushort {int} {
		return [binary format Su $int]
	}

	proc enc_long {int} {
		return [binary format I $int]
	}

	proc enc_ulong {int} {
		return [binary format Iu $int]
	}

	proc enc_ulong_long {int} {
		return [binary format Wu $int]
	}

	proc enc_float {float} {
		return [binary format f $float]
	}

	proc enc_double {double} {
		return [binary format d $double]
	}

	proc enc_timestamp {timestamp} {
		return [binary format Wu $timestamp]
	}

	# takes a class ID and a dictionary of property values
	# this proc handles encoding the props
	proc enc_content_header {classID bodySize propsD} {
		set classID [::rmq::enc_short $classID]
		set weight [::rmq::enc_short 0]
		set bodySize [::rmq::enc_ulong_long $bodySize]
		set props [::rmq::enc_properties $propsD]

		return ${classID}${weight}${bodySize}${props}
	}

	# for encoding message properties when publishing a message
	proc enc_properties {propsD} {
		# first need the flags field and then a property list
		set propFlags 0
		set props ""
		dict for {k v} $propsD {
			if {![dict exists $::rmq::PROPERTY_FLAGS $k]} {
				continue
			}

			set propFlag [dict get $::rmq::PROPERTY_FLAGS $k]
			set propFlags [expr {$propFlags | $propFlag}]

			set propEncoder "::rmq::enc_[dict get $::rmq::PROPERTY_TYPES $k]"
			append props [$propEncoder $v]
		}
		set propFlags [::rmq::enc_short $propFlags]

		return ${propFlags}${props}
	}
}


# vim: ts=4:sw=4:sts=4:noet
