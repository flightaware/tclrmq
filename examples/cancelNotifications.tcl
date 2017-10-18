package require rmq

proc rmq_connected {conn} {
    set rChan [::rmq::Channel new $conn]
    $rChan onOpen setup_cancel_notifications
}

proc setup_cancel_notifications {rChan} {
    $rChan on basicCancel cancel_notification
    puts " \[+\]: will be alerted if consumer canceled..."

    # do some consuming
}

proc cancel_notification {rChan consumerTag} {
    puts " \[-\]: consumer $consumerTag was canceled by the server"
}

# cancel notifications are turned on by default when the connection
# is created although the callback to receive them is on a channel
# argument shown here for completeness
set conn [::rmq::Connection new -cancelNotifications 1]
$conn onConnected rmq_connected
$conn connect

vwait ::die
