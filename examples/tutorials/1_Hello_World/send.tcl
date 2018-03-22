package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    $rChan queueDeclare "hello"
    # args: data exchangeName routingKey
    $rChan basicPublish "Hello World!" "" "hello"

    puts " \[x\] Sent 'Hello World!'"

    $conn closeConnection
}

proc finished {conn closeD} {
    exit
}

set conn [::rmq::Connection new]
$conn onConnected create_channel
$conn onClose finished

$conn connect

vwait die

# vim: ts=4:sw=4:sts=4:noet
