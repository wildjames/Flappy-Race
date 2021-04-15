extends Control


func _ready():
	Server.update_public_ip()
	# Automatically update the public ip text
	var _junk = Server.connect("public_ip_changed", self, "_on_Net_public_ip_changed")


remotesync func begin_game(new_seed):
	# Sync up the RNG seed for all players
	Globals.set_game_seed(new_seed)
	var _junk = get_tree().change_scene("res://scenes/World.tscn")


func _on_BGMusic_finished():
	pass #$BGMusic.play()


func _on_Net_public_ip_changed(new_ip):
	# Update IPs
	$Connecting/MyIP.text = "IP: " + new_ip
