package require rmq

proc rmq_connected {conn} {
    # set this callback on the connection object
    $conn onBlocked blocked_connection
    $rChan onOpen setup_blocked_connection_cb
}

proc blocked_connection {conn blocked reason} {
    set connStatus [expr {$blocked ? "is" : "is not"}]
    puts " \[+\]: connection $connStatus blocked (reason: $reason)"
}

# blocked connection notifications are turned on by default 
# argument shown here for completeness
# callback is set above on the Connection object
set conn [::rmq::Connection new -blockedConnections 1]
$conn onConnected rmq_connected
$conn connect

vwait ::die
