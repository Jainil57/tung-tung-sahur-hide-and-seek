extends Node
## Lobby + connection handling (ENet, LAN). Host is the server AND can play.

signal lobby_changed
signal connection_failed
signal connected_ok
signal server_gone
signal peer_left(id: int)
signal game_started(settings: Dictionary)

const PORT := 7777
const MAX_CLIENTS := 5  # host + 5 others max

const COLORS := [
	Color(0.35, 0.8, 1.0), Color(1.0, 0.8, 0.2), Color(0.5, 1.0, 0.4),
	Color(1.0, 0.5, 0.85), Color(0.75, 0.6, 1.0), Color(1.0, 0.55, 0.3),
]

var players := {}  # peer id -> {"name": String, "color": Color}
var settings := {"monster_player": false}
var my_name := "Player"
var in_game := false
var mouse_sens := 0.0025


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func host(player_name: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	my_name = player_name
	players = {1: {"name": player_name, "color": COLORS[0]}}
	lobby_changed.emit()
	return OK


func join(ip: String, player_name: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	my_name = player_name
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	in_game = false
	lobby_changed.emit()


## Single player against the AI Tung Tung. Needs no network, so it also works in the browser.
func solo(player_name: String) -> void:
	leave()  # leaves an OfflineMultiplayerPeer: we are "the server" with id 1
	my_name = player_name
	players = {1: {"name": player_name, "color": COLORS[0]}}
	settings["monster_player"] = false
	in_game = true
	game_started.emit(settings.duplicate())


func set_monster_player(v: bool) -> void:
	if not multiplayer.is_server():
		return
	settings["monster_player"] = v
	_sync_lobby.rpc(players, settings)
	lobby_changed.emit()


func start_game() -> void:
	if not multiplayer.is_server():
		return
	in_game = true
	_start.rpc(settings.duplicate())


@rpc("authority", "call_local", "reliable")
func _start(s: Dictionary) -> void:
	in_game = true
	settings = s
	game_started.emit(s)


func _on_connected() -> void:
	_register.rpc_id(1, my_name)
	connected_ok.emit()


func _on_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_gone() -> void:
	leave()
	server_gone.emit()


func _on_peer_connected(_id: int) -> void:
	pass  # wait for _register


@rpc("any_peer", "reliable")
func _register(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_game or players.size() >= MAX_CLIENTS + 1:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	var used := []
	for p in players.values():
		used.append(p["color"])
	var col: Color = COLORS[players.size() % COLORS.size()]
	for c in COLORS:
		if not used.has(c):
			col = c
			break
	var n := player_name.strip_edges().substr(0, 16)
	if n == "":
		n = "Player %d" % (players.size() + 1)
	players[id] = {"name": n, "color": col}
	_sync_lobby.rpc(players, settings)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _sync_lobby(p: Dictionary, s: Dictionary) -> void:
	players = p
	settings = s
	lobby_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	if multiplayer.is_server():
		_sync_lobby_deferred.call_deferred()
	lobby_changed.emit()
	peer_left.emit(id)


func _sync_lobby_deferred() -> void:
	if is_online() and multiplayer.is_server():
		for id in players:
			if id != 1 and id in multiplayer.get_peers():
				_sync_lobby.rpc_id(id, players, settings)


func name_of(id: int) -> String:
	if players.has(id):
		return players[id]["name"]
	return "Someone"
