package require rmq

set data "Hello World!"

proc create_channel {conn} {
    global data
    set rChan [::rmq::Channel new $conn]

    # declare a durable queue for tasks
    set qFlags [list $::rmq::QUEUE_DURABLE]
    $rChan queueDeclare "task_queue" $qFlags

    # create a dict with the additional property needed
    # to make the message persistent
    set props [dict create delivery-mode 2]

    # args: data exchangeName routingKey flags properties
    $rChan basicPublish $data "" "task_queue" [list] $props

    puts " \[x\] Sent '$data'"

    $conn closeConnection
}

proc finished {conn closeD} {
    exit
}

if {[llength $argv] > 0} {
    set data $argv
}

set conn [::rmq::Connection new]
$conn onConnected create_channel
$conn onClose finished

$conn connect

vwait die

# vim: ts=4:sw=4:sts=4:noet
