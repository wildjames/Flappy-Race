extends Node2D

const Wall := preload("res://scenes/Wall.tscn")
const Player := preload("res://scenes/Player.tscn")
const high_score_fname := "user://highscore.save"

onready var Background := $Background
onready var HiScore := $UI/HighScore
onready var Score := $UI/Score
onready var WallSpawnTimer := $WallSpawnTimer

# Public vars
var height_range := 100
var gap_range_min := 130
var gap_range_max := 250
var wall_spawn_time := 2.5
var start_wall_speed := 4.0
var wall_speed := start_wall_speed
var speed_up := 0.1
var scroll_speed := 0.1
var bob_speed := 1.0
var bob_amplitude := 0.01

func _ready():
	# Setup gubbins
	Globals.high_score = load_high_score()
	HiScore.text = str(Globals.high_score)


	# Set the wallpaper motion
	Background.material.set_shader_param('scroll_speed', scroll_speed)
	Background.material.set_shader_param('bob_speed', bob_speed)
	Background.material.set_shader_param('bob_amplitude', bob_amplitude)

	if (not Net.is_online) or (Net.is_host):
		WallSpawnTimer.wait_time = wall_spawn_time
		WallSpawnTimer.start()

	# Connect the player connection signals
	var _result
	_result = get_tree().connect("network_peer_connected", self, "player_connected")
	_result = get_tree().connect("network_peer_disconnected", self, "player_disconnected")

	# Give all the players an ID
	Net.set_ids()
	# and create a player sprite for each.
	create_players()
	# Then, create my own lil guy
	$Player.initialise(Net.net_id)


#### Online mode functions
func player_connected(id):
	# WIP
	print("Player %s connected" % id)
	print("I will do nothing about it.")


func player_disconnected(id):
	var p = get_player(id)
	remove_child(p)


func create_players():
	for id in Net.peer_ids:
		create_player(id)


func create_player(id):
	var p = Player.instance()
	p.add_to_group("Players")
	add_child(p)
	p.initialise(id)


func get_player(id):
	for child in self.get_children():
		if child.name == str(id):
			return child

	return null


remotesync func reset_game():
	print("RESETTING GAME\n\n")
	# This works well enough for one player, but we actually want a less nuclear approach
	var _ok = get_tree().reload_current_scene()


#### Wall functions
func _on_WallSpawner_timeout():
	WallSpawnTimer.wait_time = wall_spawn_time * float(start_wall_speed) / wall_speed
	if Net.is_online and Net.is_host:
		rpc("increase_difficulty")
	else:
		increase_difficulty()
	create_wall()


func create_wall():
	var inst = Wall.instance()
	# Use the game RNG to keep the levels deterministic
	var height = Globals.game_rng.randf_range(-height_range, height_range)
	var gap = Globals.game_rng.randf_range(gap_range_min, gap_range_max)
	#print("Spawning wall - height: ", height, " - gap: ", gap)
	inst.position = Vector2(get_viewport().size.x / 2 + 64, height)
	inst.gap = gap
	inst.speed = wall_speed

	call_deferred("add_child", inst)

	if Net.is_online and Net.is_host:
		rpc("spawn_wall", inst.position, inst.gap, inst.speed)


remote func spawn_wall(pos, gap, speed):
	var inst = Wall.instance()
	inst.position = pos
	inst.gap = gap
	inst.speed = speed

	call_deferred("add_child", inst)


remotesync func increase_difficulty():
	print("Speed up")
	wall_speed += speed_up
	for wall in get_tree().get_nodes_in_group("walls"):
		wall.speed = wall_speed


#### Player helper functions
func _on_Player_death(player):
	print("Player %s died" % player.name)
	# See if we have a new PB
	if player.score > Globals.high_score:
		Globals.high_score = player.score
		save_high_score()
		HiScore.text = str(Globals.high_score)

	# If I'm not the host, inform the host I've died
	if Net.is_online and not Net.is_host:
		rpc_id(0, "player_died", player.name)

	# If I'm not online, restart the game
	if not Net.is_online:
		reset_game()
	# If I am the host, check if all players are dead
	elif Net.is_host:
		are_all_players_dead()
	# And if I'm not the host, tell the host to check.
	else:
		rpc_id(0, "are_all_players_dead")


remote func player_died(id):
	for node in get_tree().get_nodes_in_group("Players"):
		if node.name == id:
			node.is_alive = false


remote func are_all_players_dead():
	# Function should only be entered if the player is online
	# Decide if the game must restart
	var num_players_alive: int = 0

	for node in get_tree().get_nodes_in_group("Players"):
		num_players_alive += int(node.is_alive)

	if num_players_alive == 0:
		if Net.is_host:
			rpc("reset_game")
		else:
			reset_game()


func _on_Player_score_point(player):
	# Actual incrimenting is handled on the player object
	Score.text = str(player.score)


#### World functions
func load_high_score():
	var save_file = File.new()
	if not save_file.file_exists(high_score_fname):
		return 0

	save_file.open(high_score_fname, File.READ)
	var data = parse_json(save_file.get_as_text())
	save_file.close()

	var high_score = int(data['highscore'])

	return high_score


func save_high_score():
	var save_file = File.new()
	save_file.open(high_score_fname, File.WRITE)

	# We will store as a JSON object. Overkill for a single integer, but should
	# be easy to scale out.
	var store_dict = {"highscore": Globals.high_score}

	save_file.store_line(to_json(store_dict))
	save_file.close()


func _on_BGMusic_finished():
	$BGMusic.play()
