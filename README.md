# tclrmq
Pure TCL RabbitMQ Library implementing AMQP 0.9.1

This library is completely asynchronous and makes no blocking calls.
It relies on TclOO and requires Tcl 8.6, but has no other dependencies 
(other than a RabbitMQ server).

# About
Developed for use within FlightAware (https://flightaware.com).

The package directory contains a Makefile for installing globally.  By
default the Makefile installs to `/usr/local/lib`, so this will need editing
if an alternative directory is required.

# Basic Usage
There are two primary classes required for using the library.

1) Connection

The _Connection_ class is used for initiating initial communication with the
RabbitMQ server.  It also relies on a subsidiary _Login_ class, which is used
for specifying username, password, vhost and authentication mechanism.  Out of
the box, this library only supports the PLAIN SASL mechanism.  It can be easily
extended to support an additional mechanism if required.

```tcl
package require rmq

# Arguments: -user -pass -vhost
# All optional and shown with their defaults
set login [Login new -user "guest" -pass "guest" -vhost "/"]

# Pass the login object created above to the Connection
# constructor
# -host and -port are shown with their default values
set conn [Connection new -host localhost -port 5672 -login $login]

# Set a callback for when the connection is ready to use
# which will be passed the connection object 
$conn onConnected rmq_conn_ready
proc rmq_conn_ready {conn} {
    puts "Connection ready!"
    $conn connectionClose
}

# Set a callback for when the connection is closed
$conn onClosed rmq_conn_closed
proc rmq_conn_closed {conn} {
    puts "Connection closed!"
}

# Initiate the connection handshake and enter the event loop
$conn connect
vwait die
```

2) Channel

The _Channel_ class is where most of the action happens.  The vast majority of AMQP
methods refer to a specific channel.  After the Connection object has gone through
the opening handshake and calls its _onOpen_ handshake a _Channel_ object can be
created by passing 

```tcl
# Assume the following proc has been set as the Connection object's 
# onOpen callback
proc rmq_conn_ready {conn} {
    # Create a channel object
    # If no channel number is specified, the
    # next available will be chosen
    set chan [Channel new $conn]

    # Do something with the channel, like 
    # declare an exchange
    set flags [list $::rmq::EXCHANGE_DURABLE]
    $chan exchangeDeclare "test" "direct" $flags
}
```

# Callbacks
Using this library for anything useful requires setting callbacks for the
AMQP methods needed in the client application. Most callbacks will be set on
_Channel_ objects, but the _Connection_ object supports a few as well.

All callbacks are passed the object they were set on as the first parameter.
Depending on the AMQP method or object event, additional parameters are provided
as appropriate.

## Connection Callbacks

Connection objects allow for the setting of the following callbacks:

1) _onConnected_: called when the AMQP connection handshake finishes and is passed the
                  _Connection_ object

2) _onBlocked_: called when the RabbitMQ server has blocked connections due to
                [resource limitations](https://www.rabbitmq.com/connection-blocked.html).
                Callback is passed the _Connection_ object, a boolean for whether the connection
                is blocked or not and a textual reason

3) _onClosed_: called when the connection is closed and is passed the _Connection_ object
               and a dict containing any data such as a textual description of the error,
               the reply code, any reply text, the class ID and the method ID

3) _onError_: called when an error code has been sent to the _Connection_ and is passed
              the error code and any accompanying data in the frame

4) _onFailedReconnect_: called when all reconnection attempts have been exhausted

```tcl
package require rmq

# Arguments: username password vhost
set login [Login new -user "guest" -pass "guest" -vhost "/"]

# Pass the login object created above to the Connection
# constructor
set conn [Connection new -host localhost -port 5672 -login $login]

$conn onConnected rmq_connected
$conn onClosed rmq_closed
$conn onError rmq_connection_error

proc rmq_connected {rmqConn} {
    # do useful things
}

proc rmq_closed {rmqConn closeD} {
    # do other useful things
}

proc rmq_error {rmqConn frameType frameData} {
    # do even more useful things
}
```

## Channel Callbacks

_Channel_ objects have a few specific callbacks that can be set along with a more general
callback mechanism for the majority of AMQP method calls.

### Specific Callbacks

The specific callbacks provided for _Channel_ objects mirror those available for _Connection_
objects.  They are:

1) _onOpen_: called when the channel is open and ready to use, i.e., when the Channel.Open-Ok
             method is received from the RabbitMQ server and is passed the same arguments as
             the _onConnected_ callback for Connection objects

2) _onClose_: called when the channel has been fully closed, i.e., when the Channel.Close-Ok
              method is received from the RabbitMQ server and is passed the same arguments as
              the _onClosed_ callback for Connection objects

3) _onError_: called when the channel receives an error, i.e., a frame is received for the
              given channel but contains an AMQP error code and is passed the same arguments as
              the _onError_ callback for Connection objects

### General Callback Mechanism

Other than the above callbacks, a Channel object can be supplied a callback for every method that
can be sent in response to an AMQP method by using the _on_ method of Channel objects.

These callbacks are passed the Channel object they were set on unless otherwise specified in the
full method documentation found below.

When specifying the name of the AMQP method the callback will be invoked on, start with a lowercase
letter and use camel case.  All AMQP methods documented in the 
[RabbitMQ 0-9-1 extended specification](https://www.rabbitmq.com/resources/specs/amqp0-9-1.extended.xml)
are available.  

```tcl
# Asumming a channel object by name rmqChan exists
$rmqChan on exchangeDeclareOk exchange_declared
$rmqChan on queueDeclareOk queue_declared
$rmqChan on queueBindOk queue_bound

$rmqChan exchangeDeclare "the_best_exchange" "fanout"
vwait exchangeDelcared

$rmqChan queueDeclare "the_best_queue"
vwait queueDeclared

$rmqChan queueBind "the_best_queue" "the_best_exchange" "the_best_routing_key"

proc exchange_delcared {rmqChan} {
    set ::exchangeDeclared 1
}

proc queue_declared {rmqChan} {
    set ::queueDeclared 1
}

proc queue_bound {rmqChan} {
    set ::queueBound 1
}
```

### The Exception of Consuming

When consuming messages from a queue using either _Basic.Consume_ or _Basic.Get_, the process of
setting a callback and the data passed into the callback differs from every other case.

For consuming, the Channel object methods _basicConsume_ and _basicGet_ take the name of the callback
invoked for each message delivered and then their arguments.  The callbacks get passed in the
Channel object, a dictionary of method data, a dictionary of frame data, and the data from the queue.

```tcl
# Assuming a channel object by name rmqChan exists
$rmqChan basicConsume consume_callback "the_best_queue"

proc consume_callback {rmqChan methodD frameD data} {
    # Can inspect the consumer tag and dispatch on it
    switch [dict get $methodD consumerTag] {
        # useful things
    }

    # Can get the delivery tag to ack the message
    $rmqChan basicAck [dict get $methodD deliveryTag]

    # Frame data includes things like the data body size
    # and is likely less immediately useful but it is
    # passed in because it might be necessary for a given
    # application
}
```

#### Consuming From Multiple Queues

For a given channel, multiple queues can be consumed from and each queue can be given its own callback proc by passing in (or allowing the server to generate) a distinct _consumerTag_ for each invocation of _basicConsume_.  Otherwise, dispatching based on the method or frame metadata allows a single callback proc to customize the handling of messages from different queues.  When the client application is not constrained in its use of channels, instantiating multiple _Channel_ objects is a straight-forward way for one consumer to concurrently pull data from more than one queue.

### Method Data

The dictionary of method data passed as the second argument to consumer callbacks contains the following items:

* __consumerTag__

    The string consumer tag, either specified at the time _basicConsume_ is called, or auto-generated by the server.

* __deliveryTag__

    Integer numbering for the message being consumed.  This is used for the _basicAck_ or _basicNack_ methods.

* __redelivered__

    Boolean integer.

* __exchange__

    Name of the exchange the message came from.

* __routingKey__

    Routing key used for delivery of the message.

### Frame Data

The dictionary of frame data passed as the third argument to consumer callbacks contains the following items:

* __classID__

    AMQP defined integer for the class used for delivering the message.

* __bodySize__

    Size in bytes for the data consumed from the queue.

* __properties__

    Dictionary of AMQP [Basic method properties](https://www.rabbitmq.com/amqp-0-9-1-reference.html), e.g., 
    _correlation-id_, _timestamp_ or _content-type_.

# Special Arguments

## Flags

For AMQP methods like _queueDeclare_ or _exchangeDeclare_ which take flags, these are passed in as a list of
constants.  All supported flags are mentioned in the documentation below detailing each _Channel_ method.  
Within the source, supported flag constants are found in [constants.tcl](package/constants.tcl#L102-L130).

## Properties / Headers

For AMQP class methods which take properties and/or headers, e.g., _basicConsume_, _basicPublish_, or _exchangeDeclare_, the 
properties and headers are passed in as a Tcl dict.  The library takes care of encoding them properly.

# Library Documentation

All methods defined for _Connection_, _Login_, and _Channel_ classes are detailed below.  Only includes methods that are
part of the public interface for each object.  Any additional methods found in the source are meant to be called internally.

## _Connection_ Class

Class for connecting to a RabbitMQ server.

### constructor

The constructor takes the following arguments (all optional):

* __-host__

    Defaults to localhost

* __-port__

    Defaults to 5672

* __-tls__

    Either 0 or 1, but defaults to 0.  Controls whether to connect to the RabbitMQ server using TLS. To set
    TLS options, e.g., if using a client cert, call the _tlsOptions_ method before invoking _connect_.

* __-login__

    _Login_ object.  Defaults to calling the Login constructor with no arguments.

* __-frameMax__

    Maximum frame size in bytes.  Defaults to the value offered by the RabbitMQ server in _Connection.Tune_.

* __-maxChannels__

    Maximum number of channels available for this connection.  Defaults to no imposed limit, which is essentially 65,535.

* __-locale__

    Defaults to en_US.

* __-heartbeatSecs__

    Interval in seconds for sending out heartbeat frames.  A value of 0 means no heartbeats will be sent.

* __-blockedConnections__

    Either 0 or 1, but defaults to 1.  Controls whether to use this [RabbitMQ extension](https://www.rabbitmq.com/connection-blocked.html).

* __-cancelNotifications__

    Either 0 or 1, but deafults to 1.  Controls whether to use this [RabbitMQ extension](https://www.rabbitmq.com/specification.html).

* __-maxTimeout__

    Integer seconds to wait before timing out the connection attempt to the server.  Defaults to 3.

* __-autoReconnect__

    Either 0 or 1, but defaults to 1.  Controls whether the library attempts to reconnect to the RabbitMQ server when the initial call to _Connection.connect_ fails or an established socket connection is closed by the server or by network conditions.

* __-maxBackoff__

    Integer number of seconds past which [exponential backoff](https://cloud.google.com/storage/docs/exponential-backoff), which is the reconnection strategy employed, will not go.  Defaults to 64 seconds.

* __-maxReconnects__

    Integer number of reconnects to attempt before giving up.  Defaults to 5.  A value of 0 means infinite reconnects.  To disable retries, pass _-autoReconnect_ as 0.

* __-debug__

    Either 0 or 1, but defaults to 0.  Controls whether or not debug statements are printed to stderr detailing the operations of the library.

### attemptReconnect

Takes no arguments.  Using the _-maxBackoff_ and _-maxReconnects_ constructor arguments, attempts to reconnect to the server.  If this cannot be done, and an _onFailedReconnect_ callback has been set, it is invoked.

### closeConnection

Takes an optional boolean argument controlling whether the _onClose_ callback is invoked (defaults to true).  Closes the connection and, if specified, calls any callback set with _onClose_.

### connect

Takes no arguments.  Actually initiates a socket connection with the RabbitMQ server.  If the connection fails the _onClose_ callback is invoked.
Two timeouts can potentially occur in this method: one during the TCP handshake and one during the AMQP handshake.  In both cases, the _-maxTimeout_ variable is used.

### connected?

Takes no arguments.  Returns 0 or 1 depending on whether the socket connection to the server has been established.  This does not indicate
whether or not the AMQP connection handshake has been completed (that is indicated by the invocation of the _onConnected_ callback).  This method
is available for detecting an inability to establish a network connection.

### getSocket

Takes no arguments.  Returns the socket object for communicating with the server.  This allows for more fine-grained inspection and tuning if
so desired.

### onBlocked 

Takes the name of a callback proc which will be used for [blocked connection notifications](https://www.rabbitmq.com/connection-blocked.html).
Blocked connection notifications are always requested by this library, but the setting of a callback is optional.  The callback takes
the _Connection_ object, a boolean for whether the connection is blocked (this callback is also used when the connection is no longer
blocked), and a textual reason why.

### onClose

Takes the name of a callback proc which will be called when the connection is closed.  This includes a failed connection to the RabbitMQ server when
first calling _connect_ and a disconnection after establishing communication with the RabbitMQ server.  The callback takes the _Connection_
object and a dictionary of data specified in the section above about callbacks.

### onClosed

Alias for _onClose_ method.

### onConnected

Takes the name of a callback proc which will be used when the AMQP handshake is finished.  When this callback is invoked, the _Connection_
object is ready to create channels and perform useful work.       

### onError

Takes the name of a callback proc used when an error is reported by the RabbitMQ server on the connection level.  The callback proc takes
the _Connection_ object, a frame type and any extra data included in the frame.

### onFailedReconnect

Takes the name of a callback proc used when the maximum number of connection attempts have been made without sucess.  The callback proc takes the __Connection__ object.

### removeCallbacks

Takes an optional boolean _channelsToo_, which defaults to 0.  Unsets all callbacks for the _Connection_ object.  If _channelsToo_ is 1, also unsets callbacks on all of its channels. 

### tlsOptions

Used to setup the parameters for an SSL / TLS connection to the RabbitMQ server.  
Supports all arguments supported by the Tcl tls package's `::tls::import::` command
as specified in the [Tcl TLS documentation](http://tls.sourceforge.net/tls.htm).

If a TLS connection is desired, this method needs to be called before _connect_.

## _Login_ Class

### constructor

The constructor takes the following arguments (all optional):

* __-user__

    Username to login with.  Defaults to guest

* __-pass__

    Password to login with.  Defaults to guest

* __-mechanism__

    Authentication mechanism to use.  Defaults to PLAIN

* __-vhost__

    Virtual host to login to.  Defaults to /

### saslResponse

Takes no arguments.  This method needs to overridden if an alternative mechanism is desired.

## _Channel_ Class

Most of the methods made available by this library come from the _Channel_ class.  It implements the majority of the AMQP methods.

### constructor

Takes the following arguments:

* __connectionObj__

    The _Connection_ object to open a channel for.  This is the only required argument.

* __channelNum__

    The channel number to open.  Optional.  If not specified, the next available number starting from 1 will be used.  Passing in an
    empty string or 0 is equivalent to not providing this argument, i.e., the class will pick the next available channel number for the 
    _Connection_ object provided.

* __shouldOpen__

    A boolean argument that defaults to 1.  If set to 1 the channel will open after it is created.  If not, the _channelOpen_ method must be
    called manually before anything can be done with the _Channel_ object.

### active?

Takes no arguments and returns 1 if the channel is active, i.e., it has been opened successfully, and 0 otherwise.

### closeChannel

Takes no arguments and closes the channel.  If an _onClose_ callback has been specified it is called with the _Channel_ object and 
a dictionary containing the following keys and values (all keys will be included even if their value is empty):

* __data__

    Any data sent back from the server when closing.  Usually empty.

* __replyCode__

    The numeric reply code sent from the server.

* __replyText__

    Textual description of the reply code.  Useful for troubleshooting purposes.

* __classID__

    Numeric class ID for the class responsible for the closing if appropriate.

* __methodID__

    Numeric method ID for the method responsible for the closing if appropriate.

### closeConnection

Takes an optional boolean argument, _callCloseCB_, which defaults to 1.  Closes the associated _Connection_ object and if _callCloseCB_ is true, any callback set with _onClose_ is invoked, otherwise it is ignored.

### closing?

Takes no arguments and returns 1 if the _Channel_ is in the process of closing and 0 otherwise.

### getChannelNum

Takes no arguments, and returns the channel number.

### getConnection

Takes no arguments, and returns the _Connection_ object passed into the constructor.

### open?
 
Alias for _active?_.

### on

Takes an AMQP method name in camel case, starting with a lower case letter and the name of a callback proc for the method.  To unset a callback, set its callback proc to the empty string or use _removeCallback_.

### onClose

Takes the name of a callback proc to be called when the channel is closed.  The callback takes the _Channel_ object and a dictionary
of data, which is specified in the README section about callbacks and in the _closeChannel_ method description above.

### onClosed

Alias for _onClose_.

### onError

Takes the name of a callback proc invoked when an error occurs on this particular _Channel_ object.  The error callback is passed
the _Channel_ object, a numeric error code as returned from the server, and any additional data passed back.  Errors occur on a channel
when the server returns an unexpected response but not when a disconnection occurs or the channel is closed forcefully by the server.

### onOpen

Takes the name of a callback proc to be called when the channel successfully opens.  Once it is open, AMQP methods can be called.
The callback takes the _Channel_ object.

### onOpened

Alias for _onOpen_.

### reconnecting?

Takes no arguments.  Returns 1 if _Connection_ is in the process of attempting a reconnect and 0 otherwise.

### removeCallback

Takes the name of an AMQP method as defined on a _Channel_ object.  

### removeCallbacks

Takes no arguments.  Sets all callbacks to the empty string, effectively removing them.

### setCallback

Takes the name of an AMQP method as defined on a _Channel_ object (or for the _on_ Channel method).  The preferred method to use is _on_, but this is alternative method for setting a callback.  To unset a callback, set its callback proc to the empty string or use _removeCallback_.

## _Channel_ AMQP Methods

The following methods are defined on _Channel_ objects and implement the methods and classes detailed in the 
[AMQP specification](https://www.rabbitmq.com/resources/specs/amqp-xml-doc0-9-1.pdf).

### Channel Methods

#### channelClose

Takes the following arguments:

* __data__

    String of data potentially transferred during closing.

* __replyCode__

    Numeric reply code for closing the channel as specified in the AMQP specification.

* __replyText__

    Textual description of the reply code.

* __classID__

    AMQP class ID number.

* __methodID__

    AMQP method ID number.

To place a callback for the closing of a channel, use the _onClose_ or _onClosed_ method.  The callback takes the _Channel_ object
and a dictionary of data describing the reason for the closing.

#### channelOpen

Takes no arguments.

To place a callback for the opening of a channel use the _onOpen_ method.  The callback takes only the _Channel_ object.

### Exchange Methods

#### exchangeBind

Takes the following arguments:

* __dst__
 
    Destination exchange name.

* __src__

    Source exchange name.

* __rKey__

    Routing key for the exchange binding.

* __noWait__

    Boolean integer, which defaults to 0.

* __eArgs__

    Exchange binding arguments (optional).  Passed in as a dict.  Defaults to an empty dict.

To set a callback for exchange to exchange bindings use the _on_ method with _exchangeBindOk_ as the first argument.
Callback only takes the _Channel_ object.

#### exchangeDeclare

Takes the following arguments:

* __eName__

    Exchange name.

* __eType__

    Exchange type: direct, fanout, header, topic

* __eFlags__

    Optional flags.  Flags supported (all in the ::rmq namespace): 

    - EXCHANGE_PASSIVE

    - EXCHANGE_DURABLE 

    - EXCHANGE_AUTO_DELETE

    - EXCHANGE_INTERNAL

    - EXCHANGE_NO_WAIT

* __eArgs__

    Optional dict of exchange declare arguments. 

To set a callback on an exchange declaration, use the _on_ method with _exchangeDeclareOk_ as the first argument.
Callback only takes the _Channel_ object.

#### exchangeDelete

Takes the following arguments:

* __eName__

    Exchange name to delete.

* __inUse__

    Optional boolean argument defaults to 0.  If set to 1, will not delete an exchange with bindings on it.

* __noWait__

    Optional boolean argument defaults to 0.  

To set a callback on the exchange deletion, use the _on_ method with _exchangeDeleteOk_ as the first argument.
Callback only takes the _Channel_ object.

#### exchangeUnbind

Takes the same arguments as _exchangeBind_, with the same callback data.

### Queue Methods

#### queueBind

Takes the following arguments:

* __qName__

    Queue name.

* __eName__

    Exchange name.

* __rKey__

    Routing key (optional).  Defaults to the empty string.

* __noWait__

    Boolean integer (optional).  Defaults to 0.

* __qArgs__

    Queue binding arguments (optional).  Needs to be passed in as a dict.  Defaults to an empty dict.

To set a callback on a queue binding, use the _on_ method with _queueBindOk_ as the first argument.
Callback only takes the _Channel_ object.

#### queueDeclare

Takes the following arguments:

* __qName__

    Queue name.

* __qFlags__

    Optional list of queue declare flags.  Supports the following flag constants (in the ::rmq namespace):

    - QUEUE_PASSIVE 

    - QUEUE_DURABLE 

    - QUEUE_EXCLUSIVE 

    - QUEUE_AUTO_DELETE 

    - QUEUE_DECLARE_NO_WAIT

To set a callback on a queue declare, use the _on_ method with _queueDeclareOk_ as the first argument.
Callback takes the _Channel_ object, the queue name (especially important for exclusive queues), message count,
number of consumers on the queue.

#### queueDelete

Takes the following arguments:

* __qName__

    Queue name.

* __flags__

    Optional list of flags.  Supported flags (in the ::rmq namespace):


    - QUEUE_IF_UNUSED 

    - QUEUE_IF_EMPTY 

    - QUEUE_DELETE_NO_WAIT

To set a callback on a queue delete, use the _on_ method with _queueDeleteOk_ as the first argument.
Callback takes the _Channel_ object and a message count from the delete queue.

#### queuePurge

Takes the following arguments:

* __qName__

    Queue name.

* __noWait__

    Optional boolean argument.  Defaults to 0.

To set a callback on a queue purge, use the _on_ method with _queuePurgeOk_ as the first argument.
Callback takes the _Channel_ object and a message count from the purged queue.

#### queueUnbind

Takes the following arguments:

* __qName__

    Queue name.

* __eName__

    Exchange name.

* __rKey__

    Routing key.

* __qArgs__

    Optional queue arguments.  Passed in as a dict.

To set a callback on a queue unbinding, use the _on_ method with _queueUnbindOk_ as the first argument.
Callback takes only the _Channel_ object.

### Basic Methods

#### basicAck

Takes the following arguments:

* __deliveryTag__

    Delivery tag being acknowledged.

* __multiple__

    Optional boolean, defaults to 0.  If set to 1, all messages up to and including the _deliveryTag_ argument's value.

Setting a callback on this method using the _on_ method is for publisher confirms.  The callback takes the _Channel_
object, a delivery tag and a multiple boolean.

#### basicCancel

Takes the following arguments:

* __cTag__

    Consumer tag.

* __noWait__

    Optional boolean argument.  Defaults to 0.

To set a callback on a basic cancel, use the _on_ method with _basicCancelOk_ as the first argument.
Callback takes the _Channel_ object and the consumer tag that was canceled.

#### basicConsume

Takes the following arguments:

* __callback__

    Name of a callback to use for consuming messages.  The callback takes the _Channel_ object, a dict of method data, a dict of
    frame data and the data from the queue.

* __qName__

    Queue name to consume from.

* __cTag__

    Optional consumer tag.

* __cFlags__

    Optional list of flags.  Supported flags (all in the ::rmq namespace):

    - CONSUME_NO_LOCAL

    - CONSUME_NO_ACK

    - CONSUME_EXCLUSIVE

    - CONSUME_NO_WAIT

* __cArgs__

    Optional arguments to control consuming.  Passed in as a dict.  Supports all arguments specified for the
    [basic class](https://www.rabbitmq.com/amqp-0-9-1-reference.html).

Callback is set directly from this method.

#### basicGet

Takes the following arguments:

* __callback__

    Name of a callback proc using the same arguments as that for _basicConsume_.

* __qName__

    Queue name to get a message from

* __noWait__

    Optional boolean.  Defaults to 0.

Like with _basicConsume_ the callback for this method is set directly from the method call.

#### basicNack

Takes the following arguments:

* __deliveryTag__

    Delivery tag for message being nack'ed.

* __nackFlags__

    Optional list of flags.  Supports the following (in the ::rmq namespace):

    - NACK_MULTIPLE

    - NACK_REQUEUE

Setting a callback on this method using the _on_ method is for publisher confirms.  The callback takes the _Channel_
object, a delivery tag and a multiple boolean.

#### basicQos

Takes the following arguments:

* __prefetchCount__

    Integer prefetch count, i.e., the number of unacknowledged messages that can be delivered to a consumer at one time.

* __globalQos__

    Optional boolean which defaults to 0.  If set to 1, the prefecth count is set globally [for all consumers on the channel](https://www.rabbitmq.com/consumer-prefetch.html).

To set a callback on a basic QOS call, use the _on_ method with _basicQosOk_ as the first argument.
Callback takes only the _Channel_ object.

#### basicPublish

Takes the following arguments:

* __data__

    The data to publish to the queue.

* __eName__

    Exchange name.

* __rKey__

    Routing key.

* __pFlags__

    Optional list of flags.  Supports the following flags (in the ::rmq namespace):

    - PUBLISH_MANDATORY 

    - PUBLISH_IMMEDIATE

No callback can be set on this directly.  For [publisher confirms](https://www.rabbitmq.com/confirms.html)
use the _on_ method with _basicAck_ as the first argument.  That callback takes the _Channel_ object,
the delivery tag and a boolean for whether the ack is for multiple messages.

#### basicRecover

Same as _basicRecoverAsync_.

### Confirm Methods

#### confirmSelect

Takes the following arguments:

* __noWait__

    Optional boolean argument, defaults to 0.

To set a callback on a confirm select call, use the _on_ method with _confirmSelectOk_ as the first argument.
Callback takes the _Channel_ object.

#### basicRecoverAsync

Takes the following arguments:

* __reQueue__

    Boolean argument.  If 0, the message will be redelivered to the original recipient.  If 1, an
    alternate recipient can get the redelivery.

To set a callback on a basic recover, use the _on_ method with _basicRecoverOk_ as the first argument.
Callback takes the _Channel_ object. 

#### basicReject

Takes the following arguments:

* __deliveryTag__

    Delivery tag of message being rejected by the client.

* __reQueue__

    Optional boolean argument, defaults to 0.  If set to 1, the rejected message will be requeued.

#### basicReturn

This method is not to be called directly, but to use a callback to handle returned messages, use the _on_ method
with _basicReturn_ as the first argument.  The callback takes the same arguments as the _basicConsume_ callback.

### TX Methods

#### txSelect

Takes no arguments.

To set a callback on a transaction select call, use the _on_ method with _txSelectOk_ as the first argument.
Callback takes the _Channel_ object.

#### txCommit

Takes no arguments.

To set a callback on a transaction commit call, use the _on_ method with _txCommitOk_ as the first argument.
Callback takes the _Channel_ object.

#### txRollback

Takes no arguments.

To set a callback on a transaction commit call, use the _on_ method with _txRollbackOk_ as the first argument.
Callback takes the _Channel_ object.
