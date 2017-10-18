package require rmq

proc create_channel {conn} {
    set rChan [::rmq::Channel new $conn]

    $rChan queueDeclare "rpc_queue"
    $rChan basicQos 1
    $rChan basicConsume on_request "rpc_queue"
    puts " \[x\] Awaiting RPC requests"
}

proc on_request {rChan methodD frameD n} {
    puts " \[.\] fib($n)"
    set response [fib $n]
    $rChan basicAck [dict get $methodD deliveryTag]

    set rpcProps [dict get $frameD properties]

    set props [dict create]
    dict set props correlation-id [dict get $rpcProps correlation-id]
    puts "Sending response $response to [dict get $rpcProps reply-to]"
    $rChan basicPublish $response "" [dict get $rpcProps reply-to] "" $props
}

proc fib {n} {
    if {$n == 0} {
        return 0
    } elseif {$n == 1} {
        return 1
    } else {
        set arg1 [expr {$n - 1}]
        set arg2 [expr {$n - 2}]
        return [expr {[fib $arg1] + [fib $arg2]}]
    }
}

set conn [::rmq::Connection new]
$conn connect
$conn onConnected create_channel

vwait ::die

# vim: ts=4:sw=4:sts=4:noet
