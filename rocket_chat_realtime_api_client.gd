extends Node

## Low-level client on top of RocketChat's realtime API.
class_name RocketChatRealtimeAPIClient


# TODO: Improve. I don't like these a lot.
enum Status {
	DISCONNECTED, ## The client hasn't tried to connect to anything yet. Default state.
	CONNECTING, ## The client is currently attempting to connect to the server.
	CONNECTED, ## The client has successfully connected to the server.
	CLOSED, ## The connection has been closed and must be reattempted to continue.
}


## Emitted as soon as the client successfully opens a socket with the server.
## [br]
## [b]Warning:[/b] This is the absolute first response emitted from the server
## and does not guarantee a successful connection nor can any request be made as
## soon as this signal is received, see [signal connected].
signal server_id(id: String)

## Emitted after the server confirms to the client that it can accept requests.
signal connected(session: String)

## Emitted as soon as the client receives a "ping" message from the server.[br]
## [b]Note:[/b] This class already responds with the appropriate "pong" message,
## so the user doesn't have to handle this themselves. This signal is purely
## informational and available in case it might be useful to know when the
## server sends a "ping".
signal ping()

## Emitted after receiving a raw "result" message, usually originating from a
## previous request.
signal result(id: String, result: Dictionary)

## Emitted after receiving a raw "changed" message, usually originating from an
## active subscription.
signal collection_changed(collection: String, id: String, data: Dictionary)

## Emitted after receiving a raw "nosub" message, which happens when the server
## receives an invalid subscription message with a duplicate, invalid or
## non-existent ID.
signal nosub(id: String)


## If true, all messages coming to and from the server will be dumped to the
## console.[br]
##[b]Warning:[/b] Debug logs may contain sensitive data, such as credentials
## or tokens!
var debug := false

var _status := Status.DISCONNECTED
var _socket := WebSocketPeer.new()


## Returns the [Status] of this client.
func get_status() -> Status:
	return _status


## Calls a Realtime API method with its own parameters, awaits a result from the
## server and returns the parsed data. Calling it while the client isn't
## connected will result in an error.
func call_method_sync(method: String, params: Array):
	assert(_status == Status.CONNECTED, "Client must be connected to call a method.")

	var id: String = str(randi())

	var method_data: Dictionary = {
		"msg": "method",
		"method": method,
		"id": id,
		"params": params
	}

	# DEBUG
	if debug:
		print("Sending data %s" % JSON.stringify(method_data))

	_socket.send_text(JSON.stringify(method_data))

	var result_data

	# I have no idea if there's a better way of detecting whether the result's
	# ours without looking at the ID of every new one incoming. Anyways, this
	# works.
	while (result_data == null):
		var result_args: Array = await result
		# We expect two and only two arguments: the id and the actual data.
		assert(result_args.size() == 2)

		var result_id: String = result_args[0] as String
		assert(result_id)

		if (result_id == id):
			result_data = result_args[1]

	return result_data


## Subscribes the client to the stream [code]stream_name[/code] with [code]
## params[/code] and returns its ID.[br]
## If the stream watches a collection, [signal collection_changed] will be
## emitted.
func subscribe_stream(stream_name: String, params: Array) -> String:
	var id: String = str(randi())

	var subscribe_data: Dictionary = {
		"msg": "sub",
		"id": id,
		"name": stream_name,
		"params": params,
	}

	_socket.send_text(JSON.stringify(subscribe_data))

	return id


## Unsubscribes the client from the stream identified by [code]stream_id[/code].
func unsubscribe_stream_id(stream_id: String) -> void:
	var unsubscribe_data: Dictionary = {
		"msg": "unsub",
		"id": stream_id,
	}

	_socket.send_text(JSON.stringify(unsubscribe_data))

	while true:
		var nosub_result: String = await nosub
		assert(nosub_result)

		var nosub_id: String = nosub_result[0] as String
		assert(nosub_id)

		if nosub_id == stream_id:
			break


## Connects to the given URL. [code]url[/code] must begin with
## [code]wss://[/code].
func connect_to_url(url: String) -> void:
	assert(url.begins_with("wss://"), "URL must start with 'wss://'.")

	print("Opening a WebSocket connection...")
	_socket.connect_to_url(url)


func _init() -> void:
	# Without this packets are limited to 2^16 bytes, which isn't enough for big
	# messages.
	_socket.inbound_buffer_size = 2**24


func _process(_delta: float) -> void:
	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _status == Status.DISCONNECTED:
				print("WebSocket open, connecting to RocketChat...")

				var connect_data: Dictionary = {
					"msg": "connect",
					"version": "1",
					"support": ["1"],
				}
				_socket.send_text(JSON.stringify(connect_data))

				_status = Status.CONNECTING

			while _socket.get_available_packet_count() > 0:
				var response: String = _socket.get_packet().get_string_from_utf8()

				# DEBUG
				if debug:
					print("DEBUG: Received response of size %d: %s" % [response.length(), response])

				var response_data: Dictionary = JSON.parse_string(response) as Dictionary
				assert(response_data.size() > 0, "Invalid JSON.")

				# Just connected
				if response_data.has("server_id"):
					var id: String = response_data.get("server_id") as String
					assert(id)

					server_id.emit(id)

				match response_data.get("msg"):
					"connected":
						var session_id: String = response_data.get("session") as String
						assert(session_id)

						_status = Status.CONNECTED

						connected.emit(session_id)

					"ping":
						ping.emit()
						_socket.send_text('{"msg":"pong"}')

					"result":
						var id: String = response_data.get("id") as String
						assert(id)

						var result_data = response_data.get("result", {})

						result.emit(id, result_data)

					"nosub":
						var id: String = response_data.get("id") as String
						assert(id)

						nosub.emit(id)

					"changed":
						var collection: String = response_data.get("collection") as String
						assert(collection)

						var id: String = response_data.get("id") as String
						assert(id)

						var data: Dictionary = response_data.get("fields") as Dictionary
						assert(data)

						collection_changed.emit(collection, id, data)

		WebSocketPeer.STATE_CLOSED:
			_status = Status.CLOSED
			print("Closed. Disabling. Reason: \"%s\". Code: %d" % [_socket.get_close_reason(), _socket.get_close_code()])
			set_process(false)
