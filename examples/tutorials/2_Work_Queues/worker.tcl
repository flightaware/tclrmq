package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    # declare a durable queue for tasks
    set qFlags [list $::rmq::QUEUE_DURABLE]
    $rChan queueDeclare "task_queue" $qFlags

    $rChan basicQos 1
    $rChan basicConsume callback "task_queue"
    puts " \[*\] Waiting for messages. To exit press CTRL+C"
}

proc callback {rChan methodD frameD msg} {
    puts " \[x\] Received $msg"
    set sleepSecs [llength [lsearch -all [split $msg ""] "."]]
    after [expr {$sleepSecs * 1000}]
    puts " \[x\] Done"
    $rChan basicAck [dict get $methodD deliveryTag]
}

set conn [::rmq::Connection new]
$conn connect
$conn onConnected create_channel

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
