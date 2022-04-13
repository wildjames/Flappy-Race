extends CommonWorld


const INTERPOLATION_OFFSET = 100


# World state vars
var last_world_state := 0
var world_state_buffer := []


func _ready() -> void:
	Network.Client.send_client_ready()


func _physics_process(_delta: float) -> void:
	var render_time = Network.Client.client_clock - INTERPOLATION_OFFSET
	if world_state_buffer.size() > 1:
		# world_state_buffer[0] will always be the oldest received world_state
		while world_state_buffer.size() > 2 and render_time > world_state_buffer[2].T:
			world_state_buffer.remove(0)
		if world_state_buffer.size() > 2:
			# We have a future world state available - smooth movement!
			interpolate_world_state(render_time)
		elif render_time > world_state_buffer[1].T:
			# No future world_states available - guess where things will be
			extrapolate_world_state(render_time)


func interpolate_world_state(render_time: int) -> void:
	var interpolation_factor = float(render_time - world_state_buffer[1]["T"]) / float(world_state_buffer[2]["T"] - world_state_buffer[1]["T"])
	for player in world_state_buffer[2].keys():
		if str(player) == "T":
			# Ignore the included timestamp
			continue
		if player == multiplayer.get_network_unique_id():
			# Ignore the local player
			continue
		if not world_state_buffer[1].has(player):
			# A connecting player won't be available in past world_state yet
			continue
		if has_node(str(player)):
			# Use the position between past and future world_states to calculate
			# the current position
			var new_position = lerp(
				world_state_buffer[1][player]["P"],
				world_state_buffer[2][player]["P"],
				interpolation_factor
			)
			get_node(str(player)).move_player(new_position)
		# TODO this should only spawn players if they are present in a future
		# world state but sometimes they still seem to arrive after death
		# else:
		# 	spawn_player(player, world_state_buffer[2][player]["P"])


func extrapolate_world_state(render_time: int) -> void:
	var extrapolation_factor = float(render_time - world_state_buffer[0]["T"]) / float(world_state_buffer[1]["T"] - world_state_buffer[0]["T"]) - 1.00
	for player in world_state_buffer[1].keys():
		if str(player) == "T":
			# Ignore the included timestamp
			continue
		if player == multiplayer.get_network_unique_id():
			# Ignore the local player
			continue
		if not world_state_buffer[0].has(player):
			# A connecting player won't be available in past world_state yet
			continue
		if has_node(str(player)):
			var position_delta = (world_state_buffer[1][player]["P"] - world_state_buffer[0][player]["P"])
			var new_position = world_state_buffer[1][player]["P"] + (position_delta * extrapolation_factor)
			get_node(str(player)).move_player(new_position)


func update_world_state(world_state: Dictionary) -> void:
	if world_state["T"] > last_world_state:
		last_world_state = world_state["T"]
		world_state_buffer.append(world_state)


func start_game(game_seed: int, new_game_options: Dictionary, new_player_list: Dictionary) -> void:
	.start_game(game_seed, new_game_options, new_player_list)
	reset_camera()
	$UI.update_lives(game_options.lives)
	$UI.start_countdown()


func _on_UI_countdown_finished() -> void:
	var client_id = multiplayer.get_network_unique_id()
	if player_list[client_id].spectate == false:
		var player = player_list[client_id].body
		player.enable_movement = true
		# Give the player a jump at the start
		player.motion.y = -STARTING_JUMP
		player.enable_control()
	$MusicPlayer.play_random_track()
	$MainCamera.add_trauma(0.8)


func reset_camera() -> void:
	var client_id = multiplayer.get_network_unique_id()
	if player_list[client_id].spectate:
		switch_camera_to_leader()
		$UI.spectating = true
	else:
		var player = player_list[client_id].body
		$MainCamera.set_target(player)


func reset_game() -> void:
	Network.Client.send_start_game_request()


func spawn_player(player_id: int, spawn_position: Vector2) -> Node2D:
	var player = .spawn_player(player_id, spawn_position)
	if player_id == multiplayer.get_network_unique_id():
		# Only connect for the local player
		player.connect("coins_changed", self, "_on_Player_coins_changed")
	if Network.Client.is_singleplayer:
		# Player list isn't populated in singleplayer
		player.set_body_colour(Globals.player_colour)
	else:
		player.set_body_colour(player_list[player_id]["colour"])
		player.set_player_name(player_list[player_id]["name"])
	return player


func despawn_player(player_id: int) -> void:
	if not has_node(str(player_id)):
		# Player already despawned
		return
	.despawn_player(player_id)
	# If this is the local player update the camera and UI
	if player_id == multiplayer.get_network_unique_id():
		if spawned_players.size() > 0:
			$MainCamera.add_trauma(0.8)
			$UI.show_death()
			# Delay to see death animation
			yield(get_tree().create_timer(1), "timeout")
			switch_camera_to_leader()


func switch_camera_to_leader() -> void:
	var leader = get_lead_player()
	if leader:
		$MainCamera.set_target(leader)
	else:
		push_error("Unable to find lead player: %s" % [spawned_players])


func get_lead_player() -> CommonPlayer:
	var leader
	for player in spawned_players:
		if leader == null or player.position.x > leader.position.x:
			leader = player
	return leader


func _on_Player_death(player: CommonPlayer) -> void:
	if int(player.name) == multiplayer.get_network_unique_id():
		._on_Player_death(player)


func knockback_player(player_id: int) -> void:
	var player = player_list[player_id].body
	player.set_enable_movement(false)
	$MainCamera.add_trauma(0.8)
	.knockback_player(player_id)
	yield(get_tree().create_timer(1), "timeout")
	player.set_enable_movement(true)


func _on_Player_score_changed(player: CommonPlayer) -> void:
	# Only update the UI for the local player
	if int(player.name) == multiplayer.get_network_unique_id():
		$UI.update_score(player.score)
		._on_Player_score_changed(player)


func _on_Player_coins_changed(player: CommonPlayer) -> void:
	# Should only be connected for the local player
	$UI.update_coins(player.coins)
	$MainCamera.add_trauma(0.4)


func _on_UI_request_restart() -> void:
	reset_game()


func player_finished(player_id: int, place: int, time: float) -> void:
	# Only show the finished screen if this client finished
	if player_id == multiplayer.get_network_unique_id():
		$UI.show_finished(place, time)
		$MusicPlayer.stop()
		$FinishMusic.play()
		$FinishChime.play()
		$MainCamera.add_trauma(0.8)
		if spawned_players.size() > 0:
			switch_camera_to_leader()
