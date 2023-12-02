# RocketChatGD

A WIP GDScript wrapper for Rocket.Chat's protocol. Used in an upcoming project
of mine.

It doesn't support a lot of features yet and unfortunately the only copy of the
protocol documentation I found wasn't very complete, updated nor consistent so
expect some funny comments and wrong assumptions.

This is barely alpha quality so don't expect a stable API for the time being,
sorry.


## Usage

Simply put this repository into the project (a git submodule would be a good
idea), then use as in the demo below.

The API should be mostly documented through documentation comments, so feel free
to take a look at them.

This library is currently divided in two parts:

 - `RocketChatRealtimeAPIClient`, a "low level client" which handles the
underlying "real time API" built on top of WebSocket.

 - `RocketChat`, a fancy (mostly incomplete) client which, through the help of
the realtime API client, wraps the whole API into custom type-safe objects,
methods and signals for ease of use.


## Simple demo (self-contained)

```gdscript
extends Node

# This is an simple example showing how to use this library. The API is subject
# to change.

# To use this demo, obtain and set an authentication token as indicated in the
# code and assign this script to a plain `Node`. Once executed, if everything
# goes right, it will print a list of subscriptions (see below and the library
# documentation for further info on the terminology).

# NOTE: Instantiating the node in any other way is fine too (singleton, scene
# tree editor, etc.)
@onready var rc: RocketChat = RocketChat.new()


func _ready() -> void:
	# NOTE: This is the default as of writing.
	rc.instance_url = "https://chat.godotengine.org"

	rc.connected.connect(_rc_on_connected)
	rc.login_request_completed.connect(_rc_on_login_request_completed)

	add_child(rc)


func _rc_on_connected(session_id: String) -> void:
	print("Connected succesfully. Session id: " + session_id)

	# The server shook hands with us and everything else. Only now any meaningful
	# request, such as login, will be taken care of by the server.

	# This brings us to the next step, authentication. Currently, only token-based
	# authentication is implemented. You can get a token from the account
	# preferences under "Personal Access Tokens".
	rc.login_with_token("INSERT_TOKEN_HERE")


func _rc_on_login_request_completed(id: String) -> void:
	print("Login complete. ID: " + id)

	# Now that we're authenticated we can do everything that the web client can do.
	# Let's print the list of subscriptions associated with our account. They are,
	# in simple words, the complete info about the rooms you're, well, subscribed
	# to. They include information such as the full room name, mention counter,
	# read status and so on.

	# Most requests, if not all of them, are async. Paired with `await` you can get
	# quite a bit of control on whether a request is asynchronous or synchronous.
	# In this case, though, we need it to be synchronous, otherwise we would not be
	# able to get the result of the request.
	var subs: Array[RocketChat.Subscription] = await rc.get_subscriptions()

	print("Available subscriptions:")
	for sub: RocketChat.Subscription in subs:
		# NOTE: Not all channels have necessarily a full name, so we'll have to
		# fallback to the "dumber" plain name. The latter should be equivalent to the
		# "#" or "@" ID (e.g. `#coffee-break`, `@riteo`)
		if not sub.full_name.is_empty():
			print(sub.full_name)
		else:
			print(sub.name)
```


## License

This work is licensed under the MIT (Expat) license, a pretty simple and
battle-tested permissive license.

See the `LICENSE.txt` file for further information.
