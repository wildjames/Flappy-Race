extends SceneHandler


class_name ServerNetwork


const SERVER_ID := 0


# IMPORTANT:
# This node is a Viewport with zero size intentionally in order to separate
# the client and server physics, so objects from the client and the server can't
# interact with eachother when self hosting.

var max_players := 0
var _host_player_id := 0 setget set_host
var player_state_collection := {}
var player_list := {}


func _ready() -> void:
	# As you can see, instead of calling get_tree().connect for network related
	# stuff we use mutltiplayer.connect . This way, IF (and only IF) the
	# MultiplayerAPI is customized, we use that instead of the global one.
	# This makes the custom MultiplayerAPI almost plug-n-play.
	assert(multiplayer.connect("network_peer_disconnected", self, "_peer_disconnected") == OK)
	assert(multiplayer.connect("network_peer_connected", self, "_peer_connected") == OK)

	# Register with the Network singleton so this node can be easily accessed
	Network.Server = self

	# Start automatically if this is a headless server
	if "--server" in OS.get_cmdline_args():
		start_server(Network.RPC_PORT, Network.MAX_PLAYERS)


func _exit_tree() -> void:
	multiplayer.disconnect("network_peer_disconnected", self, "_peer_disconnected")
	multiplayer.disconnect("network_peer_connected", self, "_peer_connected")


func set_host(new_host: int) -> void:
	_host_player_id = new_host
	Logger.print(self, "Player %s is now the host" % [_host_player_id])


func is_host(player_id: int) -> bool:
	return _host_player_id == player_id


func clear_host() -> void:
	_host_player_id = 0
	Logger.print(self, "Cleared host player")


func start_server(port: int, server_max_players: int) -> void:
	max_players = server_max_players
	var peer := NetworkedMultiplayerENet.new()
	assert(peer.create_server(port, max_players) == OK)
	# Same goes for things like:
	# get_tree().set_network_peer() -> multiplayer.set_network_peer()
	# Basically, anything networking related needs to be updated this way.
	# See the MultiplayerAPI docs for reference.
	multiplayer.set_network_peer(peer)
	Logger.print(self, "Server started - waiting for players")


func stop_server() -> void:
	clear_host()
	player_state_collection.clear()
	player_list.clear()
	multiplayer.network_peer.close_connection()
	multiplayer.set_network_peer(null)
	Logger.print(self, "Server stopped")


func _peer_connected(player_id: int) -> void:
	var num_players = multiplayer.get_network_connected_peers().size()
	Logger.print(self, "Player %s connected - %d/%d" %
			[player_id, num_players, max_players])
	if is_host(0):
		set_host(player_id)


func _peer_disconnected(player_id: int) -> void:
	Logger.print(self, "Player %s disconnected" % [player_id])
	if is_host(player_id):
		# Promote the next player to the host if any are still connected
		var peers = multiplayer.get_network_connected_peers()
		if peers.size() > 0:
			var new_host = peers[0]
			set_host(new_host)
		else:
			clear_host()
	send_despawn_player(player_id)


remote func receive_player_settings(player_name: String, player_colour: int) -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	Logger.print(self, "Got settings for player %s. Name: %s, Colour: %s" % [player_id, player_name, player_colour])
	player_list[player_id] = {
		"name": player_name,
		"colour": player_colour,
		"spectate": false,
	}
	send_player_list_update()


func send_player_list_update() -> void:
	rpc("receive_player_list_update", player_list)


remote func receive_player_colour_change(colour_choice: int) -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	player_list[player_id]["colour"] = colour_choice
	Logger.print(self, "Player %s chose colour %s " % [player_id, colour_choice])
	send_player_colour_update(player_id, colour_choice)


func send_player_colour_update(player_id: int, colour_choice: int) -> void:
	rpc("receiver_player_colour_update", player_id, colour_choice)


remote func receive_player_spectate_change(is_spectating: bool) -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	player_list[player_id]["spectate"] = is_spectating
	Logger.print(self, "Player %s set spectating to %s " % [player_id, is_spectating])
	send_player_spectate_update(player_id, is_spectating)


func send_player_spectate_update(player_id: int, is_spectating: bool) -> void:
	rpc("receiver_player_spectate_update", player_id, is_spectating)


func send_despawn_player(player_id: int) -> void:
	if player_state_collection.has(player_id):
		assert(player_state_collection.erase(player_id))
	rpc("receive_despawn_player", player_id)


remote func receive_clock_sync_request(client_time: int) -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	rpc_id(player_id, "receive_clock_sync_response", OS.get_system_time_msecs(), client_time)


remote func receive_latency_request(client_time: int) -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	rpc_id(player_id, "receive_latency_response", client_time)


remote func receive_client_ready() -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	$World.set_player_ready(player_id)


remote func receive_start_game_request() -> void:
	# Only the server or the host can start the game
	var player_id = multiplayer.get_rpc_sender_id()
	if player_id == SERVER_ID or is_host(player_id):
		if player_list.empty():
			Logger.print(self, "Cannot start game without any players!")
			return
		if is_everyone_spectating():
			Logger.print(self, "Cannot start game with just spectators!")
			return
		Logger.print(self, "Starting game!")
		send_load_world()
		change_scene("res://server/world/world.tscn")
	else:
		Logger.print(self, "Player %s tried to start the game but they're not the host!" %
				[player_id])


func is_everyone_spectating() -> bool:
	for player in player_list.values():
		if player.spectate == false:
			return false
	return true


func send_load_world() -> void:
	rpc("receive_load_world")


func send_game_started(game_seed: int) -> void:
	rpc("receive_game_started", game_seed, player_list)


remote func receive_player_state(player_state: Dictionary) -> void:
	var player_id = multiplayer.get_rpc_sender_id()
	if player_state_collection.has(player_id):
		# Check if the player_state is the latest and replace it if it's newer
		if player_state_collection[player_id]["T"] < player_state["T"]:
			player_state_collection[player_id] = player_state
	else:
		player_state_collection[player_id] = player_state


func send_world_state(world_state: Dictionary) -> void:
	rpc_unreliable("receive_world_state", world_state)
