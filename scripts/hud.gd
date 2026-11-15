extends CanvasLayer
## In-game HUD: takjil count, noise meter (game noise + mic), stamina, weapon, parry
## cooldown, Tung Tung ability warnings, prompts, controls help, pause + game over.

const MonsterScript := preload("res://scripts/monster.gd")

var game: Node
var lbl_items: Label
var lbl_inv: Label
var lbl_weapon: Label
var lbl_time: Label
var lbl_abil: Label
var lbl_help: Label
var lbl_msg: Label
var lbl_small: Label
var lbl_warn: Label
var lbl_prompt: Label
var cross: Label
var bar_stam: ProgressBar
var bar_noise: ProgressBar
var bar_mic: ProgressBar
var bar_parry: ProgressBar
var lab_stam: Label
var lab_noise: Label
var lab_mic: Label
var lab_parry: Label
var red: ColorRect
var hide_ov: ColorRect
var pause_panel: PanelContainer
var over_panel: PanelContainer
var over_lbl: Label
var msg_t := 0.0
var small_t := 0.0
var t := 0.0
var help_on := true


func _lbl(parent: Node, fsize: int, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Node, title: String, col: Color) -> Array:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var l := _lbl(row, 15)
	l.text = title
	l.custom_minimum_size = Vector2(170, 0)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(180, 16)
	b.max_value = 1.0
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	return [l, b]


func setup(g: Node) -> void:
	game = g
	layer = 10
	red = ColorRect.new()
	red.color = Color(0.8, 0.0, 0.0, 0.0)
	red.set_anchors_preset(Control.PRESET_FULL_RECT)
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(red)
	hide_ov = ColorRect.new()
	hide_ov.color = Color(0.02, 0.01, 0.0, 0.6)
	hide_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	hide_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide_ov.visible = false
	add_child(hide_ov)
	var box := VBoxContainer.new()
	box.position = Vector2(18, 12)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	lbl_items = _lbl(box, 26, Color(1, 0.85, 0.35))
	lbl_inv = _lbl(box, 16)
	lbl_weapon = _lbl(box, 16)
	var bottom := VBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 18
	bottom.offset_top = -150
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var r := _bar(bottom, "Stamina", Color(0.3, 0.8, 1.0))
	lab_stam = r[0]
	bar_stam = r[1]
	r = _bar(bottom, "Noise", Color(1.0, 0.55, 0.2))
	lab_noise = r[0]
	bar_noise = r[1]
	r = _bar(bottom, "Mic", Color(0.7, 0.7, 0.7))
	lab_mic = r[0]
	bar_mic = r[1]
	r = _bar(bottom, "Parry", Color(1.0, 0.9, 0.3))
	lab_parry = r[0]
	bar_parry = r[1]
	lbl_time = _lbl(self, 20)
	lbl_time.anchor_left = 1.0
	lbl_time.anchor_right = 1.0
	lbl_time.offset_left = -360
	lbl_time.offset_right = -18
	lbl_time.offset_top = 12
	lbl_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_abil = _lbl(self, 16, Color(1, 0.75, 0.6))
	lbl_abil.anchor_left = 1.0
	lbl_abil.anchor_right = 1.0
	lbl_abil.offset_left = -360
	lbl_abil.offset_right = -18
	lbl_abil.offset_top = 44
	lbl_abil.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cross = _lbl(self, 22)
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -7
	cross.offset_top = -16
	lbl_prompt = _lbl(self, 20, Color(0.85, 1, 0.85))
	lbl_prompt.anchor_left = 0.0
	lbl_prompt.anchor_right = 1.0
	lbl_prompt.anchor_top = 0.5
	lbl_prompt.anchor_bottom = 0.5
	lbl_prompt.offset_top = 40
	lbl_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_warn = _lbl(self, 34, Color(1, 0.25, 0.2))
	lbl_warn.anchor_left = 0.0
	lbl_warn.anchor_right = 1.0
	lbl_warn.anchor_top = 0.5
	lbl_warn.anchor_bottom = 0.5
	lbl_warn.offset_top = -120
	lbl_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg = _lbl(self, 28)
	lbl_msg.anchor_left = 0.0
	lbl_msg.anchor_right = 1.0
	lbl_msg.offset_top = 110
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_small = _lbl(self, 18, Color(1, 0.85, 0.5))
	lbl_small.anchor_left = 0.0
	lbl_small.anchor_right = 1.0
	lbl_small.anchor_top = 0.5
	lbl_small.anchor_bottom = 0.5
	lbl_small.offset_top = 75
	lbl_small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_help = _lbl(self, 14, Color(0.8, 0.8, 0.8))
	lbl_help.anchor_top = 1.0
	lbl_help.anchor_bottom = 1.0
	lbl_help.anchor_left = 0.0
	lbl_help.anchor_right = 1.0
	lbl_help.offset_top = -44
	lbl_help.offset_left = 400
	lbl_help.offset_right = -18
	lbl_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_help.autowrap_mode = TextServer.AUTOWRAP_WORD
	if game.is_monster():
		lbl_help.text = "WASD move  Mouse look  LMB bat swing  Q Kentongan Dash  E Sahur Call  R Teleport to noise  X Lampu Mati  H hide help  Esc menu"
	else:
		lbl_help.text = "WASD move  Mouse look  Shift sprint (LOUD)  Ctrl/C crouch (silent)  Space jump  E pick up / hide  F flashlight\nLMB use weapon  RMB sword PARRY  1/2 or wheel switch weapon  G place trap  Q throw decoy  H hide help  Esc menu"
	_build_pause()
	_build_over()


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.04, 0.04, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(24)
	sb.border_color = Color(0.95, 0.6, 0.25)
	sb.set_border_width_all(2)
	return sb


func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.add_theme_stylebox_override("panel", _panel_style())
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	pause_panel.visible = false
	add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(360, 0)
	pause_panel.add_child(v)
	var t1 := _lbl(v, 30, Color(0.95, 0.6, 0.25))
	t1.text = "PAUSED (game keeps running!)"
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sl := _lbl(v, 15)
	sl.text = "Mouse sensitivity"
	var sens := HSlider.new()
	sens.min_value = 0.0005
	sens.max_value = 0.008
	sens.step = 0.0001
	sens.value = Net.mouse_sens
	sens.value_changed.connect(func(val): Net.mouse_sens = val)
	v.add_child(sens)
	var mic := CheckBox.new()
	mic.text = "Use microphone"
	mic.button_pressed = Mic.enabled
	mic.toggled.connect(func(on): Mic.set_enabled(on))
	v.add_child(mic)
	var res := Button.new()
	res.text = "Resume"
	res.pressed.connect(func(): game.set_paused(false))
	v.add_child(res)
	var lv := Button.new()
	lv.text = "Leave to main menu"
	lv.pressed.connect(func(): game.leave())
	v.add_child(lv)


func _build_over() -> void:
	over_panel = PanelContainer.new()
	over_panel.add_theme_stylebox_override("panel", _panel_style())
	over_panel.set_anchors_preset(Control.PRESET_CENTER)
	over_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	over_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	over_panel.visible = false
	add_child(over_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 14)
	over_panel.add_child(ov)
	over_lbl = _lbl(ov, 34)
	over_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var again := Button.new()
	again.text = "Play Again" if multiplayer.is_server() else "Waiting for host to restart..."
	again.disabled = not multiplayer.is_server()
	again.pressed.connect(func(): Net.start_game())
	ov.add_child(again)
	var menu := Button.new()
	menu.text = "Main Menu"
	menu.pressed.connect(func(): game.leave())
	ov.add_child(menu)


func msg(text: String, dur := 3.0) -> void:
	lbl_msg.text = text
	msg_t = dur


func small(text: String, dur := 2.5) -> void:
	lbl_small.text = text
	small_t = dur


func toggle_help() -> void:
	help_on = not help_on
	lbl_help.visible = help_on


func show_pause(v: bool) -> void:
	pause_panel.visible = v


func game_over(text: String) -> void:
	over_lbl.text = text
	over_panel.visible = true
	pause_panel.visible = false


func _fmt(s: float) -> String:
	if s <= 0.0:
		return "READY"
	return "%ds" % int(ceil(s))


func update(delta: float) -> void:
	t += delta
	var exit_txt := "   DOOR OPEN - ESCAPE!" if game.exit_open else ""
	lbl_items.text = "Takjil: %d / %d%s" % [game.items_got, game.items_needed, exit_txt]
	var alive_n := 0
	for id in game.alive:
		if game.alive[id]:
			alive_n += 1
	lbl_time.text = "%d:%02d    Survivors: %d" % [int(game.elapsed) / 60, int(game.elapsed) % 60, alive_n]
	var mon: Node = game.monster
	var st: String = mon.state if mon else ""
	var immune: bool = game.mon_flags & 2 != 0 if not multiplayer.is_server() else mon.immune_t > 0.0
	# abilities
	if game.is_monster():
		lbl_inv.text = "You are TUNG TUNG SAHUR" + ("  (ENRAGED)" if mon.rage else "")
		lbl_weapon.text = "Red ? = noise you heard.  Stunned: %s" % ("YES" if st == "stun" else "no")
		lbl_abil.text = "[LMB] Bat swing\n[Q] Kentongan Dash: %s\n[E] Sahur Call: %s\n[R] Teleport: %s\n[X] Lampu Mati: %s" % [
			mon.ability_text("dash"), mon.ability_text("call"), mon.ability_text("tele"), mon.ability_text("dark")]
	else:
		var inv: Dictionary = game.my_inv
		lbl_inv.text = "Bear traps [G]: %d     Decoy drums [Q]: %d" % [inv["trap"], inv["decoy"]]
		var m: Node = game.me()
		var w: int = m.weapon if m else 0
		var sword := "[1] SWORD" if w == 0 else "1 sword"
		var gun := "no gun (find one!)"
		if inv["gun"]:
			gun = ("[2] FLARE PISTOL" if w == 1 else "2 flare pistol") + "  x%d" % inv["ammo"]
		lbl_weapon.text = "Weapon:  %s   |   %s" % [sword, gun]
		var a := "TUNG TUNG ABILITIES\n"
		a += "Sahur Call (reveals you): %s\n" % _fmt(game.ability_ready_in("call"))
		a += "Lampu Mati (blackout): %s\n" % ("ACTIVE" if game.dark_t > 0.0 else _fmt(game.ability_ready_in("dark")))
		a += "Teleport to noise: %s\n" % _fmt(game.ability_ready_in("tele"))
		a += "Dash: %s\n" % _fmt(game.ability_ready_in("dash"))
		if st == "stun":
			a += "STATUS: STUNNED!"
		elif immune:
			a += "STATUS: stun-immune"
		elif mon and mon.rage:
			a += "STATUS: ENRAGED"
		lbl_abil.text = a
	# bars
	var me: Node = game.me()
	if me:
		bar_stam.value = me.stamina / me.STAMINA_MAX
		lab_stam.text = "Stamina" + (" (tired!)" if me.exhausted else "")
		bar_stam.modulate = Color(1, 0.4, 0.4) if me.exhausted else Color.WHITE
		var lock := maxf(game.PARRY_CD, game.PARRY_FAIL_LOCK)
		if me.vulnerable_t > 0.0:
			lab_parry.text = "Parry: OPEN! (missed)"
			bar_parry.value = 0.0
			bar_parry.modulate = Color(1, 0.3, 0.3)
		elif game.parry_cd_t > 0.0:
			lab_parry.text = "Parry: %.1fs" % game.parry_cd_t
			bar_parry.value = 1.0 - game.parry_cd_t / lock
			bar_parry.modulate = Color(0.7, 0.7, 0.7)
		else:
			lab_parry.text = "Parry [RMB]: READY"
			bar_parry.value = 1.0
			bar_parry.modulate = Color.WHITE
	else:
		bar_stam.value = 1.0
		bar_parry.value = 0.0
		lab_parry.text = "Parry: -"
	bar_noise.value = clampf(game.current_noise / 30.0, 0.0, 1.0)
	if game.current_noise <= 0.5:
		lab_noise.text = "Noise: silent"
	elif game.current_noise < 6.0:
		lab_noise.text = "Noise: quiet"
	elif game.current_noise < 15.0:
		lab_noise.text = "Noise: noisy"
	else:
		lab_noise.text = "Noise: LOUD!"
	bar_mic.value = Mic.level
	bar_mic.modulate = Color(1, 0.3, 0.3) if Mic.level > Mic.threshold else Color.WHITE
	lab_mic.text = "Mic" + (" (off)" if not Mic.enabled else (" - HEARD!" if Mic.level > Mic.threshold else ""))
	# prompt / spectate
	var alive_me: bool = game.alive.get(game.local_id, false)
	if me and not alive_me:
		if me.spectate_id != -1:
			lbl_prompt.text = "GHOST - watching %s   (LMB next, RMB / WASD free fly)" % Net.name_of(me.spectate_id)
		else:
			lbl_prompt.text = "GHOST - free fly (WASD, Space up, Ctrl down)   LMB: watch a survivor"
	else:
		lbl_prompt.text = game.focus.get("text", "")
	cross.visible = alive_me or game.is_monster()
	hide_ov.visible = me != null and me.hidden and alive_me
	# warnings
	var warn := ""
	var d := 99.0
	var pos: Vector3 = Vector3.ZERO
	if me:
		pos = me.global_position
		d = pos.distance_to(mon.global_position)
	if not game.is_monster() and alive_me:
		if st == "windup" and d < 5.0:
			warn = "!! PARRY NOW !!  (Right-click)" if fmod(t, 0.2) < 0.13 else ""
		elif st == "stun" and d < 12.0:
			warn = "HE'S STUNNED - RUN!"
		elif st == "chase" and d < 12.0:
			warn = "TUNG TUNG IS CHASING!"
		else:
			var c: float = game.ability_ready_in("call")
			var k: float = game.ability_ready_in("dark")
			if c > 0.0 and c < 6.0:
				warn = "SAHUR CALL IN %d..." % int(ceil(c))
			elif k > 0.0 and k < 6.0 and game.dark_t <= 0.0:
				warn = "LIGHTS GOING OUT IN %d..." % int(ceil(k))
	lbl_warn.text = warn
	# red vignette: hit flash + heartbeat when he's close
	var a2: float = game.flash_red * 0.5
	if alive_me and d < 9.0:
		a2 += (9.0 - d) / 9.0 * 0.18 * (0.6 + 0.4 * sin(t * (6.0 + (9.0 - d))))
	if game.dark_t > 0.0:
		a2 = maxf(a2, 0.0)
	red.color.a = clampf(a2, 0.0, 0.7)
	msg_t -= delta
	lbl_msg.modulate.a = clampf(msg_t, 0.0, 1.0)
	small_t -= delta
	lbl_small.modulate.a = clampf(small_t, 0.0, 1.0)
