#!/usr/bin/env tclsh

##
##
## Used to bump the version of tclrmq
##
## Usage: ./bumpVersion.tcl <new version>
##
## Goes line by line through all files with a .tcl
## extension and copies each line into a temporary file
## with any lines containing the old version bumped to
## the new one. Once all lines in a file have been procesed,
## the temporary one replaces the original
##

proc bump_line {line newv} {
    set start {(^\s*)}
    set prefix "(package provide rmq|package ifneeded rmq|set VERSION) "
    set version {([0-9]+\.[0-9]+\.[0-9]+)}
    set rest {(.*$)}
    if {![regexp "$start$prefix$version$rest" $line -> pSpace pReq pVer pRest]} {
        return $line
    }
    return "$pSpace$pReq $newv$pRest"
}

if {!$tcl_interactive} {
    if {$argc != 1} {
        puts stderr "Usage: $argv0 <new version>"
        exit 1
    }

    if {[catch {exec which gcut} result options] == 1} {
        set cutCmd cut
    } else {
        set cutCmd gcut
    }
    set curVer [exec git tag | tail -1 | $cutCmd --complement -c 1]
    set newVer [lindex $argv 0]
    puts stderr "Bumping rmq package from $curVer to $newVer"

    set fnames [glob -directory package *.tcl]
    foreach fname $fnames {
        set ofd [open $fname]
        set tfd [file tempfile tfname]
        while {[gets $ofd line] >= 0} {
            puts $tfd [bump_line $line $newVer]
        }

        close $tfd
        close $ofd

        file rename -force $tfname $fname
        puts stderr "Bumped $fname"
    }
}
