extends Node

const RPC_PORT = 1909
const MAX_PLAYERS = 8

signal public_ip_changed(new_ip)

# TODO: Remove all references to this
var is_host = false


var net_id = null
var is_online = true
var current_players = 0
var public_ip = "127.0.0.1"


func _ready():
	update_public_ip()


func initialise_client(server_ip):
	# Start a client for communicating with the server, and connect to that server
	var peer = NetworkedMultiplayerENet.new()
	peer.create_client(server_ip, RPC_PORT)
	get_tree().set_network_peer(peer)

	peer.connect("connection_failed", self, "_on_connection_failed")
	peer.connect("connection_succeeded", self, "_on_connection_succeeded")

	is_online = true


func _on_connection_failed():
	print("Connection failed!")


func _on_connection_succeeded():
	print("Connection succeeded!")


func update_public_ip():
	var ip_lookup_api = "https://api.ipify.org"
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_http_request_completed")
	http_request.request(ip_lookup_api)


func _http_request_completed(_result, response_code, _headers, body):
	if response_code == 200:
		# Successful response
		public_ip = body.get_string_from_utf8()
	else:
		print("[NET] Received HTTP response code ", response_code, " when finding public IP!")
		public_ip = "localhost"
	emit_signal("public_ip_changed", public_ip)
