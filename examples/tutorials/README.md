# Tutorial Examples

This folder contains examples from the [RabbitMQ tutorials](https://www.rabbitmq.com/tutorials/tutorial-one-python.html).

## Defaults

Each example connects to a RabbitMQ server on `localhost:5672` using `guest` as username and password.

If this is not desirable, pass appropriate `-host` and `-port` arguments to the `Connection` constructor
and/or create a `Login` object, specifying `-user` and `-pass` in its constructor.
