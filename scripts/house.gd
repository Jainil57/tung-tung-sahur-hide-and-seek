extends Node3D
## Builds the 3D two-storey house out of primitives (boxes / cylinders), with
## collision, a baked navigation mesh for Tung Tung, lamps, furniture and props.
##
## Map legend (one char = one cell, C metres):
##   # wall   . floor   S spawn   M Tung Tung   I takjil (collect!)
##   T trap pickup   Y decoy drum   G gun pickup   V vase (breaks = LOUD)
##   s squeaky floor   X front door (exit)   L ceiling lamp   ^ stairs (ground)
##   k kitchen counter   t table   b bed   c cabinet/bookshelf   x crates
##   W wardrobe (hide inside with E)   = railing   ' ' (upper) open stairwell

const C := 1.25          # cell size in metres
const F2 := 3.4          # height of the upper floor surface
const SLAB := 0.3        # floor slab thickness
const WALL_H := 3.4 - 0.3
const ROOF_Y := 6.5
const STAIR_X0 := 17     # ramp cells x 17..24, rows 11..13, rising toward +x
const STAIR_X1 := 25
const STAIR_Z0 := 11
const STAIR_Z1 := 14

const MAP_G: Array[String] = [
	"########################################",
	"#kkkkkk.....#S.........#c.c.c.c........#",
	"#...........#..........#.............S.#",
	"#..I..tt....#...bb..V..#...xx.....I....#",
	"#.....tt..V.#...bb.....#...xx..........#",
	"#...........#.....I....#..........cc...#",
	"#.L....T....#..L....W..#.L........cc...#",
	"#####..#######..########..######..######",
	"#......s.s...............M.............#",
	"#..Y......L.....................L......#",
	"######..########################..##..##",
	"#......#.......#.^^^^^^^^###.....#.....#",
	"#..I...#.......#.^^^^^^^^###..I..#..T..#",
	"#......#..tt...#.^^^^^^^^###.....#.....#",
	"#..W...#..tt...#.........#.......#..x..#",
	"#...L..#....V..#....L....#...L...#..x..#",
	"##..########..####..######..######.....#",
	"#......s.......................s.......#",
	"#..L...........................L....Y..#",
	"#......####..###.###..####..####...G...#",
	"#..V...#.....#.....#..#........#.......#",
	"#......#..I..#..T..#..#...I....#..c....#",
	"#S.....#.....#..L..#..#...L....#..c..S.#",
	"#......#..x..#.....#..#.....W..#.......#",
	"#..S...#.....#.....#..#........#.......#",
	"####XX##################################",
]
const MAP_U: Array[String] = [
	"########################################",
	"#bb.....W...#.........#.......#.......c#",
	"#bb.........#...I.....#..V....#..I....c#",
	"#...........#.........#.......#.......c#",
	"#....I......#..bb.....#..L....#...x...L#",
	"#.L.........#..bb..L..#.......#...x....#",
	"#.......V...#.........#..T....#........#",
	"####..#########..#######..#######..#####",
	"#..........s.s.......................s.#",
	"#...L...........L.................L....#",
	"#...............=========......xx......#",
	"#..Y....#.......=        ..L...........#",
	"#.......#..G....=        ..............#",
	"#..W....#.......=        .........V....#",
	"#...............=========..............#",
	"####..###..............L......####..####",
	"#..........#####..######..#####.......c#",
	"#..........#.........#.......#........c#",
	"#...I......#...bb....#...I...#....L....#",
	"#.L........#...bb....#.......#.........#",
	"#..........#.....L...#..W....#...x.....#",
	"#....V.....#.........#..L....#...x..I..#",
	"#..........#....W....#.......#.........#",
	"#..x.......#.........#.......#.........#",
	"#..........#.........#.......#.........#",
	"########################################",
]

const WALKABLE := ".SMITYGVsL"

var maps: Array = []
var W := 40
var H := 26
var nav: NavigationRegion3D
var world_body: StaticBody3D
var meshes: Node3D
var mats := {}
var env: Environment
var spawn_points: Array[Vector3] = []
var monster_spawn := Vector3(30, 0, 10)
var pickups: Array = []   # {"pos": Vector3, "kind": String, "node": Node3D}
var vases: Array = []     # {"pos": Vector3, "node": Node3D}
var squeaks := {}         # Vector3i(floor, x, z) -> true
var hides: Array = []     # {"pos": Vector3, "out": Vector3, "yaw": float}
var lamps: Array = []     # {"light": OmniLight3D, "mat": StandardMaterial3D, "base": float, "flick": bool}
var walk_cells: Array[Vector3i] = []
var exit_pos := Vector3.ZERO
var exit_door: Node3D
var exit_body: StaticBody3D
var exit_sign: Label3D
var rng := RandomNumberGenerator.new()
var dark_k := 1.0


func build() -> void:
	rng.seed = 1337
	maps = [MAP_G, MAP_U]
	H = MAP_G.size()
	W = MAP_G[0].length()
	_make_materials()
	_build_environment()
	nav = NavigationRegion3D.new()
	nav.name = "Nav"
	add_child(nav)
	world_body = StaticBody3D.new()
	world_body.name = "World"
	world_body.collision_layer = 1
	world_body.collision_mask = 0
	nav.add_child(world_body)
	meshes = Node3D.new()
	meshes.name = "Meshes"
	add_child(meshes)
	_build_slabs()
	for f in 2:
		_build_walls(f)
		_build_cells(f)
	_build_stairs()
	_build_exit()
	_build_outside()


func bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_height = 2.0
	nm.agent_radius = 0.5
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 35.0
	nm.filter_baking_aabb = AABB(Vector3(-1, -1, -1), Vector3(W * C + 2, 7.0, H * C + 9))
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


# ------------------------------------------------------------------ helpers
func ch(f: int, x: int, z: int) -> String:
	if x < 0 or z < 0 or x >= W or z >= H:
		return "#"
	return maps[f][z][x]


func cell_center(f: int, x: int, z: int) -> Vector3:
	return Vector3(x * C + C * 0.5, f * F2, z * C + C * 0.5)


func floor_of(y: float) -> int:
	return 1 if y > F2 * 0.6 else 0


func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floor_of(p.y), clampi(floori(p.x / C), 0, W - 1), clampi(floori(p.z / C), 0, H - 1))


func is_walk(f: int, x: int, z: int) -> bool:
	return WALKABLE.contains(ch(f, x, z))


func random_floor_pos() -> Vector3:
	var c: Vector3i = walk_cells[rng.randi() % walk_cells.size()]
	return cell_center(c.x, c.y, c.z)


func find_floor_near(p: Vector3) -> Vector3:
	var c := cell_of(p)
	var options: Array[Vector3] = []
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			if maxi(absi(dx), absi(dz)) >= 2 and is_walk(c.x, c.y + dx, c.z + dz):
				options.append(cell_center(c.x, c.y + dx, c.z + dz))
	if options.is_empty():
		return cell_center(c.x, c.y, c.z)
	return options[rng.randi() % options.size()]


func los(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func set_light_level(k: float) -> void:
	dark_k = k
	for l in lamps:
		var e: float = l["base"] * k
		l["light"].light_energy = e
		l["mat"].emission_energy_multiplier = 0.2 + 3.0 * k


# ------------------------------------------------------------------ materials / textures
func _img_tex(kind: String) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = hash(kind)
	match kind:
		"planks":
			var shade := []
			for i in 8:
				shade.append(r.randf_range(0.8, 1.15))
			for y in n:
				var row := int(y / 16)
				var off := (row * 37) % n
				for x in n:
					var grain := 0.06 * sin((x + off) * 0.21 + sin(y * 0.9 + row) * 2.0)
					var v: float = shade[row] * (0.9 + grain + r.randf() * 0.05)
					if y % 16 == 0 or (x + off) % 64 == 0:
						v *= 0.55
					img.set_pixel(x, y, Color(v, v, v))
		"wallpaper":
			for y in n:
				for x in n:
					var stripe := 1.0 if (x / 8) % 2 == 0 else 0.9
					var dots := 0.92 if ((x + 4) % 16 < 2 and (y + (x / 16) * 8) % 16 < 2) else 1.0
					var v := stripe * dots * (0.95 + r.randf() * 0.06)
					img.set_pixel(x, y, Color(v, v, v))
		"plaster":
			for y in n:
				for x in n:
					var v := 0.9 + r.randf() * 0.1 + 0.04 * sin(x * 0.11) * sin(y * 0.07)
					img.set_pixel(x, y, Color(v, v, v))
		"wood":
			for y in n:
				for x in n:
					var v := 0.85 + 0.12 * sin(x * 0.35 + 3.0 * sin(y * 0.05)) + r.randf() * 0.05
					img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _mat(col: Color, tex: Texture2D = null, scale := 0.6, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	return m


func _glow(col: Color, e := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = e
	return m


func _make_materials() -> void:
	var planks := _img_tex("planks")
	var paper := _img_tex("wallpaper")
	var plaster := _img_tex("plaster")
	var wood := _img_tex("wood")
	mats["floor"] = _mat(Color(0.5, 0.36, 0.24), planks, 0.5)
	mats["floor2"] = _mat(Color(0.42, 0.3, 0.22), planks, 0.5)
	mats["squeak"] = _mat(Color(0.62, 0.48, 0.32), planks, 0.9)
	mats["wall"] = _mat(Color(0.55, 0.6, 0.5), paper, 0.45)
	mats["wall2"] = _mat(Color(0.62, 0.45, 0.42), paper, 0.45)
	mats["ceiling"] = _mat(Color(0.5, 0.48, 0.45), plaster, 0.3)
	mats["wood"] = _mat(Color(0.45, 0.28, 0.15), wood, 1.2)
	mats["darkwood"] = _mat(Color(0.25, 0.15, 0.08), wood, 1.2)
	mats["white"] = _mat(Color(0.85, 0.85, 0.8))
	mats["blue"] = _mat(Color(0.25, 0.35, 0.6))
	mats["red"] = _mat(Color(0.6, 0.15, 0.12))
	mats["metal"] = _mat(Color(0.6, 0.62, 0.66), null, 1.0, 0.35)
	mats["metal"].metallic = 0.7
	mats["counter"] = _mat(Color(0.8, 0.78, 0.72), plaster, 1.0, 0.5)
	mats["crate"] = _mat(Color(0.55, 0.42, 0.25), wood, 0.9)
	mats["ground"] = _mat(Color(0.12, 0.16, 0.1), plaster, 0.2)
	mats["vase"] = _mat(Color(0.25, 0.45, 0.8), null, 1.0, 0.25)
	mats["takjil"] = _glow(Color(1.0, 0.75, 0.15), 1.2)
	mats["takjil2"] = _glow(Color(0.9, 0.2, 0.2), 0.8)
	mats["green"] = _glow(Color(0.2, 1.0, 0.4), 2.0)


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.32)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.02, 0.035)
	env.fog_density = 0.03
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	we.environment = env
	add_child(we)


# ------------------------------------------------------------------ geometry builders
func _mesh(m: Mesh, pos: Vector3, mat: Material, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	(parent if parent else meshes).add_child(mi)
	return mi


func _box(size: Vector3, center: Vector3, mat: Material, collide := true, parent: Node3D = null) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := _mesh(bm, center, mat, parent)
	if collide:
		_col_box(size, center)
	return mi


func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, parent: Node3D = null, segs := 16) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return _mesh(cm, pos, mat, parent)


func _sphere(r: float, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	return _mesh(sm, pos, mat, parent)


func _col_box(size: Vector3, center: Vector3, body: StaticBody3D = null) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = center
	(body if body else world_body).add_child(cs)


## Greedy rectangle cover of the cells where mask(x, z) is true, inside chunks so
## every mesh stays small (GL Compatibility lights only affect a few lights per mesh).
func _rects(mask: Callable, chunk := 5) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for cz in range(0, H, chunk):
		for cx in range(0, W, chunk):
			var used := {}
			var x1 := mini(cx + chunk, W)
			var z1 := mini(cz + chunk, H)
			for z in range(cz, z1):
				for x in range(cx, x1):
					if used.has(Vector2i(x, z)) or not mask.call(x, z):
						continue
					var w := 1
					while x + w < x1 and mask.call(x + w, z) and not used.has(Vector2i(x + w, z)):
						w += 1
					var h := 1
					var grow := true
					while grow and z + h < z1:
						for i in w:
							if not mask.call(x + i, z + h) or used.has(Vector2i(x + i, z + h)):
								grow = false
								break
						if grow:
							h += 1
					for dz in h:
						for dx in w:
							used[Vector2i(x + dx, z + dz)] = true
					out.append(Rect2i(x, z, w, h))
	return out


func _build_slabs() -> void:
	# ground floor
	for r in _rects(func(_x, _z): return true, 6):
		var sz := Vector3(r.size.x * C, SLAB, r.size.y * C)
		var c := Vector3((r.position.x + r.size.x * 0.5) * C, -SLAB * 0.5, (r.position.y + r.size.y * 0.5) * C)
		_box(sz, c, mats["floor"])
	# upper floor slab (+ a ceiling-coloured skin underneath for the ground floor)
	for r in _rects(func(x, z): return ch(1, x, z) != " ", 5):
		var sz := Vector3(r.size.x * C, SLAB, r.size.y * C)
		var c := Vector3((r.position.x + r.size.x * 0.5) * C, F2 - SLAB * 0.5, (r.position.y + r.size.y * 0.5) * C)
		_box(sz, c, mats["floor2"])
		_box(Vector3(sz.x, 0.02, sz.z), c - Vector3(0, SLAB * 0.5 + 0.011, 0), mats["ceiling"], false)
	# roof
	for r in _rects(func(_x, _z): return true, 6):
		var sz := Vector3(r.size.x * C, 0.2, r.size.y * C)
		var c := Vector3((r.position.x + r.size.x * 0.5) * C, ROOF_Y + 0.1, (r.position.y + r.size.y * 0.5) * C)
		_box(sz, c, mats["ceiling"])


func _build_walls(f: int) -> void:
	var y0 := 0.0 if f == 0 else F2
	var y1 := F2 - SLAB if f == 0 else ROOF_Y
	var mat: Material = mats["wall"] if f == 0 else mats["wall2"]
	for r in _rects(func(x, z): return ch(f, x, z) == "#", 6):
		var sz := Vector3(r.size.x * C, y1 - y0, r.size.y * C)
		var c := Vector3((r.position.x + r.size.x * 0.5) * C, (y0 + y1) * 0.5, (r.position.y + r.size.y * 0.5) * C)
		_box(sz, c, mat)
	# lintels over doorways (visual only, above head height)
	for z in H:
		for x in W:
			if not is_walk(f, x, z):
				continue
			var horiz := ch(f, x - 1, z) == "#" and ch(f, x + 1, z) == "#"
			var vert := ch(f, x, z - 1) == "#" and ch(f, x, z + 1) == "#"
			if horiz != vert:
				var cc := cell_center(f, x, z)
				_box(Vector3(C, y1 - y0 - 2.55, C), Vector3(cc.x, y0 + 2.55 + (y1 - y0 - 2.55) * 0.5, cc.z), mat, false)


func _build_cells(f: int) -> void:
	for z in H:
		for x in W:
			var c: String = ch(f, x, z)
			var p := cell_center(f, x, z)
			if WALKABLE.contains(c):
				walk_cells.append(Vector3i(f, x, z))
			match c:
				"S":
					spawn_points.append(p)
				"M":
					monster_spawn = p
				"I":
					pickups.append({"pos": p, "kind": "item", "node": _make_takjil(p)})
				"T":
					pickups.append({"pos": p, "kind": "trap", "node": _make_trap(p, true)})
				"Y":
					pickups.append({"pos": p, "kind": "decoy", "node": _make_drum(p)})
				"G":
					pickups.append({"pos": p, "kind": "gun", "node": _make_gun_pickup(p)})
				"V":
					vases.append({"pos": p, "node": _make_vase(p)})
				"s":
					squeaks[Vector3i(f, x, z)] = true
					_box(Vector3(C * 0.96, 0.02, C * 0.96), p + Vector3(0, 0.01, 0), mats["squeak"], false)
				"L":
					_make_lamp(p + Vector3(0, (F2 - SLAB if f == 0 else ROOF_Y - F2) - 0.15, 0))
				"k":
					_box(Vector3(C, 0.92, C * 0.9), p + Vector3(0, 0.46, 0), mats["counter"])
					_box(Vector3(C * 0.9, 0.5, 0.05), p + Vector3(0, 0.4, C * 0.46), mats["wood"], false)
				"t":
					_box(Vector3(C, 0.08, C), p + Vector3(0, 0.76, 0), mats["wood"], false)
					for sx in [-1, 1]:
						for sz in [-1, 1]:
							_box(Vector3(0.08, 0.72, 0.08), p + Vector3(sx * C * 0.42, 0.36, sz * C * 0.42), mats["darkwood"], false)
					_col_box(Vector3(C, 0.8, C), p + Vector3(0, 0.4, 0))
				"b":
					_box(Vector3(C, 0.4, C), p + Vector3(0, 0.2, 0), mats["darkwood"])
					_box(Vector3(C * 0.96, 0.16, C * 0.96), p + Vector3(0, 0.48, 0), mats["white"], false)
					_box(Vector3(C * 0.96, 0.05, C * 0.7), p + Vector3(0, 0.58, C * 0.12), mats["blue"], false)
				"c":
					_box(Vector3(C * 0.95, 2.0, C * 0.6), p + Vector3(0, 1.0, 0), mats["darkwood"])
					for i in 3:
						var y := 0.45 + i * 0.55
						for j in 4:
							var bc: Material = [mats["red"], mats["blue"], mats["white"], mats["wood"]][(i + j + x) % 4]
							_box(Vector3(0.16, 0.36, 0.05), p + Vector3(-0.4 + j * 0.25, y + 0.18, C * 0.31), bc, false)
				"x":
					_box(Vector3(C * 0.9, 0.9, C * 0.9), p + Vector3(0, 0.45, 0), mats["crate"])
					if (x + z) % 2 == 0:
						_box(Vector3(C * 0.6, 0.6, C * 0.6), p + Vector3(0.05, 1.2, -0.05), mats["crate"])
				"W":
					_make_wardrobe(f, x, z, p)
				"=":
					var along_x := ch(f, x - 1, z) == "=" or ch(f, x + 1, z) == "="
					var sz := Vector3(C, 0.08, 0.12) if along_x else Vector3(0.12, 0.08, C)
					_box(sz, p + Vector3(0, 1.0, 0), mats["wood"], false)
					_box(Vector3(0.1, 1.0, 0.1), p + Vector3(0, 0.5, 0), mats["darkwood"], false)
					_col_box(Vector3(C, 1.1, C) if not along_x else Vector3(C, 1.1, 0.4), p + Vector3(0, 0.55, 0))


func _make_lamp(p: Vector3) -> void:
	var cord := _box(Vector3(0.02, 0.5, 0.02), p + Vector3(0, 0.25, 0), mats["darkwood"], false)
	cord.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulb_mat := _glow(Color(1.0, 0.8, 0.5), 3.0)
	var shade := _cyl(0.12, 0.3, 0.2, p + Vector3(0, -0.02, 0), mats["darkwood"], null, 12)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var b := _sphere(0.09, p + Vector3(0, -0.14, 0), bulb_mat)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.position = p + Vector3(0, -0.35, 0)
	l.light_color = Color(1.0, 0.72, 0.42)
	l.omni_range = 7.5
	l.omni_attenuation = 1.3
	var base := rng.randf_range(0.9, 1.3)
	l.light_energy = base
	meshes.add_child(l)
	lamps.append({"light": l, "mat": bulb_mat, "base": base, "flick": rng.randf() < 0.3})


func _make_wardrobe(f: int, x: int, z: int, p: Vector3) -> void:
	var out := p
	var dir := Vector3(0, 0, 1)
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if is_walk(f, x + d.x, z + d.y):
			out = cell_center(f, x + d.x, z + d.y)
			dir = Vector3(d.x, 0, d.y)
			break
	_box(Vector3(C * 0.95, 2.3, C * 0.95), p + Vector3(0, 1.15, 0), mats["darkwood"])
	# doors + handles on the open side
	var fp := p + dir * (C * 0.48)
	var side := Vector3(dir.z, 0, -dir.x)
	var door_sz := Vector3(0.04, 2.0, C * 0.44) if absf(dir.x) > 0.5 else Vector3(C * 0.44, 2.0, 0.04)
	for s in [-1, 1]:
		_box(door_sz, fp + side * (s * C * 0.23) + Vector3(0, 1.1, 0), mats["wood"], false)
		_sphere(0.04, fp + dir * 0.03 + side * (s * 0.07) + Vector3(0, 1.1, 0), mats["metal"])
	hides.append({"pos": p + Vector3(0, 0.0, 0), "out": out, "yaw": atan2(-dir.x, -dir.z)})


func _make_takjil(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	meshes.add_child(n)
	var holder := Node3D.new()
	holder.name = "Spin"
	holder.position = Vector3(0, 0.55, 0)
	n.add_child(holder)
	_box(Vector3(0.34, 0.2, 0.26), Vector3.ZERO, mats["takjil"], false, holder)
	_box(Vector3(0.36, 0.04, 0.06), Vector3(0, 0.0, 0), mats["takjil2"], false, holder)
	_box(Vector3(0.06, 0.22, 0.28), Vector3(0, 0, 0), mats["takjil2"], false, holder)
	_box(Vector3(0.3, 0.5, 0.3), Vector3(0, 0.25, 0), mats["darkwood"], false, n)  # little stool
	return n


func _make_trap(p: Vector3, pickup: bool) -> Node3D:
	var n := Node3D.new()
	n.position = p
	meshes.add_child(n)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.22
	tm.outer_radius = 0.3
	_mesh(tm, Vector3(0, 0.05, 0), mats["metal"], n)
	for i in 8:
		var a := i * TAU / 8.0
		var spike := _box(Vector3(0.03, 0.14, 0.03), Vector3(cos(a) * 0.22, 0.1, sin(a) * 0.22), mats["metal"], false, n)
		spike.rotation.z = 0.3
	if pickup:
		_box(Vector3(0.3, 0.5, 0.3), Vector3(0, -0.5 + 0.25, 0), mats["darkwood"], false, n)
		n.position.y += 0.5
	return n


func _make_drum(p: Vector3) -> Node3D:  # bedug drum = decoy
	var n := Node3D.new()
	n.position = p
	meshes.add_child(n)
	var d := _cyl(0.22, 0.22, 0.4, Vector3(0, 0.25, 0), mats["red"], n)
	d.rotation.z = PI / 2
	var h := _cyl(0.2, 0.2, 0.42, Vector3(0, 0.25, 0), mats["white"], n)
	h.rotation.z = PI / 2
	h.scale = Vector3(1, 1, 1)
	return n


func _make_gun_pickup(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	meshes.add_child(n)
	_box(Vector3(0.6, 0.06, 0.4), Vector3(0, 0.8, 0), mats["wood"], false, n)  # small table
	_box(Vector3(0.06, 0.8, 0.06), Vector3(0, 0.4, 0), mats["darkwood"], false, n)
	var g := Node3D.new()
	g.name = "Spin"
	g.position = Vector3(0, 1.0, 0)
	n.add_child(g)
	build_gun_mesh(g, mats)
	return n


static func build_gun_mesh(parent: Node3D, m: Dictionary) -> void:
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.15, 0.17)
	dark.metallic = 0.6
	dark.roughness = 0.4
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.35, 0.2, 0.1)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.2, 1.0, 0.5)
	accent.emission_enabled = true
	accent.emission = Color(0.2, 1.0, 0.5)
	var parts := [
		[Vector3(0.07, 0.09, 0.42), Vector3(0, 0, -0.1), dark],
		[Vector3(0.06, 0.16, 0.08), Vector3(0, -0.11, 0.06), grip],
		[Vector3(0.04, 0.04, 0.2), Vector3(0, 0.01, -0.38), dark],
		[Vector3(0.075, 0.02, 0.1), Vector3(0, 0.055, -0.05), accent],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[0]
		mi.mesh = bm
		mi.position = pt[1]
		mi.material_override = pt[2]
		parent.add_child(mi)


static func build_sword_mesh(parent: Node3D) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.8, 0.82, 0.88)
	steel.metallic = 0.8
	steel.roughness = 0.25
	steel.emission_enabled = true
	steel.emission = Color(0.5, 0.55, 0.65)
	steel.emission_energy_multiplier = 0.25
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.85, 0.65, 0.2)
	gold.metallic = 0.6
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.3, 0.12, 0.08)
	var parts := [
		[Vector3(0.05, 0.75, 0.015), Vector3(0, 0.5, 0), steel],
		[Vector3(0.22, 0.04, 0.05), Vector3(0, 0.12, 0), gold],
		[Vector3(0.04, 0.2, 0.04), Vector3(0, 0.0, 0), grip],
		[Vector3(0.06, 0.05, 0.06), Vector3(0, -0.11, 0), gold],
	]
	for pt in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = pt[0]
		mi.mesh = bm
		mi.position = pt[1]
		mi.material_override = pt[2]
		parent.add_child(mi)


func _make_vase(p: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = p
	meshes.add_child(n)
	_box(Vector3(0.4, 0.6, 0.4), Vector3(0, 0.3, 0), mats["darkwood"], false, n)
	_sphere(0.18, Vector3(0, 0.78, 0), mats["vase"], n)
	_cyl(0.08, 0.1, 0.18, Vector3(0, 1.0, 0), mats["vase"], n, 10)
	return n


func _build_stairs() -> void:
	var x0 := STAIR_X0 * C
	var x1 := STAIR_X1 * C
	var z0 := STAIR_Z0 * C
	var z1 := STAIR_Z1 * C
	var n := 14
	var d := (x1 - x0) / n
	var rise := F2 / n
	for i in n:
		var top := (i + 0.5) * rise
		_box(Vector3(d, top, z1 - z0), Vector3(x0 + (i + 0.5) * d, top * 0.5, (z0 + z1) * 0.5), mats["wood"] if i % 2 == 0 else mats["floor"], false)
	# smooth wedge collider (so walking up is smooth and nobody gets under it)
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = PackedVector3Array([
		Vector3(x0 - 0.05, 0, z0), Vector3(x1, 0, z0), Vector3(x1, F2, z0),
		Vector3(x0 - 0.05, 0, z1), Vector3(x1, 0, z1), Vector3(x1, F2, z1)])
	cs.shape = sh
	world_body.add_child(cs)
	# banister on the open side
	var L := sqrt((x1 - x0) * (x1 - x0) + F2 * F2)
	var rail := _box(Vector3(L, 0.08, 0.08), Vector3((x0 + x1) * 0.5, F2 * 0.5 + 0.95, z1 - 0.05), mats["darkwood"], false)
	rail.rotation.z = atan2(F2, x1 - x0)
	for i in range(0, n, 3):
		var top := (i + 0.5) * rise
		_box(Vector3(0.06, 0.95, 0.06), Vector3(x0 + (i + 0.5) * d, top + 0.47, z1 - 0.05), mats["darkwood"], false)


func _build_exit() -> void:
	var xs: Array[int] = []
	for x in W:
		if ch(0, x, H - 1) == "X":
			xs.append(x)
	if xs.is_empty():
		return
	var cx := (xs[0] + xs[-1] + 1) * 0.5 * C
	var wz := (H - 0.5) * C
	var width := xs.size() * C
	exit_pos = Vector3(cx, 0, H * C + 1.2)
	# lintel above the door
	_box(Vector3(width, F2 - SLAB - 2.6, C), Vector3(cx, 2.6 + (F2 - SLAB - 2.6) * 0.5, wz), mats["wall"])
	exit_body = StaticBody3D.new()
	exit_body.collision_layer = 1
	nav.add_child(exit_body)
	_col_box(Vector3(width, 2.6, C), Vector3(cx, 1.3, wz), exit_body)
	exit_door = Node3D.new()  # hinge on the left edge
	exit_door.position = Vector3(cx - width * 0.5, 0, wz - C * 0.3)
	meshes.add_child(exit_door)
	var red := _mat(Color(0.45, 0.12, 0.08), mats["wood"].albedo_texture, 1.2)
	_box(Vector3(width, 2.6, 0.12), Vector3(width * 0.5, 1.3, 0), red, false, exit_door)
	_sphere(0.06, Vector3(width - 0.2, 1.2, -0.08), mats["metal"], exit_door)
	exit_sign = Label3D.new()
	exit_sign.text = "PINTU DEPAN\n(locked - find the takjil!)"
	exit_sign.font_size = 48
	exit_sign.pixel_size = 0.005
	exit_sign.modulate = Color(1, 0.4, 0.3)
	exit_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	exit_sign.position = Vector3(cx, 2.75, wz - C * 0.8)
	meshes.add_child(exit_sign)


func open_exit() -> void:
	if is_instance_valid(exit_body):
		exit_body.queue_free()
	if exit_door:
		var tw := create_tween()
		tw.tween_property(exit_door, "rotation:y", -1.9, 1.2).set_trans(Tween.TRANS_BACK)
	if exit_sign:
		exit_sign.text = "EXIT - RUN!"
		exit_sign.modulate = Color(0.3, 1, 0.4)
	var l := OmniLight3D.new()
	l.light_color = Color(0.3, 1.0, 0.45)
	l.light_energy = 2.0
	l.omni_range = 6.0
	l.position = exit_pos + Vector3(0, 1.5, 0)
	meshes.add_child(l)


func _build_outside() -> void:
	# porch / front yard (the escape zone)
	_box(Vector3(W * C + 16, 0.3, 10), Vector3(W * C * 0.5, -0.15, H * C + 5), mats["ground"])
	_box(Vector3(W * C + 16, 0.3, 10), Vector3(W * C * 0.5, -0.15, -5), mats["ground"])
	_box(Vector3(8, 0.3, H * C), Vector3(-4, -0.15, H * C * 0.5), mats["ground"])
	_box(Vector3(8, 0.3, H * C), Vector3(W * C + 4, -0.15, H * C * 0.5), mats["ground"])
	var post := Vector3(exit_pos.x + 3.0, 0, exit_pos.z + 1.5)
	_box(Vector3(0.12, 3.0, 0.12), post + Vector3(0, 1.5, 0), mats["darkwood"], false)
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.7, 1.0)
	l.light_energy = 1.0
	l.omni_range = 8.0
	l.position = post + Vector3(0, 3.0, 0)
	meshes.add_child(l)
	_sphere(0.12, post + Vector3(0, 3.0, 0), _glow(Color(0.7, 0.8, 1.0), 2.0))
