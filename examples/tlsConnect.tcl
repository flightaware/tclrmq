package require rmq

proc rmq_connected {conn} {
    puts " \[+\]: Connected using TLS!"
    $conn closeConnection
    set ::die 1
}

# using the guide in https://www.rabbitmq.com/ssl.html
set conn [::rmq::Connection new -port 5671 -login [::rmq::Login new]]
$conn onConnected rmq_connected
$conn tlsOptions -cafile "$::env(HOME)/testca/cacert.pem" \
                 -certfile "$::env(HOME)/client/cert.pem" \
                 -keyfile "$::env(HOME)/client/key.pem"
$conn connect

vwait ::die
