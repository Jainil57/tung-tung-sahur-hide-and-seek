extends Node3D
## One round of the game (3D). The server (host) is authoritative for the monster,
## items, traps, parries, gunshots, catches and win/lose. Clients send their
## position + noise + actions.

const PlayerScript := preload("res://scripts/player.gd")
const MonsterScript := preload("res://scripts/monster.gd")
const HouseScript := preload("res://scripts/house.gd")
const HudScript := preload("res://scripts/hud.gd")

const ITEMS_NEEDED := 8
const PARRY_WINDOW := 0.32     # seconds the sword block is "up"
const PARRY_LAG := 0.1         # extra server-side grace for network delay
const PARRY_CD := 0.9
const PARRY_FAIL_LOCK := 1.6   # extra lockout after a whiffed parry
const VULN_TIME := 1.5         # slowed + can't parry after a whiff
const GUN_AMMO := 5
const GUN_RANGE := 40.0
const SHOT_CD := 0.5
# noise radii (metres)
const N_WALK := 4.5
const N_SPRINT := 14.0
const N_LAND := 8.0
const N_SQUEAK := 12.0
const N_VASE := 26.0
const N_PICKUP := 5.0
const N_SHOT := 35.0
const N_DECOY := 45.0
const N_SWORD := 3.5
const N_MIC_MIN := 10.0
const N_MIC_MAX := 40.0
const N_MAX := 45.0

var settings := {}
var monster_player := false
var local_id := 1
var house: Node3D
var players := {}  # id -> Player node
var alive := {}    # id -> bool
var inv := {}      # server truth: id -> {"trap","decoy","gun","ammo"}
var my_inv := {"trap": 0, "decoy": 0, "gun": false, "ammo": 0}
var pick_taken: Array[bool] = []
var vase_broken: Array[bool] = []
var traps := {}    # tid -> {"pos": Vector3, "node": Node3D}
var next_tid := 0
var decoys := []   # server: [{"pos": Vector3, "t": float}]
var items_needed := ITEMS_NEEDED
var items_got := 0
var elapsed := 0.0
var over := false
var exit_open := false
var escape_sent := false
var call_announced := false
var tele_announced := false
var dark_announced := false

var monster: CharacterBody3D
var hud: CanvasLayer
var mon_cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := -0.25
var paused := false

var parry_until := {}    # server: id -> elapsed time
var parry_pending := {}  # server: id -> true
var parry_cd_t := 0.0
var shot_cd_t := 0.0
var dark_t := 0.0
var reveal_t := 0.0
var shake := 0.0
var flash_red := 0.0
var snap_t := 0.0
var send_t := 0.0
var walk_noise_t := 0.0
var mic_noise_t := 0.0
var pending := {}
var last_cell := Vector3i(-1, -1, -1)
var current_noise := 0.0
var was_on_floor := true
var hide_idx := -1
var focus := {}
var ab_ready := PackedFloat32Array([0, 45, 70, 90])
var ab_stamp := 0.0
var mon_flags := 0
var reveal_marks: Array[Label3D] = []
var fx_root: Node3D


# ------------------------------------------------------------------ setup
func start(s: Dictionary) -> void:
	settings = s
	monster_player = bool(s.get("monster_player", false))
	local_id = multiplayer.get_unique_id()
	house = HouseScript.new()
	house.name = "House"
	add_child(house)
	house.build()
	if multiplayer.is_server():
		house.bake_nav()
	fx_root = Node3D.new()
	fx_root.name = "FX"
	add_child(fx_root)
	for p in house.pickups:
		pick_taken.append(false)
	for v in house.vases:
		vase_broken.append(false)
	var n_items := 0
	for p in house.pickups:
		if p["kind"] == "item":
			n_items += 1
	items_needed = mini(ITEMS_NEEDED, n_items)
	var ids: Array = Net.players.keys()
	ids.sort()
	var si := 0
	var center := Vector3(house.W * house.C * 0.5, 0, house.H * house.C * 0.5)
	for id in ids:
		if monster_player and id == 1:
			continue
		var info: Dictionary = Net.players[id]
		var sp: Vector3 = house.spawn_points[si % house.spawn_points.size()]
		var to := center - sp
		var p: CharacterBody3D = PlayerScript.new()
		p.setup(self, id, info["name"], info["color"], id == local_id, sp + Vector3(0, 0.1, 0), atan2(-to.x, -to.z))
		si += 1
		add_child(p)
		players[id] = p
		alive[id] = true
		inv[id] = {"trap": 0, "decoy": 0, "gun": false, "ammo": 0}
	monster = MonsterScript.new()
	monster.setup(self, house.monster_spawn + Vector3(0, 0.1, 0), monster_player)
	add_child(monster)
	if is_monster():
		mon_cam = Camera3D.new()
		mon_cam.fov = 75.0
		add_child(mon_cam)
		mon_cam.make_current()
		house.env.ambient_light_energy = 1.4  # Tung Tung sees in the dark
		house.env.fog_density = 0.012
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)
	Net.peer_left.connect(_on_peer_left)
	capture_mouse()
	if is_monster():
		_msg("YOU ARE TUNG TUNG SAHUR!\nListen for noise and catch them all.", 5.0)
	else:
		_msg("Find %d takjil and escape through the front door.\nStay QUIET. Tung Tung wakes up in a few seconds..." % items_needed, 6.0)


func is_monster() -> bool:
	return monster_player and local_id == 1


func me() -> Node3D:
	return players.get(local_id)


func mouse_free() -> bool:
	return paused or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless"


func capture_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func ability_ready_in(k: String) -> float:
	if multiplayer.is_server():
		return monster.ready_in(k)
	var i: int = MonsterScript.ABILITY_ORDER.find(k)
	return maxf(0.0, ab_ready[i] - (elapsed - ab_stamp))


func parry_cooldown_left() -> float:
	return parry_cd_t


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	if not over:
		elapsed += delta
		_local_logic(delta)
		if multiplayer.is_server():
			_server_logic(delta)
	parry_cd_t = maxf(0.0, parry_cd_t - delta)
	shot_cd_t = maxf(0.0, shot_cd_t - delta)
	reveal_t = maxf(0.0, reveal_t - delta)
	dark_t = maxf(0.0, dark_t - delta)
	shake = maxf(0.0, shake - delta * 3.0)
	flash_red = maxf(0.0, flash_red - delta * 1.5)


func _process(delta: float) -> void:
	_update_lights(delta)
	_update_cameras(delta)
	for i in house.pickups.size():
		var n: Node3D = house.pickups[i]["node"]
		var sp := n.get_node_or_null("Spin")
		if sp:
			sp.rotation.y += delta * 1.5
			sp.position.y = (0.55 if house.pickups[i]["kind"] == "item" else 1.0) + sin(elapsed * 2.0 + i) * 0.05
	for m in reveal_marks:
		m.visible = reveal_t > 0.0
	if reveal_t > 0.0 and is_monster():
		var k := 0
		for id in players:
			if alive.get(id, false) and k < reveal_marks.size():
				reveal_marks[k].global_position = players[id].global_position + Vector3(0, 2.3, 0)
				reveal_marks[k].visible = true
				k += 1
		for j in range(k, reveal_marks.size()):
			reveal_marks[j].visible = false
	if hud:
		hud.update(delta)


func _update_cameras(_delta: float) -> void:
	var cam: Camera3D = mon_cam
	if is_monster() and monster:
		var pivot := monster.global_position + Vector3(0, 2.5, 0)
		var back := Basis(Vector3.UP, cam_yaw) * Basis(Vector3.RIGHT, cam_pitch) * Vector3(0.6, 0.3, 3.4)
		var want := pivot + back
		var q := PhysicsRayQueryParameters3D.create(pivot, want, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			want = hit["position"] + (pivot - want).normalized() * 0.3
		mon_cam.global_position = want
		mon_cam.global_rotation = Vector3(cam_pitch, cam_yaw, 0)
	elif me():
		cam = me().cam
	if cam and shake > 0.0:
		cam.h_offset = randf_range(-1, 1) * shake * 0.05
		cam.v_offset = randf_range(-1, 1) * shake * 0.05
	elif cam:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	if mon_cam == null and me() and me().cam:
		me().cam.current = true


func _update_lights(_delta: float) -> void:
	var near := 99.0
	var m := me()
	if m and monster:
		near = m.global_position.distance_to(monster.global_position)
	for l in house.lamps:
		var k := 1.0
		if dark_t > 0.0:
			var since: float = MonsterScript.DARK_TIME - dark_t
			k = (1.0 if randf() < 0.5 else 0.1) if since < 1.0 else 0.0
			if dark_t < 0.8:
				k = 1.0 if randf() < 0.5 else 0.0
		elif l["flick"] and randf() < 0.06:
			k = 0.3
		elif monster and l["light"].global_position.distance_to(monster.global_position) < 6.0 and randf() < 0.15:
			k = 0.2  # lights stutter when Tung Tung walks by
		l["light"].light_energy = l["base"] * k
		l["mat"].emission_energy_multiplier = 0.2 + 3.0 * k
	house.dark_k = 0.0 if dark_t > 0.0 else 1.0
	if m:
		var e := 2.4
		if dark_t > 0.0 and randf() < 0.25:
			e = randf_range(0.0, 1.2)
		elif near < 7.0 and randf() < 0.1:
			e = 0.6
		m.flash.light_energy = e
	for id in players:
		var p: Node3D = players[id]
		if not p.is_local:
			p.flash.light_energy = 2.2 if dark_t <= 0.0 or randf() > 0.3 else 0.3


func _ring(pos: Vector3, r: float, col := Color(0.6, 0.85, 1.0), dur := 0.7) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col, 0.7)
	mat.no_depth_test = true
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx_root.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.15, 0)
	mi.scale = Vector3(0.1, 0.02, 0.1)
	var rr := minf(r, 10.0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(rr, 0.02 * rr, rr), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


func _mark(pos: Vector3, txt: String, col: Color, dur := 1.5) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = 96
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = col
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fx_root.add_child(l)
	l.global_position = pos
	if dur > 0.0:
		var tw := l.create_tween()
		tw.tween_property(l, "modulate:a", 0.0, dur)
		tw.tween_callback(l.queue_free)
	return l


func _make_noise(pos: Vector3, r: float, show := true) -> void:
	current_noise = maxf(current_noise, r)
	if show:
		_ring(pos, r)
	_srv("c_noise", pos, r)


func _srv(m: String, a = null, b = null) -> void:
	if multiplayer.is_server():
		if b != null: call(m, a, b)
		elif a != null: call(m, a)
		else: call(m)
	else:
		if b != null: rpc_id(1, m, a, b)
		elif a != null: rpc_id(1, m, a)
		else: rpc_id(1, m)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return 1 if s == 0 else s


func _msg(t: String, dur := 3.0) -> void:
	if hud:
		hud.msg(t, dur)


# ------------------------------------------------------------------ local player
func _local_logic(delta: float) -> void:
	current_noise = maxf(0.0, current_noise - delta * 15.0)
	var m := me()
	if m == null:
		return
	send_t -= delta
	if send_t <= 0.0 and not multiplayer.is_server():
		send_t = 0.05
		c_state.rpc_id(1, m.global_position, m.yaw, m.pitch, m.mode, m.net_flags())
	if not alive.get(local_id, false):
		return
	# microphone: talk / shout in real life = noise in game (muffled inside a wardrobe)
	mic_noise_t -= delta
	if Mic.enabled and Mic.level > Mic.threshold and mic_noise_t <= 0.0:
		var k := clampf((Mic.level - Mic.threshold) / maxf(0.01, 1.0 - Mic.threshold) * 1.5, 0.0, 1.0)
		var r := lerpf(N_MIC_MIN, N_MIC_MAX, k) * (0.5 if m.hidden else 1.0)
		_make_noise(m.global_position, r)
		mic_noise_t = 0.3
	_update_focus()
	if m.hidden:
		return
	# footsteps: sprint is loud, walking is quiet, sneaking is silent
	var hs := Vector2(m.velocity.x, m.velocity.z).length()
	walk_noise_t -= delta
	if hs > 0.8 and m.is_on_floor() and walk_noise_t <= 0.0:
		if m.mode == 2:
			_make_noise(m.global_position, N_SPRINT)
			Sfx.play("step", -4.0, randf_range(0.9, 1.1))
			walk_noise_t = 0.32
		elif m.mode == 0:
			_make_noise(m.global_position, N_WALK, false)
			Sfx.play("step", -14.0, randf_range(0.9, 1.1))
			walk_noise_t = 0.5
	if m.is_on_floor() and not was_on_floor and m.fall_speed > 4.0:
		_make_noise(m.global_position, N_LAND)
		Sfx.play("step", 0.0, 0.7)
	was_on_floor = m.is_on_floor()
	# squeaky floorboards
	var cell: Vector3i = house.cell_of(m.global_position)
	if cell != last_cell:
		last_cell = cell
		if house.squeaks.has(cell) and m.mode != 1:
			Sfx.play_at("squeak", m.global_position, self)
			_make_noise(m.global_position, N_SQUEAK)
	# knocking over vases (sneak past them carefully!)
	for i in house.vases.size():
		if vase_broken[i] or pending.has("v%d" % i) or m.mode == 1:
			continue
		var vp: Vector3 = house.vases[i]["pos"]
		if absf(vp.y - m.global_position.y) < 1.0 and Vector2(vp.x - m.global_position.x, vp.z - m.global_position.z).length() < 0.75:
			pending["v%d" % i] = true
			_srv("c_vase", i)
	if exit_open and not escape_sent:
		var ep: Vector3 = house.exit_pos
		if m.global_position.distance_to(ep) < 2.2 or m.global_position.z > house.H * house.C + 0.4:
			escape_sent = true
			_srv("c_escape")


func _update_focus() -> void:
	focus = {}
	var m := me()
	if m == null or not alive.get(local_id, false):
		return
	if m.hidden:
		focus = {"type": "unhide", "text": "[E] Leave the wardrobe"}
		return
	var best := 1.9
	var pos: Vector3 = m.global_position
	for i in house.pickups.size():
		if pick_taken[i] or pending.has("p%d" % i):
			continue
		var pp: Vector3 = house.pickups[i]["pos"]
		var d := Vector2(pp.x - pos.x, pp.z - pos.z).length()
		if absf(pp.y - pos.y) < 1.2 and d < best:
			best = d
			var names := {"item": "takjil", "trap": "bear trap", "decoy": "decoy drum", "gun": "flare pistol"}
			focus = {"type": "pickup", "i": i, "text": "[E] Pick up %s" % names[house.pickups[i]["kind"]]}
	if focus.is_empty():
		for j in house.hides.size():
			var hp: Vector3 = house.hides[j]["out"]
			var d := Vector2(hp.x - pos.x, hp.z - pos.z).length()
			if absf(hp.y - pos.y) < 1.2 and d < 1.0 and not _hide_taken(j):
				focus = {"type": "hide", "i": j, "text": "[E] Hide in the wardrobe"}
				break


func _hide_taken(j: int) -> bool:
	var hp: Vector3 = house.hides[j]["pos"]
	for id in players:
		if id != local_id and players[id].hidden and players[id].global_position.distance_to(hp) < 0.6:
			return true
	return false


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
		if is_monster():
			cam_yaw -= e.relative.x * Net.mouse_sens
			cam_pitch = clampf(cam_pitch - e.relative.y * Net.mouse_sens, -1.2, 0.6)
		elif me():
			me().look(e.relative)
		return
	if e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if not over and not paused:
				capture_mouse()
			return
		if over or paused:
			return
		match e.button_index:
			MOUSE_BUTTON_LEFT: _primary()
			MOUSE_BUTTON_RIGHT: _secondary()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN: _switch_weapon(-1)
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k: Key = e.physical_keycode
	if k == KEY_ESCAPE:
		set_paused(not paused)
		return
	if k == KEY_H:
		hud.toggle_help()
		return
	if over or paused:
		return
	if is_monster():
		match k:
			KEY_Q: monster.use_ability("dash")
			KEY_E: monster.use_ability("call")
			KEY_R: monster.use_ability("tele")
			KEY_X: monster.use_ability("dark")
		return
	var m := me()
	if m == null:
		return
	if not alive.get(local_id, false):
		return
	match k:
		KEY_F:
			m.flashlight_on = not m.flashlight_on
			Sfx.play("click", -6.0)
		KEY_E:
			_interact()
		KEY_1:
			_switch_weapon(0)
		KEY_2:
			_switch_weapon(1)
		KEY_G:
			if my_inv["trap"] > 0 and not m.hidden:
				my_inv["trap"] -= 1
				_srv("c_use", "trap", m.global_position)
				_msg("Bear trap placed. If Tung Tung steps on it he's stunned.", 2.5)
		KEY_Q:
			if my_inv["decoy"] > 0 and not m.hidden:
				my_inv["decoy"] -= 1
				_srv("c_use", "decoy", _throw_point())
				Sfx.play("whoosh")
				_msg("Decoy drum thrown! It will boom in 2.5s.", 2.0)


func set_paused(v: bool) -> void:
	paused = v
	hud.show_pause(v)
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		capture_mouse()


func _throw_point() -> Vector3:
	var m := me()
	var from: Vector3 = m.cam.global_position
	var dir: Vector3 = -m.cam.global_transform.basis.z
	var to := from + dir * 8.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
	var p: Vector3 = to if hit.is_empty() else hit["position"] - dir * 0.4
	var down := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - Vector3(0, 8, 0), 1))
	return p if down.is_empty() else down["position"]


func _switch_weapon(w: int) -> void:
	var m := me()
	if m == null:
		return
	if w == -1:
		w = 1 - m.weapon
	if w == 1 and not my_inv["gun"]:
		_msg("No flare pistol yet - find one in the house.", 1.5)
		return
	m.weapon = w
	Sfx.play("click", -8.0, 0.8)


func _primary() -> void:
	if is_monster():
		monster.want_attack = true
		return
	var m := me()
	if m == null:
		return
	if not alive.get(local_id, false):
		m.spectate_next()
		return
	if m.hidden:
		return
	if m.weapon == 1 and my_inv["gun"]:
		_shoot()
	else:
		_parry()


func _secondary() -> void:
	if is_monster():
		return
	var m := me()
	if m == null:
		return
	if not alive.get(local_id, false):
		m.spectate_id = -1
		return
	if m.hidden:
		return
	_parry()


func _parry() -> void:
	var m := me()
	if parry_cd_t > 0.0 or m.vulnerable_t > 0.0:
		return
	parry_cd_t = PARRY_CD
	m.play_parry()
	Sfx.play("whoosh", -2.0, randf_range(0.9, 1.2))
	_make_noise(m.global_position, N_SWORD, false)
	_srv("c_parry")


func _shoot() -> void:
	var m := me()
	if shot_cd_t > 0.0:
		return
	if my_inv["ammo"] <= 0:
		Sfx.play("click")
		_msg("Out of flares!", 1.2)
		return
	shot_cd_t = SHOT_CD
	my_inv["ammo"] -= 1
	m.play_recoil()
	Sfx.play("shot", 2.0)
	shake = maxf(shake, 0.6)
	var origin: Vector3 = m.cam.global_position
	var dir: Vector3 = -m.cam.global_transform.basis.z
	current_noise = N_SHOT
	_srv("c_shoot", origin, dir)


func _interact() -> void:
	var m := me()
	if focus.is_empty():
		return
	match focus["type"]:
		"pickup":
			var i: int = focus["i"]
			pending["p%d" % i] = true
			_srv("c_pickup", i)
		"hide":
			hide_idx = focus["i"]
			m.enter_hide(house.hides[hide_idx])
			Sfx.play("door", -12.0, 1.6)
			_msg("Hiding... Tung Tung can't see you in here (but he can still HEAR you).", 3.0)
		"unhide":
			if hide_idx >= 0:
				m.exit_hide(house.hides[hide_idx])
			hide_idx = -1
			Sfx.play("door", -12.0, 1.4)
			_make_noise(m.global_position, N_WALK)


# ------------------------------------------------------------------ server
func _server_logic(delta: float) -> void:
	snap_t -= delta
	if snap_t <= 0.0 and elapsed > 0.5:
		snap_t = 0.05
		var ids := PackedInt32Array()
		var poss := PackedVector3Array()
		var rots := PackedVector2Array()
		var modes := PackedByteArray()
		var flags := PackedByteArray()
		for id in players:
			var p: Node3D = players[id]
			ids.append(id)
			poss.append(p.global_position)
			if p.is_local:
				rots.append(Vector2(p.yaw, p.pitch))
				flags.append(p.net_flags())
			else:
				rots.append(Vector2(p.net_yaw, p.net_pitch))
				flags.append(p.net_flags())
			modes.append(p.mode)
		var ab := PackedFloat32Array()
		for k in MonsterScript.ABILITY_ORDER:
			ab.append(monster.ready_in(k))
		s_snap.rpc(ids, poss, rots, modes, flags, monster.global_position, monster.rotation.y,
			MonsterScript.STATES.find(monster.state), monster.net_flags(), elapsed, ab)
	if not call_announced and elapsed >= MonsterScript.UNLOCK["call"]:
		call_announced = true
		fx("unlock_call", Vector3.ZERO)
	if not dark_announced and elapsed >= MonsterScript.UNLOCK["dark"]:
		dark_announced = true
		fx("unlock_dark", Vector3.ZERO)
	if not tele_announced and elapsed >= MonsterScript.UNLOCK["tele"]:
		tele_announced = true
		fx("unlock_tele", Vector3.ZERO)
	for d in decoys.duplicate():
		d["t"] -= delta
		if d["t"] <= 0.0:
			decoys.erase(d)
			server_noise(d["pos"], N_DECOY)
			fx("drum", d["pos"])
	# whiffed parries
	for id in parry_pending.keys():
		if elapsed > parry_until.get(id, 0.0):
			parry_pending.erase(id)
			if alive.get(id, false):
				_send_parry_fail(id)
	if monster.state != "stun" and monster.state != "wake":
		for tid in traps.keys():
			var tp: Vector3 = traps[tid]["pos"]
			var mp: Vector3 = monster.global_position
			if Vector2(tp.x - mp.x, tp.z - mp.z).length() < 0.9 and absf(tp.y - mp.y) < 1.2:
				monster.trap_stun(3.5)
				s_trap_hit.rpc(tid)
				break
	_check_end()


func _send_parry_fail(id: int) -> void:
	if id == 1:
		s_parry_fail()
	else:
		s_parry_fail.rpc_id(id)


func parry_active(id: int) -> bool:
	return parry_until.get(id, -1.0) >= elapsed


func on_parried(ids: Array[int]) -> void:
	var res: String = monster.try_stun(false)
	for id in ids:
		parry_pending.erase(id)
		parry_until.erase(id)
	s_parry_ok.rpc(ids[0], res, monster.global_position + Vector3(0, 1.6, 0))


func server_catch(id: int) -> void:
	if alive.get(id, false) and not over:
		s_caught.rpc(id)


func server_noise(pos: Vector3, r: float) -> void:
	if monster.hear(pos, r) and monster_player:
		_add_ping(pos)  # the host IS the monster, so show it locally


func _add_ping(pos: Vector3) -> void:
	if is_monster():
		_mark(pos + Vector3(0, 1.0, 0), "?", Color(1, 0.3, 0.2), 1.5)


func on_sahur_call() -> void:
	if monster_player:
		return
	var best := -1
	var bd := INF
	for id in players:
		if alive.get(id, false):
			var d: float = monster.global_position.distance_to(players[id].global_position)
			if d < bd:
				bd = d
				best = id
	if best != -1:
		monster.call_track_id = best
		monster.call_track_t = 4.0
		monster.has_noise = true
		monster.last_noise = players[best].global_position
		monster.target = players[best].global_position
		monster.set_state("hunt")
		monster.repath_t = 0.0


func _check_end() -> void:
	if over or alive.is_empty():
		return
	for id in alive:
		if alive[id]:
			return
	s_game_over.rpc(false, "")


func fx(kind: String, pos: Vector3) -> void:
	s_fx.rpc(kind, pos)


func _on_peer_left(id: int) -> void:
	if players.has(id):
		players[id].queue_free()
		players.erase(id)
		alive.erase(id)
		_msg("%s left the game" % Net.name_of(id))
		if multiplayer.is_server():
			_check_end()


func leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Net.leave()
	get_parent().back_to_menu("")


func summary() -> String:
	var ps := []
	for id in players:
		ps.append("%d@%s%s" % [id, str(players[id].global_position.snapped(Vector3.ONE * 0.1)), "" if alive.get(id, false) else "(dead)"])
	return "t=%.1f players=%s monster=%s state=%s items=%d/%d over=%s stun_immune=%.1f" % [
		elapsed, str(ps), str(monster.global_position.snapped(Vector3.ONE * 0.1)), monster.state, items_got, items_needed, str(over), monster.immune_t]


# ------------------------------------------------------------------ client -> server
@rpc("any_peer", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, pitch: float, mode: int, flags: int) -> void:
	var id := _sender()
	if players.has(id) and not players[id].is_local:
		var p: Node3D = players[id]
		p.target_pos = pos
		p.net_yaw = yaw
		p.net_pitch = pitch
		p.mode = mode
		p.apply_flags(flags)
		if not alive.get(id, false):
			p.hidden = false


@rpc("any_peer", "reliable")
func c_noise(pos: Vector3, r: float) -> void:
	if alive.get(_sender(), false):
		server_noise(pos, minf(r, N_MAX))


@rpc("any_peer", "reliable")
func c_pickup(i: int) -> void:
	var id := _sender()
	if over or i < 0 or i >= house.pickups.size() or pick_taken[i] or not alive.get(id, false):
		return
	if players[id].global_position.distance_to(house.pickups[i]["pos"]) > 4.0:
		return
	var kind: String = house.pickups[i]["kind"]
	match kind:
		"trap", "decoy":
			inv[id][kind] += 1
		"gun":
			inv[id]["gun"] = true
			inv[id]["ammo"] += GUN_AMMO
	s_pick_taken.rpc(i, id)
	server_noise(house.pickups[i]["pos"], N_PICKUP)


@rpc("any_peer", "reliable")
func c_vase(i: int) -> void:
	var id := _sender()
	if over or i < 0 or i >= house.vases.size() or vase_broken[i] or not alive.get(id, false):
		return
	s_vase_broken.rpc(i)
	server_noise(house.vases[i]["pos"], N_VASE)


@rpc("any_peer", "reliable")
func c_use(kind: String, pos: Vector3) -> void:
	var id := _sender()
	if over or not inv.has(id) or not inv[id].has(kind) or inv[id][kind] <= 0 or not alive.get(id, false):
		return
	inv[id][kind] -= 1
	if kind == "trap":
		s_trap_add.rpc(next_tid, pos)
		next_tid += 1
	elif kind == "decoy":
		decoys.append({"pos": pos, "t": 2.5})
		s_decoy_add.rpc(pos)


@rpc("any_peer", "reliable")
func c_parry() -> void:
	var id := _sender()
	if over or not alive.get(id, false):
		return
	parry_until[id] = elapsed + PARRY_WINDOW + PARRY_LAG
	parry_pending[id] = true


@rpc("any_peer", "reliable")
func c_shoot(origin: Vector3, dir: Vector3) -> void:
	var id := _sender()
	if over or not alive.get(id, false) or not inv.has(id) or not inv[id]["gun"] or inv[id]["ammo"] <= 0:
		return
	inv[id]["ammo"] -= 1
	dir = dir.normalized()
	if players.has(id) and origin.distance_to(players[id].global_position) > 3.0:
		origin = players[id].global_position + Vector3(0, 1.5, 0)
	var end := origin + dir * GUN_RANGE
	var wall := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, end, 1))
	var wall_t := GUN_RANGE
	if not wall.is_empty():
		wall_t = origin.distance_to(wall["position"])
		end = wall["position"]
	# hit spheres on Tung Tung: bat tip, bat middle, head, body
	var spheres := [
		["bat", monster.bat_tip(), 0.4],
		["bat", monster.bat.to_global(Vector3(0, -0.4, 0)), 0.3],
		["head", monster.head_pos(), 0.5],
		["body", monster.global_position + Vector3(0, 1.2, 0), 0.55],
		["body", monster.global_position + Vector3(0, 0.6, 0), 0.4],
	]
	var part := ""
	var best_t := wall_t
	for s in spheres:
		var t := _ray_sphere(origin, dir, s[1], s[2])
		if t >= 0.0 and t < best_t:
			best_t = t
			part = s[0]
	var res := ""
	if part != "":
		end = origin + dir * best_t
		if part == "body" and monster.is_attacking():
			res = "thud"
		else:
			res = monster.try_stun(true)
		if not monster_player:
			monster.chase_id = id
	s_shot.rpc(id, origin, end, part, res)
	server_noise(origin, N_SHOT)


func _ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var h := b * b - cc
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else -1.0


@rpc("any_peer", "reliable")
func c_escape() -> void:
	var id := _sender()
	if over or not exit_open or not alive.get(id, false):
		return
	s_game_over.rpc(true, Net.name_of(id))


# ------------------------------------------------------------------ server -> everyone
@rpc("authority", "call_remote", "unreliable_ordered")
func s_snap(ids: PackedInt32Array, poss: PackedVector3Array, rots: PackedVector2Array, modes: PackedByteArray,
		flags: PackedByteArray, mpos: Vector3, myaw: float, mst: int, mflags: int, t: float, ab: PackedFloat32Array) -> void:
	for k in ids.size():
		var id: int = ids[k]
		if id != local_id and players.has(id):
			var p: Node3D = players[id]
			p.target_pos = poss[k]
			p.net_yaw = rots[k].x
			p.net_pitch = rots[k].y
			p.mode = modes[k]
			p.apply_flags(flags[k])
	if monster:
		monster.net_update(mpos, myaw, mst, mflags)
	mon_flags = mflags
	if absf(elapsed - t) > 0.5:
		elapsed = t
	ab_ready = ab
	ab_stamp = elapsed


@rpc("authority", "call_local", "reliable")
func s_pick_taken(i: int, id: int) -> void:
	pick_taken[i] = true
	var pk: Dictionary = house.pickups[i]
	pk["node"].visible = false
	Sfx.play_at("pickup", pk["pos"], self)
	var kind: String = pk["kind"]
	if kind == "item":
		items_got += 1
		_ring(pk["pos"], 4.0, Color(1, 0.9, 0.3))
		if items_got >= items_needed and not exit_open:
			_open_exit()
		else:
			_msg("%s found a takjil! (%d/%d)" % [Net.name_of(id), items_got, items_needed], 2.5)
		if multiplayer.is_server() and not monster.rage and items_needed - items_got <= MonsterScript.RAGE_ITEMS_LEFT:
			monster.rage = true
			fx("rage", monster.global_position)
	elif id == local_id:
		match kind:
			"trap":
				my_inv["trap"] += 1
				_msg("Got a BEAR TRAP! Press G to place it.", 2.5)
			"decoy":
				my_inv["decoy"] += 1
				_msg("Got a DECOY DRUM! Press Q to throw it - lures Tung Tung away.", 2.5)
			"gun":
				my_inv["gun"] = true
				my_inv["ammo"] += GUN_AMMO
				if me():
					me().weapon = 1
				_msg("Got a FLARE PISTOL (%d flares)! Press 2 / scroll to switch.\nShoot his BAT or HEAD while he winds up to stun him. Gunshots are LOUD." % GUN_AMMO, 4.5)


func _open_exit() -> void:
	exit_open = true
	house.open_exit()
	Sfx.play("door")
	_msg("THE FRONT DOOR IS OPEN!\nEscape through the front door (ground floor, bottom-left)!", 5.0)


@rpc("authority", "call_local", "reliable")
func s_vase_broken(i: int) -> void:
	vase_broken[i] = true
	var v: Dictionary = house.vases[i]
	v["node"].visible = false
	Sfx.play_at("smash", v["pos"], self, 4.0)
	_ring(v["pos"], 8.0, Color(1, 0.5, 0.3), 1.0)
	if me() and me().global_position.distance_to(v["pos"]) < 3.0:
		_msg("CRASH! You knocked over a vase! (crouch to sneak past them)", 2.5)


@rpc("authority", "call_local", "reliable")
func s_trap_add(tid: int, pos: Vector3) -> void:
	traps[tid] = {"pos": pos, "node": house._make_trap(pos, false)}


@rpc("authority", "call_local", "reliable")
func s_trap_hit(tid: int) -> void:
	if not traps.has(tid):
		return
	var pos: Vector3 = traps[tid]["pos"]
	traps[tid]["node"].queue_free()
	traps.erase(tid)
	Sfx.play_at("snap", pos, self, 4.0)
	Sfx.play_at("stun", pos, self, 2.0)
	_msg("TUNG TUNG STEPPED IN A TRAP! RUN!", 2.5)


@rpc("authority", "call_local", "reliable")
func s_decoy_add(pos: Vector3) -> void:
	var n: Node3D = house._make_drum(pos)
	get_tree().create_timer(2.6).timeout.connect(n.queue_free)


@rpc("authority", "call_local", "reliable")
func s_parry_ok(id: int, res: String, pos: Vector3) -> void:
	Sfx.play_at("clang", pos, self, 6.0)
	_ring(pos - Vector3(0, 1.5, 0), 3.0, Color(1, 1, 0.5), 0.5)
	_mark(pos + Vector3(0, 0.5, 0), "PARRY!" if res == "stun" else "BLOCK", Color(1, 0.95, 0.3), 1.2)
	shake = maxf(shake, 1.0)
	if id == local_id:
		parry_cd_t = 0.2
	if res == "stun":
		Sfx.play_at("stun", pos, self, 4.0)
		_msg("%s PARRIED! TUNG TUNG IS STUNNED - RUN!" % ("YOU" if id == local_id else Net.name_of(id)), 3.0)
	else:
		_msg("%s blocked the swing! (He's still dizzy-immune, no stun)" % ("YOU" if id == local_id else Net.name_of(id)), 2.5)


@rpc("authority", "call_remote", "reliable")
func s_parry_fail() -> void:
	var m := me()
	if m == null:
		return
	m.vulnerable_t = VULN_TIME
	parry_cd_t = maxf(parry_cd_t, PARRY_FAIL_LOCK)
	Sfx.play("fail", -2.0)
	hud.small("Parry missed - you're OPEN for a moment!")


@rpc("authority", "call_local", "reliable")
func s_shot(id: int, origin: Vector3, end: Vector3, part: String, res: String) -> void:
	if id != local_id:
		Sfx.play_at("shot", origin, self, 4.0)
	_tracer(origin + Vector3(0, -0.15, 0), end)
	match res:
		"stun":
			Sfx.play_at("clang", end, self, 6.0, 1.3)
			Sfx.play_at("stun", end, self, 4.0)
			_mark(end + Vector3(0, 0.4, 0), "DEFLECT!", Color(1, 0.95, 0.3), 1.2)
			_msg("%s shot the %s - TUNG TUNG IS STUNNED!" % ["YOU" if id == local_id else Net.name_of(id), part.to_upper()], 3.0)
		"block":
			Sfx.play_at("clang", end, self, 4.0, 1.3)
			_mark(end + Vector3(0, 0.4, 0), "BLOCK", Color(1, 0.8, 0.3), 1.0)
			_msg("Deflected his swing! (He's immune to stuns right now)", 2.0)
		"flinch":
			Sfx.play_at("tung", end, self, 4.0, 1.5)
			if id == local_id:
				hud.small("Hit! He flinched... and now he's angry. Shoot during his WINDUP to stun.")
		"thud":
			Sfx.play_at("tung", end, self, 2.0, 1.6)
			if id == local_id:
				hud.small("Body shot - aim for the BAT or HEAD!")


func _tracer(a: Vector3, b: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var len := a.distance_to(b)
	if len < 0.1:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.55, 0.2, 0.9)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.03, len)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	fx_root.add_child(mi)
	mi.global_position = (a + b) * 0.5
	mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	var l := OmniLight3D.new()
	l.light_color = Color(1, 0.5, 0.2)
	l.light_energy = 4.0
	l.omni_range = 6.0
	fx_root.add_child(l)
	l.global_position = b - (b - a).normalized() * 0.3
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_property(l, "light_energy", 0.0, 0.35)
	tw.chain().tween_callback(func(): mi.queue_free(); l.queue_free())


@rpc("authority", "call_local", "reliable")
func s_fx(kind: String, pos: Vector3) -> void:
	match kind:
		"drum":
			for i in 3:
				get_tree().create_timer(i * 0.25).timeout.connect(func(): Sfx.play_at("drum", pos, self, 8.0))
			_ring(pos, 10.0, Color(1, 0.4, 0.3), 1.2)
		"call":
			for i in 3:
				get_tree().create_timer(i * 0.3).timeout.connect(func(): Sfx.play("tung", 6.0, 0.8))
			_msg("TUNG TUNG TUNG SAHUR!!!\nHe knows where you are... MOVE!", 3.5)
			shake = 1.5
			flash_red = 0.6
			reveal_t = 4.0
			if is_monster() and reveal_marks.is_empty():
				for i in 6:
					reveal_marks.append(_mark(Vector3.ZERO, "!", Color(1, 0.15, 0.1), 0.0))
		"dark":
			dark_t = MonsterScript.DARK_TIME
			Sfx.play("dark", 4.0)
			_msg("LAMPU MATI! The lights are out...", 3.0)
		"tele":
			Sfx.play_at("tele", pos, self, 4.0)
			_ring(pos, 3.0, Color(0.8, 0.3, 1.0), 0.8)
		"dash":
			Sfx.play_at("tung", pos, self, 8.0, 1.4)
		"windup":
			for i in 3:
				get_tree().create_timer(i * 0.2).timeout.connect(func(): Sfx.play_at("tung", pos, self, 8.0, 1.25 + i * 0.12))
		"swing":
			Sfx.play_at("whoosh", pos, self, 6.0, 0.7)
		"spotted":
			Sfx.play_at("sting", pos, self, 2.0)
		"awake":
			Sfx.play("sting", -4.0, 0.6)
			_msg("Tung Tung is awake...", 2.0)
		"rage":
			_msg("TUNG TUNG IS ENRAGED! It's faster and swings quicker now!", 3.0)
			Sfx.play("sting", 0.0, 0.7)
		"unlock_call":
			_msg("Tung Tung learned SAHUR CALL!\nEvery minute it senses where you are...", 3.5)
		"unlock_dark":
			_msg("Tung Tung learned LAMPU MATI!\nIt can cut the lights...", 3.5)
		"unlock_tele":
			_msg("Tung Tung learned TELEPORT!\nIt can now appear at noises!", 3.5)


@rpc("authority", "call_local", "reliable")
func s_caught(id: int) -> void:
	if not alive.get(id, false):
		return
	alive[id] = false
	if players.has(id):
		if id == local_id and hide_idx >= 0:
			players[id].exit_hide(house.hides[hide_idx])
			hide_idx = -1
		players[id].set_dead()
		Sfx.play_at("caught", players[id].global_position, self, 6.0)
	if id == local_id:
		shake = 2.0
		flash_red = 1.0
		_msg("BONK! YOU WERE CAUGHT!\nYou're a ghost now: fly with WASD/Space/Ctrl, LEFT CLICK to watch a survivor.", 5.0)
	else:
		_msg("%s was caught by Tung Tung!" % Net.name_of(id), 3.0)


@rpc("authority", "call_local", "reliable")
func s_game_over(survivors_win: bool, who: String) -> void:
	if over:
		return
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if survivors_win:
		hud.game_over("SURVIVORS WIN!\n%s escaped the house!" % who)
		Sfx.play("door")
	else:
		hud.game_over("TUNG TUNG SAHUR WINS!\nEveryone was caught.")
		Sfx.play("caught")
