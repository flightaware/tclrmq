package require rmq


proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    # declare a fanout exchange named logs
    $rChan exchangeDeclare "logs" "fanout"

    # send a message to the fanout
    global msg
    $rChan basicPublish $msg "logs" ""
    puts " \[x\] Sent $msg"

    set ::die 1
}

global msg
if {[llength $argv] > 0} {
    set msg $argv
} else {
    set msg "info: Hello World!"
}

set conn [::rmq::Connection new]
$conn connect
$conn onConnected create_channel

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
