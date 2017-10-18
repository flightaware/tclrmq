package require uuid

package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    # declare an exclusive queue and bind to the
    # fanout exchange
    $rChan on queueDeclareOk setup_rpc_client
    set qFlags [list $::rmq::QUEUE_EXCLUSIVE]
    $rChan queueDeclare "" $qFlags
}

proc setup_rpc_client {rChan qName msgCount consumers} {
    # basicConsume takes the callback proc name, queue name, consumer tag, flags
    set cFlags [list $::rmq::CONSUME_NO_ACK]
    $rChan basicConsume on_response $qName "" $cFlags

    # make call to request rpc response
    global correlationID
    set correlationID [::uuid::uuid generate]
    set props [dict create]
    dict set props correlation-id $correlationID
    dict set props reply-to $qName

    puts " \[x\] Request fib(30) $props"
    $rChan basicPublish 30 "" "rpc_queue" "" $props
}

proc on_response {rChan methodD frameD msg} {
    global correlationID
    set props [dict get $frameD properties]
    if {[dict get $props correlation-id] == $correlationID} {
        puts " \[.\] Got $msg"
        set ::die 1
    }
}

set conn [::rmq::Connection new]
$conn connect
$conn onConnected create_channel

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
