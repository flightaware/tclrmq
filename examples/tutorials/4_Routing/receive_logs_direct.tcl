package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    # declare a fanout exchange named logs
    $rChan exchangeDeclare "direct_logs" "direct"

    # declare an exclusive queue and bind to the
    # fanout exchange
    $rChan on queueDeclareOk bind_to_fanout
    set qFlags [list $::rmq::QUEUE_EXCLUSIVE]
    $rChan queueDeclare "" $qFlags
}

proc bind_to_fanout {rChan qName msgCount consumers} {
    global severities

    # bind to each severity we're interested in
    foreach severity $severities {
        $rChan queueBind $qName "direct_logs" $severity
    }

    # basicConsume takes the callback proc name, queue name, consumer tag, flags
    set cFlags [list $::rmq::CONSUME_NO_ACK]
    $rChan basicConsume callback $qName "" $cFlags
    puts " \[*\] Waiting for logs. To exit press CTRL+C"
}

proc callback {rChan methodD frameD msg} {
    puts " \[x\] [dict get $methodD routingKey]:$msg"
}

global severities
if {[llength $argv] > 0} {
    set severities $argv
} else {
    puts stderr "Usage: $::argv0 \[info\] \[warning\] \[error\]"
    exit 1
}

set conn [::rmq::Connection new]
$conn connect
$conn onConnected create_channel

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
