package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    # declare a fanout exchange named logs
    $rChan exchangeDeclare "direct_logs" "direct"

    # send a message to the direct exchange
    # using the severity as the routing key
    global msg severity
    $rChan basicPublish $msg "direct_logs" $severity
    puts " \[x\] Sent $severity:$msg"

    set ::die 1
}

global msg severity
if {[llength $argv] > 0} {
    lassign $argv severity msg
    if {$msg eq ""} {
        set msg "Hello World!"
    }
} else {
    set severity "info"
    set msg "Hello World!"
}

set conn [::rmq::Connection new]
$conn connect
$conn onConnected create_channel

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
