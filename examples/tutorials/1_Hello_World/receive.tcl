package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    $rChan queueDeclare "hello"

    set consumeFlags [list $::rmq::CONSUME_NO_ACK]
    $rChan basicConsume callback "hello" $consumeFlags

    puts " \[*\] Waiting for messages. To exit press CTRL+C"
}

proc callback {rChan methodD frameD msg} {
    puts " \[x\] Received $msg"
}

set conn [::rmq::Connection new]
$conn onConnected create_channel
$conn connect

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
