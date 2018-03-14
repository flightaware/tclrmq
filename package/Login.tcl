package provide rmq 1.3.5

package require TclOO

namespace eval rmq {
	namespace export Login
}

oo::class create ::rmq::Login {
	variable user pass mechanism vhost

	constructor {args} {
		array set options {}
		set options(-user) $::rmq::DEFAULT_UN
		set options(-pass) $::rmq::DEFAULT_PW
		set options(-mechanism) $::rmq::DEFAULT_MECHANISM
		set options(-vhost) $::rmq::DEFAULT_VHOST

		foreach {opt val} $args {
			if {[info exists options($opt)]} {
				set options($opt) $val
			}
		}

		foreach opt [array names options] {
			set [string trimleft $opt -] $options($opt)
		}
	}

	method getVhost {} {
		return $vhost
	}

	method saslResponse {} {
		# can dispatch on method if more are supported in
		# the future but at this point, only send PLAIN format
		if {$mechanism eq "PLAIN"} {
			set unLen [string length $user]
			set pwLen [string length $pass]
			return "\x00[binary format a$unLen $user]\x00[binary format a$pwLen $pass]"
		}
	}
}

# vim: ts=4:sw=4:sts=4:noet
