extends MenuControl


var lobby_scene := "res://client/menu/lobby/lobby.tscn"


onready var player_list = $Setup/PlayerList
onready var info_message = $Setup/InfoMessage


func _ready() -> void:
	var result = Network.Client.connect("player_list_changed", self, "populate_players")
	assert(result == OK)

	info_message.hide()

	if Network.Client.is_server_connected():
		# Already connected to the server, so set all of the values
		if not Network.Client.player_list.empty():
			populate_players(Network.Client.player_list)
			var player_id = multiplayer.get_network_unique_id()
			if Network.Client.player_list[player_id].spectate == true:
				$Setup/SpectateButton.set_pressed_no_signal(true)
				$Setup/SpectatorText.show()
				$Setup/PlayerOptions.hide()


func populate_players(new_player_list: Dictionary) -> void:
	Logger.print(self, "Got player list: %s" % [new_player_list])
	player_list.clear_players()
	for player_id in new_player_list:
		var colour_choice = new_player_list[player_id]["colour"]
		var player_name = new_player_list[player_id]["name"]
		var spectating = new_player_list[player_id]["spectate"]
		player_list.add_player(player_id, player_name, colour_choice, spectating)


func update_player_colour(player_id: int, colour_choice: int) -> void:
	player_list.update_player_colour(player_id, colour_choice)


func update_player_spectating(player_id: int, is_spectating: bool) -> void:
	player_list.update_player_spectating(player_id, is_spectating)


func _on_BackButton_pressed() -> void:
	change_menu(lobby_scene)


func _on_SpectateButton_toggled(button_pressed: bool) -> void:
	Network.Client.send_player_spectate_change(button_pressed)
	$Setup/SpectatorText.visible = button_pressed
	$Setup/PlayerOptions.visible = not button_pressed


func show_message(message: String) -> void:
	info_message.text = message
	var animation = info_message.get_node("AnimationPlayer")
	animation.stop()
	animation.play("show")
