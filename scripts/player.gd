extends CharacterBody3D
## A survivor (first person). The local one reads input; remote ones interpolate.

const HouseScript := preload("res://scripts/house.gd")

const WALK := 3.3
const CROUCH := 1.7
const SPRINT := 5.8
const GHOST := 7.0
const JUMP := 5.5
const GRAVITY := 18.0
const STAND_EYE := 1.6
const CROUCH_EYE := 1.0
const STAMINA_MAX := 5.0

var game: Node
var pid := 0
var pname := ""
var color := Color.WHITE
var is_local := false
var alive := true
var mode := 0  # 0 walk, 1 crouch (silent), 2 sprint (loud)
var target_pos := Vector3.ZERO
var net_yaw := 0.0
var net_pitch := 0.0
var yaw := 0.0
var pitch := 0.0
var flashlight_on := true
var hidden := false
var weapon := 0  # 0 sword, 1 gun
var parrying := false
var stamina := STAMINA_MAX
var exhausted := false
var vulnerable_t := 0.0
var parry_anim := 0.0
var recoil := 0.0
var eye_h := STAND_EYE
var bob := 0.0
var spectate_id := -1
var fall_speed := 0.0

var head: Node3D
var cam: Camera3D
var flash: SpotLight3D
var viewmodel: Node3D
var vm_sword: Node3D
var vm_gun: Node3D
var body_model: Node3D
var held_sword: Node3D
var held_gun: Node3D
var hand: Node3D
var label: Label3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var body_mat: StandardMaterial3D


func setup(g: Node, id: int, n: String, c: Color, local: bool, pos: Vector3, start_yaw: float) -> void:
	game = g
	pid = id
	pname = n
	color = c
	is_local = local
	position = pos
	target_pos = pos
	yaw = start_yaw
	net_yaw = start_yaw
	rotation.y = start_yaw
	name = "P%d" % id


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(40)
	floor_snap_length = 0.4
	shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.75
	shape.shape = capsule
	shape.position = Vector3(0, 0.875, 0)
	add_child(shape)
	head = Node3D.new()
	head.position = Vector3(0, STAND_EYE, 0)
	add_child(head)
	flash = SpotLight3D.new()
	flash.light_color = Color(1.0, 0.95, 0.82)
	flash.spot_range = 22.0
	flash.spot_angle = 28.0
	flash.spot_attenuation = 1.1
	flash.spot_angle_attenuation = 0.6
	flash.light_energy = 2.4
	if is_local:
		cam = Camera3D.new()
		cam.fov = 75.0
		cam.near = 0.04
		cam.far = 120.0
		head.add_child(cam)
		cam.make_current()
		flash.position = Vector3(0.12, -0.12, 0)
		flash.shadow_enabled = true
		cam.add_child(flash)
		viewmodel = Node3D.new()
		viewmodel.position = Vector3(0.32, -0.3, -0.5)
		viewmodel.scale = Vector3(0.75, 0.75, 0.75)
		cam.add_child(viewmodel)
		vm_sword = Node3D.new()
		viewmodel.add_child(vm_sword)
		HouseScript.build_sword_mesh(vm_sword)
		vm_gun = Node3D.new()
		viewmodel.add_child(vm_gun)
		HouseScript.build_gun_mesh(vm_gun, {})
		for n in [vm_sword, vm_gun]:
			for mi in n.get_children():
				(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		flash.shadow_enabled = false
		flash.light_energy = 2.2
		flash.position = Vector3(0.0, 0.0, -0.3)
		head.add_child(flash)
		_build_body()


func _build_body() -> void:
	body_model = Node3D.new()
	add_child(body_model)
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = color
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.66, 0.5)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.12)
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.3
	var b := MeshInstance3D.new()
	b.mesh = cap
	b.material_override = body_mat
	b.position = Vector3(0, 0.75, 0)
	body_model.add_child(b)
	var hm := SphereMesh.new()
	hm.radius = 0.2
	hm.height = 0.4
	var h := MeshInstance3D.new()
	h.mesh = hm
	h.material_override = skin
	h.position = Vector3(0, 1.58, 0)
	body_model.add_child(h)
	for s in [-1, 1]:
		var em := SphereMesh.new()
		em.radius = 0.04
		em.height = 0.08
		var e := MeshInstance3D.new()
		e.mesh = em
		e.material_override = dark
		e.position = Vector3(s * 0.08, 1.62, -0.18)
		body_model.add_child(e)
	hand = Node3D.new()
	hand.position = Vector3(0.32, 1.05, -0.25)
	body_model.add_child(hand)
	held_sword = Node3D.new()
	held_sword.rotation.x = -1.1
	hand.add_child(held_sword)
	HouseScript.build_sword_mesh(held_sword)
	held_gun = Node3D.new()
	hand.add_child(held_gun)
	HouseScript.build_gun_mesh(held_gun, {})
	label = Label3D.new()
	label.text = pname
	label.font_size = 40
	label.pixel_size = 0.005
	label.outline_size = 8
	label.modulate = color.lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.05, 0)
	add_child(label)


func look(rel: Vector2) -> void:
	var s: float = Net.mouse_sens
	yaw -= rel.x * s
	pitch = clampf(pitch - rel.y * s, -1.45, 1.45)


func set_dead() -> void:
	alive = false
	hidden = false
	collision_mask = 0  # ghosts float through walls
	shape.disabled = true
	if body_model:
		body_model.visible = false
		flash.visible = false
	if label:
		label.text = pname + " (ghost)"
		label.modulate.a = 0.35
	if is_local:
		flash.shadow_enabled = false
		flash.spot_range = 30.0
		viewmodel.visible = false


func enter_hide(h: Dictionary) -> void:
	hidden = true
	shape.disabled = true
	global_position = h["pos"]
	velocity = Vector3.ZERO
	yaw = h["yaw"]
	pitch = 0.0


func exit_hide(h: Dictionary) -> void:
	hidden = false
	global_position = h["out"] + Vector3(0, 0.05, 0)
	shape.disabled = false


func play_parry() -> void:
	parry_anim = 1.0


func play_recoil() -> void:
	recoil = 1.0


func net_flags() -> int:
	return (1 if flashlight_on else 0) | (2 if hidden else 0) | (4 if weapon == 1 else 0) | (8 if parry_anim > 0.0 else 0)


func apply_flags(f: int) -> void:
	flashlight_on = f & 1 != 0
	hidden = f & 2 != 0
	weapon = 1 if f & 4 != 0 else 0
	if f & 8 != 0 and not parrying:
		parry_anim = 1.0
	parrying = f & 8 != 0


func _physics_process(delta: float) -> void:
	parry_anim = maxf(0.0, parry_anim - delta / 0.3)
	recoil = maxf(0.0, recoil - delta * 6.0)
	vulnerable_t = maxf(0.0, vulnerable_t - delta)
	if is_local:
		_local(delta)
	else:
		_remote(delta)


func _local(delta: float) -> void:
	rotation.y = yaw
	head.rotation.x = pitch
	flash.visible = flashlight_on
	if not alive:
		_ghost(delta)
		return
	if hidden:
		mode = 1
		velocity = Vector3.ZERO
		head.position.y = 1.5
		_viewmodel(delta, false)
		return
	var d := Vector3.ZERO
	var free: bool = game.over or game.mouse_free()
	if not free:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): d.z -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): d.z += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): d.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): d.x += 1
	var crouch := not free and (Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C))
	if not crouch and capsule.height < 1.7:
		# only stand up if there is room above
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.5, 0), global_position + Vector3(0, 1.9, 0), 1)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			crouch = true
	var want_sprint := not free and Input.is_physical_key_pressed(KEY_SHIFT) and not crouch and d != Vector3.ZERO
	if stamina <= 0.0:
		exhausted = true
	if exhausted and stamina > STAMINA_MAX * 0.35:
		exhausted = false
	var sprint := want_sprint and not exhausted
	if sprint:
		stamina = maxf(0.0, stamina - delta)
	else:
		stamina = minf(STAMINA_MAX, stamina + delta * 0.45)
	mode = 1 if crouch else (2 if sprint else 0)
	var spd := WALK
	if crouch:
		spd = CROUCH
	elif sprint:
		spd = SPRINT
	if vulnerable_t > 0.0:
		spd *= 0.55
	capsule.height = 1.1 if crouch else 1.75
	shape.position.y = capsule.height * 0.5
	eye_h = lerpf(eye_h, CROUCH_EYE if crouch else STAND_EYE, minf(1.0, 12.0 * delta))
	var wish := (Basis(Vector3.UP, yaw) * d).normalized() * spd
	var accel := 14.0 if is_on_floor() else 3.0
	velocity.x = lerpf(velocity.x, wish.x, minf(1.0, accel * delta))
	velocity.z = lerpf(velocity.z, wish.z, minf(1.0, accel * delta))
	if is_on_floor():
		fall_speed = 0.0
		if not free and Input.is_physical_key_pressed(KEY_SPACE) and not crouch:
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
		fall_speed = maxf(fall_speed, -velocity.y)
	move_and_slide()
	if global_position.y < -5.0:
		global_position = game.house.spawn_points[0] + Vector3(0, 0.5, 0)
	var hs := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hs > 0.5:
		bob += delta * hs * 2.2
	head.position.y = eye_h + sin(bob) * 0.035 * minf(hs / 3.0, 1.0)
	_viewmodel(delta, hs > 0.5)


func _viewmodel(delta: float, walking: bool) -> void:
	vm_sword.visible = weapon == 0 or parry_anim > 0.0
	vm_gun.visible = weapon == 1 and parry_anim <= 0.0 and game.my_inv["gun"]
	var sway := Vector3(sin(bob * 0.5) * 0.015, -absf(cos(bob * 0.5)) * 0.012, 0) if walking else Vector3.ZERO
	viewmodel.position = viewmodel.position.lerp(Vector3(0.36, -0.34, -0.55) + sway, minf(1.0, 12.0 * delta))
	# sword: rest = held up at the right, parry = sweep across the screen to block
	var k := sin(PI * (1.0 - parry_anim)) if parry_anim > 0.0 else 0.0
	vm_sword.position = Vector3(lerpf(0.05, -0.35, k), lerpf(-0.05, 0.2, k), lerpf(0.0, -0.1, k))
	vm_sword.rotation = Vector3(lerpf(-0.6, -0.1, k), lerpf(0.0, 0.4, k), lerpf(-0.45, 1.45, k))
	vm_gun.position = Vector3(0, 0, recoil * 0.08)
	vm_gun.rotation = Vector3(recoil * 0.35, 0, 0)


func _ghost(delta: float) -> void:
	mode = 0
	var free: bool = game.mouse_free()
	var d := Vector3.ZERO
	if not free:
		if Input.is_physical_key_pressed(KEY_W): d.z -= 1
		if Input.is_physical_key_pressed(KEY_S): d.z += 1
		if Input.is_physical_key_pressed(KEY_A): d.x -= 1
		if Input.is_physical_key_pressed(KEY_D): d.x += 1
	if d != Vector3.ZERO:
		spectate_id = -1
	if spectate_id != -1 and game.players.has(spectate_id) and game.alive.get(spectate_id, false):
		var t: Node3D = game.players[spectate_id]
		global_position = global_position.lerp(t.global_position + Vector3(0, 0.2, 0), minf(1.0, 10.0 * delta))
		yaw = lerp_angle(yaw, t.net_yaw, minf(1.0, 10.0 * delta))
		pitch = lerpf(pitch, t.net_pitch, minf(1.0, 10.0 * delta))
		head.position.y = 1.55
		return
	spectate_id = -1
	var up := 0.0
	if not free:
		if Input.is_physical_key_pressed(KEY_SPACE): up += 1
		if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C): up -= 1
	var dir := (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * d)
	velocity = (dir.normalized() * GHOST) + Vector3(0, up * GHOST * 0.7, 0)
	global_position += velocity * delta


func spectate_next() -> void:
	var ids: Array = []
	for id in game.players:
		if id != pid and game.alive.get(id, false):
			ids.append(id)
	ids.sort()
	if ids.is_empty():
		spectate_id = -1
		return
	var i := ids.find(spectate_id)
	spectate_id = ids[(i + 1) % ids.size()]


func _remote(delta: float) -> void:
	global_position = global_position.lerp(target_pos, minf(1.0, 15.0 * delta))
	rotation.y = lerp_angle(rotation.y, net_yaw, minf(1.0, 15.0 * delta))
	head.rotation.x = lerpf(head.rotation.x, net_pitch, minf(1.0, 15.0 * delta))
	if body_model == null:
		return
	body_model.visible = alive and not hidden
	flash.visible = alive and flashlight_on and not hidden
	label.visible = not hidden
	var crouch := mode == 1
	body_model.scale.y = lerpf(body_model.scale.y, 0.68 if crouch else 1.0, minf(1.0, 10.0 * delta))
	head.position.y = lerpf(head.position.y, CROUCH_EYE if crouch else STAND_EYE, minf(1.0, 10.0 * delta))
	held_gun.visible = weapon == 1 and parry_anim <= 0.0
	held_sword.visible = not held_gun.visible
	var k := sin(PI * (1.0 - parry_anim)) if parry_anim > 0.0 else 0.0
	held_sword.rotation = Vector3(lerpf(-1.1, -1.5, k), lerpf(0.0, 0.0, k), lerpf(0.0, 1.5, k))
	held_gun.rotation.x = net_pitch
