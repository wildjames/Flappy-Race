extends ColorRect


# This function is called when the join or host buttons are pushed.
# It should ONLY handle changing the screen for the user.
func show_connect_screen():
	# Reveal thyself
	show()

	$ConnectingText.text = "...Connecting to server..."

remote func update_connect_screen(num_players):
	Server.current_players = num_players
	$ConnectingText.text = "Waiting for players..."
	$NumPlayers.text = "Players: [%d/%d]" % [Server.current_players, Server.MAX_PLAYERS]
