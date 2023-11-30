extends Node

## High level wrapper on top of [RocketChatRealtimeAPIClient].
class_name RocketChat

enum MessageType {
	UNKNOWN, ## Got a type but there was no corresponding enum.
	GENERIC, ## Normal message, no type has been otherwise specified.
	ROOM_NAME_CHANGED, ## The room's name has changed.
	USER_ADDED_BY, ## A user got added to the room by someone.
	USER_REMOVED_BY, ## A user got removed from the room by someone.
	USER_LEFT, ## A user left the room themselves.
	USER_LEFT_TEAM, ## A user left the team themselves.
	USER_JOINED_CHANNEL, ## A user joined the channel.
	USER_JOINED_TEAM, ## A user joined the team.
	USER_JOINED_CONVERSATION, ## A user joined the conversation.
	MESSAGE_REMOVED,
	ADDED_USER_TO_TEAM, ## A user got added to the team.
	REMOVED_USER_FROM_TEAM, ## A user got removed from the team.
	USER_MUTED_BY, ## A user got muted by someone.
}


enum SubscriptionType {
	UNKOWN, ## Invalid subscription type.
	DIRECT_CHAT, ## A conversation between two users.
	CHAT, ## A conversation between multiple people.
	PRIVATE_CHAT, ## A conversation which might be read-only to certain users.
	LIVE_CHAT,
}


enum StreamNotifyRoomEvent {
	DELETE_MESSAGE, ## Event reporting when a message is deleted.
	TYPING, ## Event reporting when a user starts or stops writing.
	USER_ACTIVITY, ## Event reporting whether a user changes their activity, e.g becomes online.
}


enum StreamNotifyUserEvent {
	MESSAGE,
	OFF_THE_RECORD,
	WEBRTC,
	NOTIFICATION,
	ROOMS_CHANGED,
	SUBSCRIPTIONS_CHANGED, ## Event reporting whether the user's subscriptions changed.
}


class User:
	## The user's unique ID.
	var id: String

	## The user's username, used for mentions and fetching their avatar.
	var username: String

	## The user's full name. Can be empty.
	var name: String


class Attachment:
	class Field:
		var is_short: bool
		var title: String
		var value: String

	var color: Color
	var text: String
	var timestamp: int
	var thumbnail_url: String
	var link: String
	var is_collapsed: bool
	var author_name: String
	var author_link: String
	var author_icon_url: String
	var title: String
	var title_link: String
	var can_download_title_link: bool
	var image_url: String
	var audio_url: String
	var video_url: String
	var fields: Array[Field]


class Message:
	var type: MessageType

	var id: String
	var room_id: String
	var text: String
	var thread_id: String
	var creation_timestamp: int
	var mentioned_users: Array[User]
	var author: User
	# TODO: `blocks`.
	# TODO: `md`.
	var starred_user_ids: Array[String]
	var is_pinned: bool
	var is_unread: bool
	var is_temporal: bool
	var direct_room_id: String
	var update_timestamp: int
	var edit_timestamp : int
	var edit_author: User
	# TODO: `urls`.
	var attachments: Array[Attachment]
	var alias: String
	var avatar_url: String
	var is_groupable: bool
	var channel: String
	var should_parse_urls: bool
	# TODO: `tlm`.
	# TODO: `reactions`.


## A single places where users can join and send messages.
class Room:
	## The room's unique ID.
	var id: String

	# FIXME: Is this used?
	var update_epoch: int


## A conversation between two user.
class DirectChat extends Room:
	pass


## A conversation between multiple users.
class Chat extends Room:
	## The name of the chat, used for name-based addressing.
	var name: String

	## The user who created the chat.
	var creator: User

	## A string describing the topic of the discussion inside the chat.
	var topic: String

	## A list of usernames which got muted.
	var muted_usernames: Array[String]


## Info about the relation of room and a user, such as the number of unread
## mentions.
class Subscription:
	var type: SubscriptionType = SubscriptionType.UNKOWN
	var creation_time: int
	var last_seen_time: int
	var name: String
	var full_name: String
	var room_id: String
	var is_favorite: bool
	var is_open: bool
	var has_alert: bool
	var unread_mention_count: int
	var user: User
	# WTF, the documentation lists _two_ schemas, both with something missing.
	#var roles: Array[String]
	#var unread_message_count: int
	#var unread_thread_ids: Array[String]
	#var unread_thread_ids_group: Array[String]
	#var unread_thread_ids_mention: Array[String]
	#var update_time: int
	#var id: String
	#var last_thread_reply_time: int
	#var hide_unread_status: bool
	#var is_team_main_room: bool
	#var team_id: String
	#var unread_mention_count: int
	#var unread_group_mention_count: int
	#var parent_room_id: String


## Object describing the list of updated and removed rooms from a list.
class ChangedRoom:
	var updated: Array[Room]
	var removed: Array[Room]


## Object describing the list of removed, inserted and updated rooms from a
## list.
class ChangedSubscriptions:
	var removed: Array[Subscription]
	var inserted: Array[Subscription]
	var updated: Array[Subscription]


## Emitted when the client successfully connects and get a valid initial
## response from the server.
signal connected(session_id: String)

## Emitted when the clients receives a login response from the server.
signal login_request_completed(id: String)

## Emitted when the client receives new messages from room [code]room_id[/code].
## Gets fired only after subscribing to the respective room's message stream.
## See [method subscribe_room_messages].
signal room_messages_changed(room_id: String, messages: Array[Message])

## Emitted when the message with id [code]message_id[/code] gets deleted from
## the room with ID [code]room_id[/code].
signal room_message_id_deleted(room_id: String, message_id: String)


## Emitted when a user's subscriptions change.
signal subscriptions_changed(user_id: String, changed_subscriptions: ChangedSubscriptions)

@export
var instance_url : String = "https://chat.godotengine.org"

var _client: RocketChatRealtimeAPIClient


# NOTE: Returns null in case of invalid user (no id)
func _parse_user_data(data: Dictionary) -> User:
	var user := User.new()

	user.id = data.get("_id", "")

	if user.id.is_empty():
		return null

	user.username = data.get("username", "")
	user.name = data.get("name", "")

	return user


func _parse_attachment_data(data: Dictionary) -> Attachment:
	var attachment := Attachment.new()

	attachment.color = Color.from_string(data.get("color", ""), Color.WHITE)
	attachment.text = data.get("text", "")

	# NOTE: For some mystical reason the timestamp can be formatted in both the
	# "old" ISO 8601 format and the "new" [Dictionary]-based one. I have no idea
	# why.
	var time_object = data.get("ts")

	if time_object is Dictionary:
		var time_dict := time_object as Dictionary
		attachment.timestamp = time_dict.get("$date", 0)
	elif time_object is String:
		var time_string := time_object as String
		time_string = time_string.rstrip("Z")
		attachment.timestamp = Time.get_unix_time_from_datetime_string(time_string)

	#print("Converted timestamp %s to %d" % [time_object, attachment.timestamp])

	attachment.image_url = data.get("image_url", "")

	return attachment


func _parse_message_data(data: Dictionary) -> Message:
	var message := Message.new()

	var type_string := data.get("t", "") as String

	match type_string:
		"":
			message.type = MessageType.GENERIC

		"r":
			message.type = MessageType.ROOM_NAME_CHANGED

		"au":
			message.type = MessageType.USER_ADDED_BY

		"ru":
			message.type = MessageType.USER_REMOVED_BY

		"ul":
			message.type = MessageType.USER_LEFT

		"ult":
			message.type = MessageType.USER_LEFT_TEAM

		"uj":
			message.type = MessageType.USER_JOINED_CHANNEL

		"ujt":
			message.type = MessageType.USER_JOINED_TEAM

		"ut":
			message.type = MessageType.USER_JOINED_CONVERSATION

		"rm":
			message.type = MessageType.MESSAGE_REMOVED

		"added-user-to-team":
			message.type = MessageType.ADDED_USER_TO_TEAM

		"removed-user-from-team":
			message.type = MessageType.REMOVED_USER_FROM_TEAM

		"user-muted":
			message.type = MessageType.USER_MUTED_BY

		_:
			push_warning("Unknown message type received: %s", type_string)

	message.id = data.get("_id") as String
	message.room_id = data.get("rid") as String
	message.text = data.get("msg", "") as String

	message.creation_timestamp = (data.get("ts", {}) as Dictionary).get("$date", 0)

	for user_data in data.get("mentions", []) as Array:
		var user: User = _parse_user_data(user_data)

		if user:
			message.mentioned_users.push_back(user)

	message.thread_id = data.get("tmid", "") as String
	message.author = _parse_user_data(data.get("u", {}))

	# TODO: `blocks`.
	# TODO: `md`.

	for id in data.get("starred", []) as Array:
		assert(id is String)
		message.starred_user_ids.push_back(id)

	message.is_pinned = data.get("pinned", false)
	message.is_unread = data.get("unread", false)
	message.is_temporal = data.get("temp", false)
	message.direct_room_id = data.get("drid", "")
	message.update_timestamp = (data.get("_updatedAt", {}) as Dictionary).get("$date", 0)
	message.edit_author = _parse_user_data(data.get("editedBy", {}))

	# TODO: `urls`.

	for attachment_data in data.get("attachments", []):
		var attachment: Attachment = _parse_attachment_data(attachment_data)

		if attachment:
			message.attachments.push_back(attachment)

	message.avatar_url = data.get("avatar", "")
	message.is_groupable = data.get("groupable", false)
	message.channel = data.get("channel", "")
	message.should_parse_urls = data.get("parseUrls", false)

	# TODO: `tlm`.
	# TODO: `reactions`.

	return message


func _parse_message_list_data(messages_data: Array) -> Array[Message]:
	var messages: Array[Message] = []

	for message_data in messages_data:
		assert(message_data is Dictionary)
		messages.push_back(_parse_message_data(message_data))

	return messages


func _parse_room_data(data: Dictionary) -> Room:
	var new_room: Room

	var type: String = data.get("t", "")

	match type:
		"c":
			# Chat
			var new_chat := Chat.new()
			new_chat.name = data.get("name", "")
			new_chat.creator = _parse_user_data(data.get("u", {}))
			new_chat.topic = data.get("topic", "")

			for username in data.get("muted", []) as Array:
				assert(username as String)
				new_chat.muted_usernames.push_back(username)

			new_room = new_chat

		"d":
			# Direct chat
			var new_direct := DirectChat.new()
			new_room = new_direct

		_:
			new_room = Room.new()

	assert(new_room)

	new_room.id = data.get("_id", "")
	# Must NOT be null.
	assert(new_room.id)

	var update_date_object: Dictionary = data.get("_updatedAt", {}) as Dictionary
	new_room.update_epoch = update_date_object.get("$date", 0) as int

	return new_room


func _parse_room_list_data(rooms_data: Array) -> Array[Room]:
	var rooms: Array[Room] = []

	for room_data in rooms_data:
		assert(room_data is Dictionary)
		rooms.push_back(_parse_room_data(room_data))

	return rooms


func _parse_subscription_data(data: Dictionary) -> Subscription:
	var new_sub := Subscription.new()

	match data.get("t", ""):
		"d":
			new_sub.type = SubscriptionType.DIRECT_CHAT

		"c":
			new_sub.type = SubscriptionType.CHAT

		"p":
			new_sub.type = SubscriptionType.PRIVATE_CHAT

		"l":
			new_sub.type = SubscriptionType.LIVE_CHAT

		_:
			new_sub.type = SubscriptionType.UNKOWN

	new_sub.creation_time = (data.get("ts", {}) as Dictionary).get("$date", 0)
	new_sub.last_seen_time = (data.get("ls", {}) as Dictionary).get("$date", 0)
	new_sub.name = data.get("name", "")
	new_sub.full_name = data.get("fname", "")
	new_sub.room_id = data.get("rid", "")

	new_sub.is_favorite = data.get("f", false)
	new_sub.is_open = data.get("open", false)
	new_sub.has_alert = data.get("alert", false)
	new_sub.unread_mention_count = data.get("unread", 0)

	new_sub.user = _parse_user_data(data.get("u", {}))

	#new_sub.roles = data.get("roles", [] as Array[String])
	#new_sub.unread_message_count = data.get("unread", 0)

	#for id in data.get("tunread", []):
	#	if id is String:
	#		new_sub.unread_thread_ids.push_back(id)
	#
	#for id in data.get("tunreadGroup", []):
	#	if id is String:
	#		new_sub.unread_thread_ids_group.push_back(id)
	#
	#for id in data.get("tunreadUser", []):
	#	if id is String:
	#		new_sub.unread_thread_ids_mention.push_back(id)
	#
	#new_sub.update_time = (data.get("_updatedAt", {}) as Dictionary).get("$date", 0)
	#new_sub.id = data.get("_id", "")
	#new_sub.last_thread_reply_time = (data.get("lr", {}) as Dictionary).get("$date", 0)
	#new_sub.hide_unread_status = data.get("hideUnreadStatus", false)
	#new_sub.is_team_main_room = data.get("teamMain", false)
	#new_sub.team_id = data.get("teamId", "")
	#new_sub.unread_mention_count = data.get("userMentions", 0)
	#new_sub.unread_group_mention_count = data.get("groupMentions", 0)
	#new_sub.parent_room_id = data.get("prid", "")

	return new_sub


func _parse_subscription_list_data(datas: Array) -> Array[Subscription]:
	var subs: Array[Subscription] = []

	for data in datas:
		subs.push_back(_parse_subscription_data(data))

	return subs


func _on_server_id(server_id: String) -> void:
	print("Server ID: %s" % server_id)


func _on_connected(session_id: String) -> void:
	print("Connected successfully. Session ID: %s" % session_id)
	connected.emit(session_id)


func _on_ping() -> void:
	#print("pong")
	pass


func _on_collection_changed(collection: String, _id: String, data: Dictionary) -> void:
	print("Collection %s changed." % collection)
	match collection:
		"stream-room-messages":
			var room_id: String = data.get("eventName", "")
			assert(room_id)

			var messages_data: Array = data.get("args")
			var messages: Array[Message] = _parse_message_list_data(messages_data)

			room_messages_changed.emit(room_id, messages)

		"stream-notify-room":
			var notification_data: PackedStringArray = (data.get("eventName", "") as String).split("/")

			# We expect two fields: the room ID and the notification type. This
			# comes from the fact that the string is formatted as follows:
			# `room-id/notification-type`
			assert(notification_data.size() == 2)

			var room_id: String = notification_data[0] as String
			assert(room_id)

			var notification_type: String = notification_data[1] as String
			assert(notification_type)

			match notification_type:
				"deleteMessage":
					var arguments: Array = data.get("args", [])
					assert(arguments.size() == 1)

					var message_id: String = (arguments[0] as Dictionary).get("_id", "")
					assert(message_id)

					room_message_id_deleted.emit(room_id, message_id)

		"stream-notify-user":
			var notification_data: PackedStringArray = (data.get("eventName", "") as String).split("/")

			# We expect two fields: the user ID and the notification type. This
			# comes from the fact that the string is formatted as follows:
			# user-id/notification-type`
			assert(notification_data.size() == 2)

			var user_id: String = notification_data[0] as String
			assert(user_id)

			var notification_type: String = notification_data[1] as String
			assert(notification_type)

			match notification_type:
				"subscriptions-changed":
					var arguments: Array = data.get("args", [])

					var changed_subscriptions := ChangedSubscriptions.new()

					for i in arguments.size():
						match arguments[i]:
							"removed":
								var removed: Subscription = _parse_subscription_data(arguments[i + 1])
								if removed:
									print("removed %s." % removed.room_id)
									changed_subscriptions.removed.push_back(removed)

							"inserted":
								var inserted: Subscription = _parse_subscription_data(arguments[i + 1])
								if inserted:
									changed_subscriptions.inserted.push_back(inserted)

							"updated":
								var updated: Subscription = _parse_subscription_data(arguments[i + 1])
								if updated:
									changed_subscriptions.updated.push_back(updated)

					subscriptions_changed.emit(user_id, changed_subscriptions)


func _ready() -> void:
	_client = RocketChatRealtimeAPIClient.new()
	add_child(_client)

	_client.server_id.connect(_on_server_id)
	_client.connected.connect(_on_connected)
	_client.ping.connect(_on_ping)
	_client.collection_changed.connect(_on_collection_changed)
	_client.connect_to_url(instance_url.replace("https://", "wss://") + "/websocket")


## Authenticates with the server through a personal access token. Returns the
## id of the user who logged in, if failed, an empty [String] and emits [signal
## login_request_completed]. Can be also awaited directly.
func login_with_token(token: String) -> String:
	assert(token, "Token must not be empty.")

	var result = await _client.call_method_sync("login", [ { "resume": token } ])

	var return_id: String = ""

	if result is Dictionary:
		var result_dict = result as Dictionary
		var result_token: String  = result_dict.get("token", "")
		var result_id: String = result_dict.get("id", "")

		if result_token == token and not result_id.is_empty():
			return_id = result_id

	login_request_completed.emit(return_id)
	return return_id


## Gets the rooms associated with the user. If the user's anonymous and the
## server allows them, returns an [Array] of [RocketChat.Room]s, otherwise a
## [RocketChat.ChangedRoom] object.
func get_rooms(date: int):
	# NOTE: Looks like the API returns an array when not authenticated while it
	# returns a fancier "updated/removed" dictionary otherwise. That's pretty
	# annoying.
	var result = await _client.call_method_sync("rooms/get", [ { "$date" : date } ])

	if result is Array:
		# Anonymous list.
		var rooms: Array[Room] = _parse_room_list_data(result)
		return rooms
	elif result is Dictionary:
		var result_dict = result as Dictionary

		# User updated/removed list.
		var changed_room := ChangedRoom.new()
		changed_room.updated = _parse_room_list_data(result_dict.get("update"))
		changed_room.removed = _parse_room_list_data(result_dict.get("remove"))
		return changed_room


# FIXME: tf did [code]last_update_epoch[/code] do?
## Returns [code]message_amount[/code] messages from the room with ID [code]room_id[/code] and dated
## earlier than [code]newest_message_epoch[/code].
func get_room_history(room_id: String, newest_message_epoch: int, message_amount: int, last_update_epoch: int) -> Array[Message]:
	@warning_ignore("incompatible_ternary")
	var result := await _client.call_method_sync("loadHistory", [
		room_id,
		{ "$date": newest_message_epoch } if newest_message_epoch >= 0 else null,
		message_amount,
		{ "$date": last_update_epoch },
	]) as Dictionary

	assert(result)

	return _parse_message_list_data(result.get("messages"))


## Gets the subscriptions associated with the current user. [br]
## If [code]last_update_time[/code] is set to [code]-1[/code], it returns an
## [Array] with the complete list, otherwise a [RocketChat.ChangedSubscriptions]
## with the changes since then.
func get_subscriptions(last_update_time: int = -1):
	var args := []

	if last_update_time >= 0:
		args.push_back({"$date": last_update_time})

	var result = await _client.call_method_sync("subscriptions/get", args)
	assert(result)

	if result is Array:
		return _parse_subscription_list_data(result)
	elif result is Dictionary:
		var changed_subscriptions := ChangedSubscriptions.new()
		changed_subscriptions.updated = _parse_subscription_list_data(result.get("update"))
		changed_subscriptions.removed = _parse_subscription_list_data(result.get("remove"))

		return changed_subscriptions

	push_error("Invalid response.")

## Subscribes to the room messages stream for the given room ID. Any updates
## will be emitted through the [signal room_messages_changed] signal.
func subscribe_room_messages(room_id: String) -> String:
	var stream_args: Array = [
		room_id,
		{
			"useCollection": false,
			"args": [],
		},
	]

	return _client.subscribe_stream("stream-room-messages", stream_args)


## Sends a message to the room with ID [code]room_id[/code] with [code]text
## [/code] as its content.
func send_message(room_id: String, text: String) -> void:
	# FIXME: Generate better IDs.
	var id: String = str(randi())

	var request_data: Dictionary = {
		"_id": id,
		"rid": room_id,
		"msg": text,
	}

	_client.call_method_sync("sendMessage", [request_data])


## Subscribe to the [code]stream-notify-room[/code] stream, which reports
## whether a message gets deleted, a users starts/stops writing or they change
## their activity status. [br]
## See also: [enum StreamNotifyRoomEvent].
func subscribe_notify_room(room_id: String, event: StreamNotifyRoomEvent) -> String:
	var event_name: String = ""

	match event:
		StreamNotifyRoomEvent.DELETE_MESSAGE:
			event_name = "deleteMessage"

		StreamNotifyRoomEvent.TYPING:
			event_name = "typing"

		StreamNotifyRoomEvent.USER_ACTIVITY:
			event_name = "userActivity"

	assert(event_name)

	var stream_args: Array = [
		"%s/%s" % [room_id, event_name]
	]

	return _client.subscribe_stream("stream-notify-room", stream_args)


## Subscribe to the [code]stream-notify-user[/code] stream, which reports
## various user-related events such as notifications and subscriptions changes.
## [br] See also: [enum StreamNotifyUserevent]
func subscribe_notify_user(user_id: String, event: StreamNotifyUserEvent) -> String:
	var event_name: String = ""

	match event:
		StreamNotifyUserEvent.MESSAGE:
			event_name = "message"

		StreamNotifyUserEvent.OFF_THE_RECORD:
			event_name = "otr"

		StreamNotifyUserEvent.WEBRTC:
			event_name = "webrtc"

		StreamNotifyUserEvent.NOTIFICATION:
			event_name = "notification"

		StreamNotifyUserEvent.ROOMS_CHANGED:
			event_name = "rooms-changed"

		StreamNotifyUserEvent.SUBSCRIPTIONS_CHANGED:
			event_name = "subscriptions-changed"

	assert(event_name)

	var stream_args: Array = [
		"%s/%s" % [user_id, event_name]
	]

	return _client.subscribe_stream("stream-notify-user", stream_args)


## Marks the room with ID [code]room_id[/code] as read.
func mark_room_read(room_id: String) -> void:
	# WHAT.
	# This isn't documented anywhere and is invoked from the web client as a
	# REST method, although with a message format akin to the realtime API.
	# Oh God.
	_client.call_method_sync("readMessages", [room_id])
