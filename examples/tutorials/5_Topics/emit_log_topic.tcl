package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    # declare a fanout exchange named logs
    $rChan exchangeDeclare "topic_logs" "topic"

    # send a message to the direct exchange
    # using the severity as the routing key
    global msg routingKey
    $rChan basicPublish $msg "topic_logs" $routingKey
    puts " \[x\] Sent $routingKey:$msg"

    [$rChan getConnection] closeConnection
}

proc quit {args} {
    exit
}

global msg routingKey
if {[llength $argv] > 0} {
    lassign $argv routingKey msg
    if {$msg eq ""} {
        set msg "Hello World!"
    }
} else {
    set routingKey "anonymous.info"
    set msg "Hello World!"
}

set conn [::rmq::Connection new -autoReconnect 0]
$conn onConnected create_channel
$conn onClose quit
$conn connect

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
