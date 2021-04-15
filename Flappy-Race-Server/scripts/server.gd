extends Node

const PORT = 31400
const MAX_PLAYERS = 8

var server = NetworkedMultiplayerENet.new()


func _ready():
	start_server()

func start_server():
	server.create_server(PORT, MAX_PLAYERS)
	get_tree().set_network_peer(server)

	var _result
	_result = get_tree().connect("network_peer_connected", self, "client_connected")
	_result = get_tree().connect("network_peer_disconnected", self, "client_disconnected")

func client_connected(player_id):
	print("Client connected! ID: %s" % str(player_id))

func client_disconnected(player_id):
	print("Client lost. ID: %s" % str(player_id))
