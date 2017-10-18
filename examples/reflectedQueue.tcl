namespace eval qchan {
    package require struct
    variable chans
    array set chans {}

    proc initialize {chanid args} {
        variable chans

        set chans($chanid) [::struct::queue]
        foreach event {read write} {
            set chans($chanid,$event) 0
        }

        set map [dict create]
        foreach subCmd [list finalize watch read write] {
            dict set map $subCmd [list ::qchan::$subCmd $chanid]
        }

        namespace ensemble create -map $map -command ::$chanid
        return "initialize finalize watch read write"
    }

    proc finalize {chanid} {
        variable chans

        $chans($chanid) destroy
        unset chans($chanid)
    }

    proc watch {chanid events} {
        variable chans
        foreach event {read write} {
            set chans($chanid,$event) 0
        }
        foreach event $events {
            set chans($chanid,$event) 1
        }
    }

    proc read {chanid count} {
        variable chans

        if {[$chans($chanid) size] == 0} {
            return -code error EAGAIN
        }

        return [$chans($chanid) get]
    }

    proc write {chanid data} {
        variable chans

        $chans($chanid) put $data
        if {$chans($chanid,read)} {
            chan postevent $chanid read
        }

        return [string length $data]
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}

# vim: set ts=8 sw=4 sts=4 noet :
