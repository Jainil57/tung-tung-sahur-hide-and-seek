extends CharacterBody3D
## TUNG TUNG SAHUR (3D). The server runs the AI (or the host steers it); clients interpolate.
## It HEARS noise (mic, sprinting, vases, squeaky floors, gunshots, decoys) and hunts the
## loudest recent one. On sight it chases, winds up its bat (telegraph: bat raised, red glow,
## "tung tung tung") and swings. A sword parry or a gunshot to the bat/head during the
## windup STUNS it (with immunity afterwards so it can't be stun-locked).

const SPEED_WANDER := 2.0
const SPEED_HUNT := 3.4
const SPEED_CHASE := 4.6
const SPEED_PLAYER := 4.9
const SIGHT := 13.0
const SIGHT_KEEP := 20.0
const FOV_COS := 0.25        # ~150 degree vision cone
const ATTACK_RANGE := 2.3
const HIT_RANGE := 3.0
const HIT_COS := 0.26        # ~75 degrees each side
const WINDUP := 0.85
const WINDUP_RAGE := 0.7
const SWING := 0.3
const RECOVER := 0.8
const ATTACK_CD := 0.6
const STUN_TIME := 3.5
const STUN_IMMUNE := 6.0
const WAKE_TIME := 6.0
const GRAVITY := 20.0

# Special abilities: unlock at a set time, then cooldown. The AI casts Sahur Call and
# Lampu Mati as soon as they are ready, so survivors get a reliable countdown warning.
const UNLOCK := {"dash": 0.0, "call": 45.0, "dark": 70.0, "tele": 90.0}
const CD := {"dash": 12.0, "call": 60.0, "dark": 75.0, "tele": 50.0}
const ABILITY_ORDER := ["dash", "call", "dark", "tele"]
const DASH_TIME := 1.4
const DARK_TIME := 10.0
const RAGE_ITEMS_LEFT := 2

const STATES := ["wake", "wander", "hunt", "look", "chase", "windup", "swing", "recover", "stun", "flinch"]

var game: Node
var house: Node
var controlled := false
var is_server := false
var state := "wake"
var state_t := 0.0
var target := Vector3.ZERO
var chase_id := -1
var noise_score := 0.0
var has_noise := false
var last_noise := Vector3.ZERO
var call_track_id := -1
var call_track_t := 0.0
var sight_t := 0.0
var wander_t := 0.0
var repath_t := 0.0
var stuck_t := 0.0
var stuck_pos := Vector3.ZERO
var stun_t := 0.0
var immune_t := 0.0
var dash_t := 0.0
var attack_cd := 0.0
var cd := {"dash": 0.0, "call": 0.0, "dark": 0.0, "tele": 0.0}
var rage := false
var net_target := Vector3.ZERO
var net_yaw := 0.0
var anim := 0.0
var last_step := Vector3.ZERO
var moving := false
var want_attack := false
var freeze_pose := ""  # screenshots/tests only

var agent: NavigationAgent3D
var model: Node3D
var arm_r: Node3D
var arm_l: Node3D
var bat: Node3D
var stars: Node3D
var disc: MeshInstance3D
var disc_mat: StandardMaterial3D
var eye_mat: StandardMaterial3D
var bat_mat: StandardMaterial3D
var wood_mat: StandardMaterial3D
var eye_light: OmniLight3D
var leg_l: Node3D
var leg_r: Node3D


func setup(g: Node, pos: Vector3, ctrl: bool) -> void:
	game = g
	house = g.house
	position = pos
	net_target = pos
	last_step = pos
	target = pos
	stuck_pos = pos
	controlled = ctrl
	name = "Monster"


func _ready() -> void:
	is_server = multiplayer.is_server()
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(40)
	floor_snap_length = 0.5
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 2.1
	cs.shape = cap
	cs.position = Vector3(0, 1.05, 0)
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 0.8
	agent.radius = 0.5
	agent.height = 2.0
	agent.path_max_distance = 3.0
	add_child(agent)
	_build_model()


# ------------------------------------------------------------------ model
func _m(col: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _part(mesh: Mesh, pos: Vector3, mat: Material, parent: Node3D, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cylm(rt: float, rb: float, h: float, segs := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _boxm(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


func _sphm(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2
	s.radial_segments = 12
	s.rings = 6
	return s


func _build_model() -> void:
	wood_mat = _m(Color(0.62, 0.42, 0.24))
	var wood_tex: Texture2D = house.mats["wood"].albedo_texture
	wood_mat.albedo_texture = wood_tex
	wood_mat.uv1_scale = Vector3(1, 3, 1)
	var dark := _m(Color(0.3, 0.18, 0.09))
	var ring := _m(Color(0.82, 0.64, 0.4))
	var white := _m(Color(0.95, 0.95, 0.92), 0.4)
	eye_mat = _m(Color(0.05, 0.02, 0.02), 0.3)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1, 0.05, 0.02)
	eye_mat.emission_energy_multiplier = 0.5
	bat_mat = _m(Color(0.42, 0.25, 0.12))
	bat_mat.albedo_texture = wood_tex
	bat_mat.emission_enabled = true
	bat_mat.emission = Color(1, 0.1, 0.05)
	bat_mat.emission_energy_multiplier = 0.0
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	# legs
	leg_l = Node3D.new()
	leg_l.position = Vector3(-0.18, 0.62, 0)
	model.add_child(leg_l)
	_part(_cylm(0.09, 0.08, 0.62), Vector3(0, -0.31, 0), dark, leg_l)
	_part(_boxm(Vector3(0.18, 0.08, 0.3)), Vector3(0, -0.58, -0.06), dark, leg_l)
	leg_r = Node3D.new()
	leg_r.position = Vector3(0.18, 0.62, 0)
	model.add_child(leg_r)
	_part(_cylm(0.09, 0.08, 0.62), Vector3(0, -0.31, 0), dark, leg_r)
	_part(_boxm(Vector3(0.18, 0.08, 0.3)), Vector3(0, -0.58, -0.06), dark, leg_r)
	# the log body
	_part(_cylm(0.42, 0.45, 1.6, 18), Vector3(0, 1.4, 0), wood_mat, model)
	_part(_cylm(0.4, 0.4, 0.04, 18), Vector3(0, 2.21, 0), ring, model)
	_part(_cylm(0.24, 0.24, 0.045, 14), Vector3(0, 2.215, 0), dark, model)
	_part(_cylm(0.1, 0.1, 0.05, 10), Vector3(0, 2.22, 0), ring, model)
	for i in 7:  # bark grooves (skip the face side)
		var a := PI * 0.35 + i * (PI * 1.3 / 6.0)
		_part(_boxm(Vector3(0.04, 1.3, 0.03)), Vector3(sin(a) * 0.44, 1.35, cos(a) * 0.44), dark, model, Vector3(0, a, 0))
	# face (front is -Z)
	for s in [-1, 1]:
		_part(_sphm(0.11), Vector3(s * 0.16, 1.86, -0.37), white, model)
		_part(_sphm(0.055), Vector3(s * 0.16, 1.86, -0.47), eye_mat, model)
		_part(_boxm(Vector3(0.2, 0.045, 0.05)), Vector3(s * 0.15, 2.0, -0.43), dark, model, Vector3(0, 0, -s * 0.35))
	_part(_cylm(0.035, 0.05, 0.12, 8), Vector3(0, 1.72, -0.47), dark, model, Vector3(PI / 2, 0, 0))
	var mouth := _m(Color(0.12, 0.03, 0.02))
	_part(_boxm(Vector3(0.34, 0.07, 0.05)), Vector3(0, 1.55, -0.43), mouth, model)
	_part(_boxm(Vector3(0.06, 0.06, 0.05)), Vector3(-0.17, 1.59, -0.43), mouth, model)
	_part(_boxm(Vector3(0.06, 0.06, 0.05)), Vector3(0.17, 1.59, -0.43), mouth, model)
	# arms (pivot at shoulder; rotation.x raises them)
	arm_l = Node3D.new()
	arm_l.position = Vector3(-0.5, 1.72, 0)
	model.add_child(arm_l)
	_part(_cylm(0.07, 0.06, 0.65), Vector3(0, -0.32, 0), dark, arm_l)
	_part(_sphm(0.09), Vector3(0, -0.66, 0), wood_mat, arm_l)
	arm_r = Node3D.new()
	arm_r.position = Vector3(0.5, 1.72, 0)
	model.add_child(arm_r)
	_part(_cylm(0.07, 0.06, 0.65), Vector3(0, -0.32, 0), dark, arm_r)
	_part(_sphm(0.09), Vector3(0, -0.66, 0), wood_mat, arm_r)
	bat = Node3D.new()
	bat.position = Vector3(0, -0.66, 0)
	bat.rotation.x = 0.55
	arm_r.add_child(bat)
	_part(_cylm(0.05, 0.12, 1.05, 12), Vector3(0, -0.45, 0), bat_mat, bat)
	_part(_cylm(0.12, 0.12, 0.02, 12), Vector3(0, -0.98, 0), dark, bat)
	# stun stars
	stars = Node3D.new()
	stars.position = Vector3(0, 2.55, 0)
	stars.visible = false
	model.add_child(stars)
	var star_mat := _m(Color(1, 0.95, 0.2))
	star_mat.emission_enabled = true
	star_mat.emission = Color(1, 0.9, 0.2)
	star_mat.emission_energy_multiplier = 2.5
	for i in 4:
		var a := i * TAU / 4.0
		var st := _part(_boxm(Vector3(0.13, 0.13, 0.13)), Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), star_mat, stars)
		st.rotation = Vector3(0.6, 0.6, 0.0)
	# danger zone telegraph on the floor
	disc_mat = StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(1, 0.05, 0.02, 0.0)
	disc = _part(_cylm(HIT_RANGE, HIT_RANGE, 0.02, 32), Vector3(0, 0.04, 0), disc_mat, self)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.visible = false
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(1, 0.12, 0.05)
	eye_light.omni_range = 3.5
	eye_light.light_energy = 0.6
	eye_light.position = Vector3(0, 1.85, -0.9)
	model.add_child(eye_light)


func bat_tip() -> Vector3:
	return bat.to_global(Vector3(0, -0.75, 0))


func head_pos() -> Vector3:
	return global_position + Vector3(0, 1.85, 0)


# ------------------------------------------------------------------ state helpers
func set_state(s: String) -> void:
	if s != state:
		state = s
		state_t = 0.0


func is_attacking() -> bool:
	return state == "windup" or state == "swing"


func windup_time() -> float:
	return WINDUP_RAGE if rage else WINDUP


func speed_mult() -> float:
	return (1.85 if dash_t > 0.0 else 1.0) * (1.2 if rage else 1.0)


func ready_in(k: String) -> float:
	return maxf(UNLOCK[k] - game.elapsed, cd[k])


func ability_ready(k: String) -> bool:
	if state == "stun" or state == "wake" or is_attacking():
		return false
	if ready_in(k) > 0.0:
		return false
	if k == "tele" and not has_noise:
		return false
	return true


func ability_text(k: String) -> String:
	var t: float = game.elapsed
	if t < UNLOCK[k]:
		return "unlocks in %ds" % int(ceil(UNLOCK[k] - t))
	if cd[k] > 0.0:
		return "%ds" % int(ceil(cd[k]))
	if k == "tele" and not has_noise:
		return "no noise heard yet"
	return "READY"


func use_ability(k: String) -> bool:
	if not is_server or game.over or not ability_ready(k):
		return false
	cd[k] = CD[k]
	match k:
		"dash":
			dash_t = DASH_TIME
			game.fx("dash", global_position)
		"call":
			game.fx("call", global_position)
			game.on_sahur_call()
		"dark":
			game.fx("dark", global_position)
		"tele":
			var dest: Vector3 = house.find_floor_near(last_noise)
			game.fx("tele", global_position)
			global_position = dest + Vector3(0, 0.1, 0)
			last_step = dest
			velocity = Vector3.ZERO
			game.fx("tele", dest)
			if not controlled:
				set_state("hunt")
				target = last_noise
				repath_t = 0.0
	return true


func start_windup() -> void:
	if attack_cd > 0.0 or state == "stun" or state == "wake" or is_attacking():
		return
	set_state("windup")
	velocity = Vector3.ZERO
	dash_t = 0.0
	game.fx("windup", global_position)


## Called by the game when a parry/gunshot connects. Returns "stun", "block" or "".
func try_stun(by_gun: bool) -> String:
	if not is_server:
		return ""
	if not is_attacking() and not by_gun:
		return ""
	if not is_attacking():
		# shot while not attacking: just flinches and gets angry
		if state != "stun" and state != "wake":
			set_state("flinch")
		return "flinch"
	if immune_t > 0.0:
		set_state("recover")
		state_t = RECOVER * 0.4
		attack_cd = ATTACK_CD
		return "block"
	set_state("stun")
	stun_t = STUN_TIME
	immune_t = STUN_TIME + STUN_IMMUNE
	dash_t = 0.0
	velocity = Vector3.ZERO
	return "stun"


func trap_stun(t: float) -> void:
	set_state("stun")
	stun_t = t
	immune_t = t + STUN_IMMUNE * 0.5
	dash_t = 0.0
	velocity = Vector3.ZERO


func net_update(pos: Vector3, yaw: float, st: int, flags: int) -> void:
	if pos.distance_to(global_position) > 6.0:
		global_position = pos  # teleported
	net_target = pos
	net_yaw = yaw
	var s: String = STATES[clampi(st, 0, STATES.size() - 1)]
	if s != state:
		set_state(s)
	rage = flags & 1 != 0
	dash_t = 1.0 if flags & 4 != 0 else 0.0
	immune_t = 1.0 if flags & 2 != 0 else 0.0


func net_flags() -> int:
	return (1 if rage else 0) | (2 if immune_t > 0.0 else 0) | (4 if dash_t > 0.0 else 0)


func hear(pos: Vector3, r: float) -> bool:
	if state == "stun" or state == "wake":
		return false
	if house.floor_of(pos.y) != house.floor_of(global_position.y):
		r *= 0.6  # muffled through the floor
	var d := global_position.distance_to(pos)
	if d > r:
		return false
	has_noise = true
	last_noise = pos
	if controlled:
		return true
	if state in ["chase", "windup", "swing", "recover", "flinch"]:
		return true
	var score := r - d
	if state != "hunt" or score >= noise_score * 0.8:
		noise_score = score
		target = pos
		set_state("hunt")
		repath_t = 0.0
	return true


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	anim += delta
	state_t += delta
	if not is_server:
		var old := global_position
		global_position = global_position.lerp(net_target, minf(1.0, 12.0 * delta))
		rotation.y = lerp_angle(rotation.y, net_yaw, minf(1.0, 12.0 * delta))
		moving = old.distance_to(global_position) > 0.01
		_steps()
		_animate(delta)
		return
	for k in cd:
		cd[k] = maxf(0.0, cd[k] - delta)
	immune_t = maxf(0.0, immune_t - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	dash_t = maxf(0.0, dash_t - delta)
	var hv := Vector3.ZERO
	if freeze_pose != "":
		state = freeze_pose
		state_t = windup_time() * 0.75
		_animate(delta)
		return
	if not game.over:
		match state:
			"wake":
				if state_t >= WAKE_TIME:
					set_state("wander")
					game.fx("awake", global_position)
			"stun":
				stun_t -= delta
				if stun_t <= 0.0:
					set_state("hunt" if has_noise else "wander")
					target = last_noise if has_noise else target
					repath_t = 0.0
			"flinch":
				if state_t >= 0.6:
					set_state("chase" if _valid(chase_id) else "hunt")
			"windup":
				if not controlled and _valid(chase_id):
					var to: Vector3 = game.players[chase_id].global_position - global_position
					to.y = 0
					if to.length() > 0.1:
						_face(to.normalized(), delta * 0.6)
						if to.length() > 1.4:
							hv = to.normalized() * 1.2
				elif controlled:
					rotation.y = lerp_angle(rotation.y, game.cam_yaw, minf(1.0, 10.0 * delta))
				if state_t >= windup_time():
					_do_swing()
			"swing":
				if state_t >= SWING:
					set_state("recover")
			"recover":
				if state_t >= RECOVER:
					attack_cd = ATTACK_CD
					set_state("chase" if _valid(chase_id) and not controlled else ("hunt" if has_noise else "wander"))
			_:
				if controlled:
					hv = _player_control(delta)
				else:
					hv = _ai(delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	moving = hv.length() > 0.1
	if global_position.y < -5.0:
		global_position = house.monster_spawn + Vector3(0, 0.5, 0)
	_steps()
	_animate(delta)


func _valid(id: int) -> bool:
	return game.players.has(id) and game.alive.get(id, false)


func _face(dir: Vector3, delta: float) -> void:
	var ty := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, ty, minf(1.0, 9.0 * delta))


func _do_swing() -> void:
	set_state("swing")
	game.fx("swing", global_position)
	var fwd := -global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var hits: Array[int] = []
	var parried: Array[int] = []
	for id in game.players:
		if not game.alive.get(id, false):
			continue
		var p: Node3D = game.players[id]
		var to := p.global_position - global_position
		var dy := to.y
		to.y = 0
		if absf(dy) > 1.6 or to.length() > HIT_RANGE:
			continue
		if to.length() > 0.7 and fwd.dot(to.normalized()) < HIT_COS:
			continue
		if p.hidden and id != chase_id:
			continue
		if not house.los(head_pos(), p.global_position + Vector3(0, 1.0, 0)) and to.length() > 1.0:
			continue
		if game.parry_active(id):
			parried.append(id)
		else:
			hits.append(id)
	if not parried.is_empty():
		game.on_parried(parried)
		return
	for id in hits:
		game.server_catch(id)
	if not hits.is_empty() and not controlled:
		chase_id = -1


func _steps() -> void:
	var a := global_position
	a.y = 0
	var b := last_step
	b.y = 0
	if a.distance_to(b) > 1.7:
		last_step = global_position
		Sfx.play_at("tung", global_position, game, -2.0, randf_range(0.9, 1.1))


func _player_control(_delta: float) -> Vector3:
	var d := Vector3.ZERO
	if game.mouse_free():
		return d
	if Input.is_physical_key_pressed(KEY_W): d.z -= 1
	if Input.is_physical_key_pressed(KEY_S): d.z += 1
	if Input.is_physical_key_pressed(KEY_A): d.x -= 1
	if Input.is_physical_key_pressed(KEY_D): d.x += 1
	rotation.y = game.cam_yaw
	if want_attack:
		want_attack = false
		start_windup()
		return Vector3.ZERO
	return (Basis(Vector3.UP, game.cam_yaw) * d).normalized() * SPEED_PLAYER * speed_mult()


func _ai(delta: float) -> Vector3:
	# --- eyes ---
	sight_t -= delta
	if sight_t <= 0.0:
		sight_t = 0.15
		var best := -1
		var bd := INF
		var fwd := -global_transform.basis.z
		for id in game.players:
			if not game.alive.get(id, false):
				continue
			var p: Node3D = game.players[id]
			var d := global_position.distance_to(p.global_position)
			if p.hidden and not (state == "chase" and chase_id == id and d < 4.0):
				continue
			var rng := SIGHT_KEEP if (state == "chase" and chase_id == id) else SIGHT
			if p.mode == 1:
				rng *= 0.6  # crouching = harder to spot
			if p.flashlight_on:
				rng *= 1.35  # a lit flashlight gives you away
			if house.dark_k < 0.5:
				rng *= 0.8
			var to := (p.global_position - global_position).normalized()
			if d > 3.0 and fwd.dot(to) < FOV_COS:
				continue
			if d < rng and d < bd and house.los(head_pos(), p.global_position + Vector3(0, 1.2 if p.mode != 1 else 0.7, 0)):
				best = id
				bd = d
		if best != -1:
			if state != "chase":
				game.fx("spotted", global_position)
			set_state("chase")
			chase_id = best
		elif state == "chase":
			set_state("hunt")  # lost them: go to where they were last seen
			repath_t = 0.0
	noise_score = maxf(0.0, noise_score - delta * 2.0)
	if call_track_t > 0.0:
		call_track_t -= delta
		if _valid(call_track_id) and state != "chase":
			target = game.players[call_track_id].global_position
			if state != "hunt":
				set_state("hunt")
	# --- auto abilities ---
	if ability_ready("call"):
		use_ability("call")
	if state != "chase" and ability_ready("dark"):
		use_ability("dark")
	# --- brain ---
	var spd := SPEED_WANDER
	match state:
		"chase":
			if _valid(chase_id):
				target = game.players[chase_id].global_position
				var to := target - global_position
				var dy := to.y
				to.y = 0
				if to.length() < ATTACK_RANGE and absf(dy) < 1.5 and attack_cd <= 0.0:
					start_windup()
					return Vector3.ZERO
				if to.length() > 4.0 and to.length() < 12.0 and absf(dy) < 1.5:
					use_ability("dash")
				spd = SPEED_CHASE
				if to.length() < 3.5 and absf(dy) < 1.0:
					_face(to.normalized(), delta)
					return to.normalized() * spd * speed_mult()
			else:
				set_state("wander")
				wander_t = 0.0
		"hunt":
			spd = SPEED_HUNT
			if has_noise and global_position.distance_to(last_noise) > 22.0:
				use_ability("tele")
			var to := target - global_position
			if Vector2(to.x, to.z).length() < 1.3 and absf(to.y) < 1.5:
				set_state("look")
		"look":
			rotation.y += delta * 2.5
			if state_t > 2.0:
				set_state("wander")
				wander_t = 0.0
			return Vector3.ZERO
		"wander":
			wander_t -= delta
			var to := target - global_position
			if wander_t <= 0.0 or (Vector2(to.x, to.z).length() < 1.3 and absf(to.y) < 1.5):
				target = house.random_floor_pos()
				wander_t = 18.0
				repath_t = 0.0
	# stuck detection
	stuck_t += delta
	if stuck_t > 2.0:
		if global_position.distance_to(stuck_pos) < 0.4 and state != "chase":
			if state == "hunt":
				set_state("look")
			else:
				target = house.random_floor_pos()
				repath_t = 0.0
		stuck_t = 0.0
		stuck_pos = global_position
	return _nav_velocity(spd * speed_mult(), delta)


func _nav_velocity(spd: float, delta: float) -> Vector3:
	repath_t -= delta
	if repath_t <= 0.0 or agent.target_position.distance_to(target) > 1.5:
		agent.target_position = target
		repath_t = 0.4
	var next := agent.get_next_path_position()
	var dir := next - global_position
	dir.y = 0
	if dir.length() < 0.05:
		dir = target - global_position
		dir.y = 0
	if dir.length() < 0.1:
		return Vector3.ZERO
	dir = dir.normalized()
	_face(dir, delta)
	return dir * spd


# ------------------------------------------------------------------ animation
func _animate(delta: float) -> void:
	var walk := sin(anim * (13.0 if dash_t > 0.0 else 8.0))
	var mv := 1.0 if moving else 0.0
	model.position.y = absf(walk) * 0.07 * mv
	leg_l.rotation.x = walk * 0.5 * mv
	leg_r.rotation.x = -walk * 0.5 * mv
	arm_l.rotation.x = lerpf(arm_l.rotation.x, -walk * 0.5 * mv + 0.1, minf(1.0, 10.0 * delta))
	var arm_target := 0.35 + walk * 0.35 * mv
	var lean := -0.3 if dash_t > 0.0 else 0.0
	var wob := 0.0
	var disc_a := 0.0
	var glow := 0.6
	stars.visible = false
	match state:
		"windup":
			var k := clampf(state_t / windup_time(), 0.0, 1.0)
			arm_target = lerpf(0.4, 3.5, ease(k, 0.4))
			lean = 0.18 * k
			disc_a = 0.06 + 0.16 * k
			glow = 1.5 + 3.0 * k
			bat_mat.emission_energy_multiplier = 3.0 * k
		"swing":
			arm_target = lerpf(3.5, 1.2, clampf(state_t / 0.1, 0.0, 1.0))
			lean = -0.3
			disc_a = 0.25 * (1.0 - state_t / SWING)
			glow = 4.0
			bat_mat.emission_energy_multiplier = 2.0
		"stun":
			arm_target = 0.1
			wob = sin(anim * 9.0) * 0.18
			stars.visible = true
			stars.rotation.y += delta * 5.0
			glow = 0.1
		"chase":
			glow = 2.5
		"flinch":
			lean = 0.25
			wob = sin(anim * 30.0) * 0.08
		"wake":
			arm_target = 0.0
			glow = 0.2 + 0.2 * sin(anim * 3.0)
	if state != "windup" and state != "swing":
		bat_mat.emission_energy_multiplier = lerpf(bat_mat.emission_energy_multiplier, 0.0, minf(1.0, 6.0 * delta))
	var arm_speed := 30.0 if state == "swing" else 9.0
	arm_r.rotation.x = lerpf(arm_r.rotation.x, arm_target, minf(1.0, arm_speed * delta))
	model.rotation.x = lerpf(model.rotation.x, lean, minf(1.0, 8.0 * delta))
	model.rotation.z = wob
	disc.visible = disc_a > 0.01
	disc_mat.albedo_color.a = disc_a
	if rage:
		glow += 1.0
	eye_mat.emission_energy_multiplier = lerpf(eye_mat.emission_energy_multiplier, glow, minf(1.0, 6.0 * delta))
	eye_light.light_energy = 0.3 + glow * 0.35
	wood_mat.albedo_color = Color(0.8, 0.35, 0.25) if rage else Color(0.62, 0.42, 0.24)
