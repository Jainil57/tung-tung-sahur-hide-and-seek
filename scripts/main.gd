extends Node
## Main menu / lobby. Starts a Game when the host presses Start.

const GameScript := preload("res://scripts/game.gd")

var menu: Control
var game: Node3D = null
var name_edit: LineEdit
var ip_edit: LineEdit
var status_lbl: Label
var list_lbl: Label
var ip_lbl: Label
var host_btn: Button
var join_btn: Button
var leave_btn: Button
var start_btn: Button
var monster_chk: CheckBox
var mic_chk: CheckBox
var sens: HSlider
var mic_bar: ProgressBar


func _ready() -> void:
	randomize()
	_build_menu()
	Net.lobby_changed.connect(_refresh)
	Net.game_started.connect(_on_game_started)
	Net.connection_failed.connect(func(): _status("Could not connect. Check the IP and that you're on the same Wi-Fi."))
	Net.server_gone.connect(func(): back_to_menu("The host left the game."))
	Net.connected_ok.connect(func(): _status("Connected! Waiting for the host to start..."))
	_refresh()
	_smoke_test()


func _process(_delta: float) -> void:
	if menu.visible:
		mic_bar.value = Mic.level
		mic_bar.modulate = Color(1, 0.3, 0.3) if Mic.level > Mic.threshold else Color(1, 1, 1)


func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(560, 0)
	center.add_child(v)

	var title := Label.new()
	title.text = "TUNG TUNG SAHUR 3D"
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.95, 0.6, 0.25))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "3D HIDE & SEEK  -  stay quiet, find the takjil, parry the bat, escape the house"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.text = "Player%d" % (randi() % 100)
	name_edit.max_length = 16
	v.add_child(name_edit)

	var solo_btn := Button.new()
	solo_btn.text = "PLAY SOLO  (vs AI Tung Tung)"
	solo_btn.pressed.connect(func(): Net.solo(name_edit.text))
	v.add_child(solo_btn)

	var hrow := HBoxContainer.new()
	v.add_child(hrow)
	host_btn = Button.new()
	host_btn.text = "Host Game"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host)
	hrow.add_child(host_btn)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "Host IP"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hrow.add_child(ip_edit)
	join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.pressed.connect(_on_join)
	hrow.add_child(join_btn)

	ip_lbl = Label.new()
	ip_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	v.add_child(ip_lbl)

	monster_chk = CheckBox.new()
	monster_chk.text = "Host plays as Tung Tung (otherwise Tung Tung is AI)"
	monster_chk.toggled.connect(func(on): Net.set_monster_player(on))
	v.add_child(monster_chk)

	mic_chk = CheckBox.new()
	mic_chk.text = "Use microphone (talking makes noise in the game!)"
	mic_chk.button_pressed = true
	mic_chk.toggled.connect(func(on): Mic.set_enabled(on))
	v.add_child(mic_chk)
	var mrow := HBoxContainer.new()
	v.add_child(mrow)
	var ml := Label.new()
	ml.text = "Mic level "
	mrow.add_child(ml)
	mic_bar = ProgressBar.new()
	mic_bar.max_value = 1.0
	mic_bar.show_percentage = false
	mic_bar.custom_minimum_size = Vector2(160, 16)
	mrow.add_child(mic_bar)
	var sl := Label.new()
	sl.text = "  Sensitivity "
	mrow.add_child(sl)
	sens = HSlider.new()
	sens.min_value = 0.03
	sens.max_value = 0.6
	sens.step = 0.01
	sens.value = Mic.threshold
	sens.custom_minimum_size = Vector2(140, 16)
	sens.tooltip_text = "Right = you must be LOUDER before Tung Tung hears you"
	sens.value_changed.connect(func(val): Mic.threshold = val)
	mrow.add_child(sens)
	var srow := HBoxContainer.new()
	v.add_child(srow)
	var msl := Label.new()
	msl.text = "Mouse sensitivity "
	srow.add_child(msl)
	var ms := HSlider.new()
	ms.min_value = 0.0005
	ms.max_value = 0.008
	ms.step = 0.0001
	ms.value = Net.mouse_sens
	ms.custom_minimum_size = Vector2(200, 16)
	ms.value_changed.connect(func(val): Net.mouse_sens = val)
	srow.add_child(ms)

	list_lbl = Label.new()
	list_lbl.custom_minimum_size = Vector2(0, 110)
	v.add_child(list_lbl)

	var brow := HBoxContainer.new()
	v.add_child(brow)
	start_btn = Button.new()
	start_btn.text = "START GAME"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_btn.pressed.connect(func(): Net.start_game())
	brow.add_child(start_btn)
	leave_btn = Button.new()
	leave_btn.text = "Leave"
	leave_btn.pressed.connect(func(): Net.leave(); _status(""))
	brow.add_child(leave_btn)

	status_lbl = Label.new()
	status_lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.4))
	status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(status_lbl)

	var help := Label.new()
	help.text = "Up to 5 survivors on the same Wi-Fi. Sprinting, vases, squeaky floors, gunshots and YOUR VOICE make noise.\n" + \
		"Crouch (Ctrl) to sneak. E picks things up / hides in wardrobes. F flashlight.\n" + \
		"When Tung Tung RAISES HIS BAT (tung tung tung!), right-click to PARRY with your sword - or shoot the bat/head\n" + \
		"with a flare pistol - to STUN him. Bear traps (G) stun him, decoy drums (Q) lure him away."
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	v.add_child(help)

	# Browsers can't host or join over Wi-Fi (no UDP), so the web version is solo only.
	if OS.has_feature("web"):
		for n in [hrow, ip_lbl, monster_chk, list_lbl, brow]:
			n.visible = false
		help.text = "Browser version = SOLO vs AI. Download the Windows version on itch.io for up to 5-player multiplayer!\n" + help.text.substr(help.text.find("\n") + 1)


func _status(t: String) -> void:
	status_lbl.text = t


func _on_host() -> void:
	var err := Net.host(name_edit.text)
	if err != OK:
		_status("Could not host (port %d busy?) error %d" % [Net.PORT, err])
		return
	_status("Hosting! Friends click Join with one of your IPs below.")


func _on_join() -> void:
	var err := Net.join(ip_edit.text.strip_edges(), name_edit.text)
	if err != OK:
		_status("Could not start connection, error %d" % err)
		return
	_status("Connecting to %s ..." % ip_edit.text)


func _refresh() -> void:
	var online := Net.is_online()
	var is_host := online and multiplayer.is_server()
	host_btn.disabled = online
	join_btn.disabled = online
	leave_btn.disabled = not online
	start_btn.visible = is_host
	monster_chk.disabled = not is_host
	monster_chk.set_pressed_no_signal(bool(Net.settings.get("monster_player", false)))
	if is_host:
		var ips: Array[String] = []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
				ips.append(a)
		ip_lbl.text = "Your IP (tell friends): " + (", ".join(ips) if ips.size() > 0 else "unknown") + "   port %d" % Net.PORT
	else:
		ip_lbl.text = ""
	if not online:
		list_lbl.text = "Not connected."
		return
	var t := "Players in lobby (%d):\n" % Net.players.size()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var role := "survivor"
		if id == 1 and Net.settings.get("monster_player", false):
			role = "TUNG TUNG"
		t += "  - %s%s  [%s]\n" % [Net.players[id]["name"], " (host)" if id == 1 else "", role]
	list_lbl.text = t


func _on_game_started(s: Dictionary) -> void:
	if game:
		remove_child(game)  # free the name "Game" right away so RPC paths match
		game.queue_free()
	menu.visible = false
	game = GameScript.new()
	game.name = "Game"
	add_child(game)
	game.start(s)


func back_to_menu(reason: String) -> void:
	if game:
		remove_child(game)
		game.queue_free()
		game = null
	menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	_status(reason)


# Automated tests: run Godot with  -- --smoke-solo  (or --smoke-host / --smoke-client)
#                  or  -- --screenshot=/path/to.png  for a rendered gameplay screenshot
func _smoke_test() -> void:
	var mode := ""
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke"):
			mode = a
		if a.begins_with("--screenshot="):
			shot = a.substr(13)
	if shot != "":
		_screenshot(shot)
		return
	if mode == "":
		return
	if mode == "--smoke-offline":  # the PLAY SOLO button (also what the browser version uses)
		Mic.set_enabled(false)
		Net.solo("Tester")
		await _wait(8.0)
		print("SMOKE offline: ", game.summary())
		game._srv("c_noise", game.monster.global_position + Vector3(6, 0, 0), 20.0)
		await _wait(3.0)
		print("SMOKE offline after noise: ", game.summary())
		var p0: Vector3 = game.house.pickups[0]["pos"]
		game.me().global_position = p0
		await _wait(0.2)
		game._srv("c_pickup", 0)
		await _wait(0.3)
		print("SMOKE offline pickup0 taken=%s inv=%s" % [str(game.pick_taken[0]), str(game.inv[1])])
		game.s_caught.rpc(1)
		await _wait(0.5)
		print("SMOKE offline caught: alive=%s over=%s" % [str(game.alive), str(game.over)])
		Net.leave()
		get_tree().quit()
		return
	if mode == "--smoke-solo" or mode == "--smoke-monster":
		Mic.set_enabled(false)
		Net.host("Tester")
		Net.set_monster_player(mode == "--smoke-monster")
		Net.start_game()
		await _wait(1.0)
		var map: RID = game.house.nav.get_navigation_map()
		var a: Vector3 = game.house.monster_spawn
		var b: Vector3 = game.house.cell_center(1, 33, 2)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, a, b, true)
		var endp: Vector3 = path[path.size() - 1] if path.size() > 0 else Vector3.ZERO
		print("SMOKE nav: path to upstairs points=%d end=%s (wanted %s) polys=%d" % [path.size(), str(endp.snapped(Vector3.ONE * 0.1)), str(b), game.house.nav.navigation_mesh.get_polygon_count()])
		await _wait(6.5)
		print("SMOKE awake: ", game.summary())
		if mode == "--smoke-monster":
			await _wait(3.0)
			print("SMOKE monster end: ", game.summary())
			Net.leave()
			get_tree().quit()
			return
		game._srv("c_noise", game.monster.global_position + Vector3(6, 0, 0), 20.0)
		await _wait(0.3)
		print("SMOKE after noise: ", game.summary(), " target=", game.monster.target)
		await _wait(3.0)
		print("SMOKE moving: ", game.summary())
		# ---- sword parry test
		var r1 := await _attack_test("sword")
		print("SMOKE parry(sword) result: state=%s immune=%.1f alive=%s" % [r1, game.monster.immune_t, str(game.alive)])
		await _wait(4.0)
		game.monster.immune_t = 0.0
		# ---- gun deflect test
		game.inv[1]["gun"] = true
		game.inv[1]["ammo"] = 3
		game.my_inv["gun"] = true
		game.my_inv["ammo"] = 3
		var r2 := await _attack_test("gun")
		print("SMOKE deflect(gun) result: state=%s alive=%s" % [r2, str(game.alive)])
		await _wait(4.0)
		# ---- immune test: parry while immune => block (no stun)
		var r3 := await _attack_test("sword")
		print("SMOKE parry-while-immune result: state=%s (expect recover/block)" % r3)
		await _wait(2.0)
		game.monster.immune_t = 0.0
		# ---- no parry => caught
		var r4 := await _attack_test("none")
		print("SMOKE no-parry result: state=%s alive=%s over=%s" % [r4, str(game.alive), str(game.over)])
		print("SMOKE end: ", game.summary())
		Net.leave()
		get_tree().quit()
	elif mode == "--smoke-host":
		Mic.set_enabled(false)
		Net.host("Host")
		await _wait(4.0)
		print("SMOKE lobby: ", Net.players)
		Net.start_game()
		await _wait(3.0)
		print("SMOKE host mid: ", game.summary())
		await _wait(4.5)
		# make Tung Tung attack the client; the client parries over the network
		var cid := -1
		for id in game.players:
			if id != 1:
				cid = id
		if cid != -1:
			var cp: Vector3 = game.players[cid].global_position
			game.monster.global_position = cp + Vector3(1.6, 0.1, 0)
			game.monster.chase_id = cid
			game.monster.attack_cd = 0.0
			game.monster.set_state("chase")
			await _wait(0.1)
			print("SMOKE host: monster attacking client, state=", game.monster.state)
			await _wait(1.3)
			print("SMOKE host: after client parry, state=%s immune=%.1f alive=%s" % [game.monster.state, game.monster.immune_t, str(game.alive)])
		await _wait(3.0)
		print("SMOKE host end: ", game.summary())
		Net.leave()
		get_tree().quit()
	elif mode == "--smoke-client":
		Mic.set_enabled(false)
		await _wait(0.5)
		Net.join("127.0.0.1", "Client")
		await _wait(5.5)
		if game == null:
			print("SMOKE client: NO GAME")
			Net.leave()
			get_tree().quit()
			return
		var me: Node3D = game.me()
		# walk to the first takjil and pick it up through the server
		var idx := -1
		for i in game.house.pickups.size():
			if game.house.pickups[i]["kind"] == "item":
				idx = i
				break
		me.global_position = game.house.pickups[idx]["pos"] + Vector3(0.6, 0.1, 0)
		await _wait(0.5)
		game._srv("c_pickup", idx)
		game._srv("c_parry")
		await _wait(1.0)
		print("SMOKE client mid: ", game.summary(), " my_pos=", me.global_position.snapped(Vector3.ONE * 0.1))
		# parry when we SEE the windup (from network snapshots), like a real player would
		var parried := false
		for i in 400:
			await get_tree().physics_frame
			if game.monster.state == "windup" and not parried:
				await _wait(0.35)
				game._parry()
				parried = true
				print("SMOKE client: saw windup -> parried")
			if parried and game.monster.state == "stun":
				print("SMOKE client: sees Tung Tung STUNNED")
				break
		await _wait(1.0)
		print("SMOKE client end: ", game.summary())
		Net.leave()
		get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## Puts Tung Tung right in front of the solo tester, makes him attack, and reacts.
func _attack_test(how: String) -> String:
	var me: Node3D = game.me()
	var mon: Node = game.monster
	var fwd := -me.global_transform.basis.z
	fwd.y = 0
	mon.global_position = me.global_position + fwd.normalized() * 1.8
	mon.chase_id = 1
	mon.attack_cd = 0.0
	mon.set_state("chase")
	for i in 120:
		await get_tree().physics_frame
		if mon.state == "windup":
			break
	print("SMOKE   attack started: state=%s" % mon.state)
	await _wait(mon.windup_time() - 0.25)
	if how == "sword":
		game._parry()
	elif how == "gun":
		me.weapon = 1
		var origin: Vector3 = me.global_position + Vector3(0, 1.6, 0)
		game._srv("c_shoot", origin, (mon.head_pos() - origin).normalized())
	await _wait(0.45)
	return mon.state


func _screenshot(path: String) -> void:
	Mic.set_enabled(false)
	Net.host("Raka")
	Net.start_game()
	await _wait(0.5)
	var h: Node3D = game.house
	var me: Node3D = game.me()
	var pose := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose="):
			pose = int(a.substr(7))
	var p_cell := Vector3i(0, 14, 5)
	var m_cell := Vector3i(0, 18, 3)
	if pose == 1:
		p_cell = Vector3i(0, 2, 8)
		m_cell = Vector3i(0, 13, 9)
	elif pose == 2:
		p_cell = Vector3i(1, 9, 9)
		m_cell = Vector3i(1, 19, 9)
	var pp: Vector3 = h.cell_center(p_cell.x, p_cell.y, p_cell.z) + Vector3(0, 0.1, 0)
	var mp: Vector3 = h.cell_center(m_cell.x, m_cell.y, m_cell.z) + Vector3(0, 0.1, 0)
	me.global_position = pp
	var to := mp - pp
	me.yaw = atan2(-to.x, -to.z)
	me.pitch = 0.1
	game.monster.global_position = mp
	game.monster.rotation.y = atan2(to.x, to.z)
	game.monster.freeze_pose = "windup"
	game.my_inv["gun"] = pose == 2
	me.weapon = 1 if pose == 2 else 0
	if pose == 1:  # a second (fake remote) survivor for the shot
		var buddy: CharacterBody3D = game.PlayerScript.new()
		buddy.setup(game, 99, "Dimas", Net.COLORS[1], false, pp + Vector3(2.2, 0.1, 1.0), 0.0)
		game.add_child(buddy)
		buddy.target_pos = pp + to.normalized() * 4.0 + Vector3(0, 0, 0.8)
		buddy.net_yaw = atan2(-to.x, -to.z) + 0.5
		buddy.weapon = 0
		buddy.parry_anim = 0.0
	await _wait(2.0)
	game._msg("", 0.0)
	await _wait(0.6)
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Saved screenshot to ", path)
	Net.leave()
	get_tree().quit()
