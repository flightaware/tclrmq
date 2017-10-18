package require rmq

source reflectedQueue.tcl

proc rmq_connected {conn} {
    set rChan [::rmq::Channel new $conn]
    $rChan onOpen setup_queue_channel
}

proc setup_queue_channel {rChan} {
    # setup a reflected queue channel to put messages on
    # for processing
    global ch
    set ch [chan create "read write" qchan]

    chan configure $ch -buffering line
    chan event $ch readable [list read_queue $ch]

    # start consuming messages assuming all necessary
    # exchanges, queues and bindings have been established
    $rChan basicConsume consume_rmq "test" "reflected-queue-consumer"
}

proc consume_rmq {rmqChan methodD frameD msg} {
    global ch

    # when consuming, put the message onto the queue
    # channel so the consume callback finishes ASAP
    puts $ch $msg
}

proc read_queue {ch} {
    # Read a message from the queue and do some processing
    set msg [chan gets $ch]
    puts " \[+\]: Read from queue $msg"
}

set conn [::rmq::Connection new -login [::rmq::Login new]]
$conn onConnected rmq_connected
$conn connect

vwait ::die


