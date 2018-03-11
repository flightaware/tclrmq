#!/usr/bin/env tclsh

proc bump_line {line newv} {
    if {![regexp {(package provide rmq|package ifneeded rmq) ([0-9]+\.[0-9]+\.[0-9]+)(.*$)} \
          $line -> pReq pVer pRest]} {
        return $line
    }
    return "$pReq $newv$pRest"
}

if {!$tcl_interactive} {
    if {$argc != 1} {
        puts stderr "Usage: $argv0 <new version>"
        exit 1
    }

    set curVer [exec git tag | tail -1 | cut --complement -c 1]
    set newVer [lindex $argv 0]
    puts stderr "Bumping rmq package from $curVer to $newVer"

    set fnames [glob -directory package *.tcl]
    foreach fname $fnames {
        set ofd [open $fname]
        set tfd [file tempfile tfname]
        while {[gets $ofd line] >= 0} {
            puts stderr $tfd [bump_line $line $newVer]
        } 

        close $tfd
        close $ofd 

        file rename -force $tfname $fname
        puts stderr "Bumped $fname"
    }
}
