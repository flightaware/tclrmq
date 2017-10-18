package require rmq

proc rmq_connected {conn} {
    set rChan [::rmq::Channel new $conn]
    $rChan onOpen setup_publisher_confirms
}

proc confirm_selected {rChan} {
    set ::confirmsAccepted 1
}

proc setup_publisher_confirms {rChan} {
    # need to use the AMQP confirm.select method
    $rChan confirmSelect
    $rChan on confirmSelectOk confirm_selected
    puts " \[+\] Sent confirm.select: waiting for acceptance..."
    vwait ::confirmsAccepted

    # with confirm.select sent, need to setup a callback
    # for basic.ack
    $rChan on basicAck publisher_confirm

    # now need to publish some data
    # assumes the test queue has been setup already
    puts " \[+\] Publishing some messages..."
    set pFlags [list]
    set props [dict create delivery-mode 2]
    for {set i 0} {$i < 10} {incr i} {
        $rChan basicPublish [randomDelimString 1000]  "" "test" $pFlags $props
    }
    puts " \[+\] Published messages..."
}

# Taken from the Tcl wiki: https://wiki.tcl.tk/3757
binary scan A c A
binary scan z c z
proc randomDelimString [list length [list min $A] [list max $z]] {
    set range [expr {$max-$min}]

    set txt ""
    for {set i 0} {$i < $length} {incr i} {
       set ch [expr {$min+int(rand()*$range)}]
       append txt [binary format c $ch]
    }
    return $txt
}

proc publisher_confirm {rChan dTag multiple} {
    puts " \[+\]: Received confirm for delivery tag $dTag (multiple? $multiple)"

    # do some book-keeping to mark which message has been confirmed

    # in our case, will exit the event loop after getting all our confirms
    if {$dTag == 10} {
        set ::die 1
    }
}

set conn [::rmq::Connection new -login [::rmq::Login new]]
$conn onConnected rmq_connected
$conn connect

vwait ::die
