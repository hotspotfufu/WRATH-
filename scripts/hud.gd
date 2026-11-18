extends CanvasLayer
## On-screen display: shield & health, ammo, crosshair, motion tracker (radar),
## soldiers-left counter, Thor's timer / health bar, pick-up prompts,
## kill feed, big banners, start screen and end screen.

var game: Node
var _c: Control
var _font: Font
var _hit := 0.0
var _hit_head := false
var _dmg := 0.0
var _banner := ""
var _sub := ""
var _banner_t := 0.0
var _feed: Array = []
var _time := 0.0
var start_screen := true
var end_title := ""
var end_sub := ""


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_font = ThemeDB.fallback_font
	_c = Control.new()
	_c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_c.draw.connect(_draw)
	add_child(_c)


func _process(delta: float) -> void:
	_time += delta
	_hit = maxf(0.0, _hit - delta * 4.0)
	_dmg = maxf(0.0, _dmg - delta * 1.5)
	_banner_t -= delta
	for f in _feed.duplicate():
		f["t"] -= delta
		if f["t"] <= 0.0:
			_feed.erase(f)
	_c.queue_redraw()


func hitmarker(head: bool) -> void:
	_hit = 1.0
	_hit_head = head


func damage_flash(_from: Node) -> void:
	_dmg = minf(1.0, _dmg + 0.45)


func banner(title: String, sub: String, secs: float) -> void:
	_banner = title
	_sub = sub
	_banner_t = secs


func feed(text: String) -> void:
	_feed.push_front({"text": text, "t": 5.0})
	if _feed.size() > 6:
		_feed.pop_back()


# ------------------------------------------------------------------ drawing helpers
func _text(t: String, p: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var x := p.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_c.draw_string_outline(_font, Vector2(x, p.y), t, HORIZONTAL_ALIGNMENT_LEFT, width, size, maxi(4, size / 6), Color(0, 0, 0, 0.75 * col.a))
	_c.draw_string(_font, Vector2(x, p.y), t, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)


func _bar(r: Rect2, frac: float, col: Color, back := Color(0, 0, 0, 0.45), segments := 0) -> void:
	_c.draw_rect(r.grow(2), Color(0.8, 0.9, 1.0, 0.35), false, 2.0)
	_c.draw_rect(r, back)
	_c.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0, 1), r.size.y)), col)
	for i in range(1, segments):
		var x := r.position.x + r.size.x * i / segments
		_c.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.4), 2.0)


# ------------------------------------------------------------------ main draw
func _draw() -> void:
	var sz := _c.size
	var cx := sz.x * 0.5
	if start_screen:
		_draw_start(sz)
		return
	var p: Node = game.get("player") if game else null
	var boss: Node = game.get("boss") if game else null

	# damage vignette
	if _dmg > 0.0:
		for i in 6:
			var w := 40.0 + i * 25.0
			var a := _dmg * 0.12
			_c.draw_rect(Rect2(0, 0, sz.x, w), Color(0.8, 0.0, 0.0, a))
			_c.draw_rect(Rect2(0, sz.y - w, sz.x, w), Color(0.8, 0.0, 0.0, a))
			_c.draw_rect(Rect2(0, 0, w, sz.y), Color(0.8, 0.0, 0.0, a))
			_c.draw_rect(Rect2(sz.x - w, 0, w, sz.y), Color(0.8, 0.0, 0.0, a))

	# top-left: soldiers left + timer
	var alive := int(game.get("alive")) if game else 0
	_text("SOLDIERS LEFT", Vector2(40, 60), 26, Color(0.85, 0.9, 1.0))
	_text(str(alive), Vector2(40, 120), 64, Color(1, 1, 1))
	var phase := String(game.get("phase")) if game else ""
	if phase == "loot":
		var tl := float(game.get("loot_left"))
		var col := Color(1.0, 0.85, 0.3) if tl > 15.0 else Color(1.0, 0.35, 0.3, 0.6 + 0.4 * sin(_time * 10.0))
		_text("THOR ARRIVES IN  %d:%02d" % [int(tl) / 60, int(tl) % 60], Vector2(40, 170), 30, col)
		_text("Find guns, armor and a vehicle!", Vector2(40, 205), 22, Color(0.85, 0.9, 1.0, 0.85))

	# top-centre: Thor's health
	if boss and is_instance_valid(boss) and not bool(boss.get("dead")):
		_draw_boss_bars(boss, cx)

	if p and is_instance_valid(p) and not bool(p.get("dead")):
		_draw_player(p, sz)
		_draw_radar(p, sz)

	# kill feed
	var fy := 60.0
	for f in _feed:
		_text(f["text"], Vector2(sz.x - 40, fy), 24, Color(1, 1, 1, clampf(f["t"], 0, 1)), HORIZONTAL_ALIGNMENT_RIGHT)
		fy += 34.0

	# banner
	if _banner_t > 0.0:
		var a := clampf(_banner_t, 0.0, 1.0)
		_text(_banner, Vector2(cx, sz.y * 0.32), 72, Color(1.0, 0.9, 0.55, a), HORIZONTAL_ALIGNMENT_CENTER)
		_text(_sub, Vector2(cx, sz.y * 0.32 + 52), 32, Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER)

	if end_title != "":
		_c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.55))
		_text(end_title, Vector2(cx, sz.y * 0.4), 96, Color(1.0, 0.88, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
		_text(end_sub, Vector2(cx, sz.y * 0.4 + 70), 34, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
		_text("Press ENTER or click to play again", Vector2(cx, sz.y * 0.4 + 140), 28, Color(0.8, 0.9, 1.0, 0.6 + 0.4 * sin(_time * 4.0)), HORIZONTAL_ALIGNMENT_CENTER)


## stacked health bars: the bar underneath shows the colour of the next one
const BAR_COLORS := [Color(1.0, 0.75, 0.2), Color(0.7, 0.35, 1.0), Color(0.3, 0.65, 1.0)]


func _draw_boss_bars(boss: Node, cx: float) -> void:
	var hp := float(boss.get("hp"))
	var per := float(boss.get("BAR_HP"))
	var left := int(boss.call("bars_left"))
	var in_bar := hp - per * (left - 1)
	var frac := clampf(in_bar / per, 0.0, 1.0)
	var r := Rect2(cx - 420, 72, 840, 26)
	_text("THOR, GOD OF THUNDER", Vector2(cx, 58), 30, Color(0.75, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	var top: Color = BAR_COLORS[clampi(left - 1, 0, 2)]
	var under := Color(0, 0, 0, 0.5)
	if left > 1:
		under = (BAR_COLORS[left - 2] as Color).darkened(0.25)
	if float(boss.get("_phase_shield")) > 0.0:
		top = Color(0.85, 0.95, 1.0, 0.6 + 0.4 * sin(_time * 18.0))
	_bar(r, frac, top, under, 10)
	# pips: how many bars are left
	for i in 3:
		var pc := Vector2(cx + 450 + i * 26, 85)
		var on := i < left
		_c.draw_circle(pc, 9.0, (BAR_COLORS[i] as Color) if on else Color(0.2, 0.2, 0.25, 0.7))
		_c.draw_arc(pc, 9.0, 0, TAU, 16, Color(1, 1, 1, 0.6), 2.0)
	_text("x%d" % left, Vector2(cx - 440, 94), 30, top, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_player(p: Node, sz: Vector2) -> void:
	var cx := sz.x * 0.5
	# ARMOR (blue) on top, HEALTH (red) underneath. Neither one regenerates.
	var shield := float(p.get("shield"))
	var max_shield := float(p.get("max_shield"))
	var health := float(p.get("health"))
	var sr := Rect2(cx - 300, sz.y - 128, 600, 20)
	_bar(sr, shield / max_shield, Color(0.35, 0.75, 1.0), Color(0, 0, 0, 0.5), 10)
	_text("ARMOR  %d" % int(shield), Vector2(cx - 300, sz.y - 134), 20, Color(0.6, 0.85, 1.0))
	var low := health < 35.0
	var hcol := Color(0.9, 0.25, 0.25) if not low else Color(1.0, 0.2, 0.2, 0.55 + 0.45 * sin(_time * 10.0))
	_bar(Rect2(cx - 300, sz.y - 94, 600, 16), health / float(p.get("max_health")), hcol, Color(0, 0, 0, 0.5), 10)
	_text("HEALTH  %d" % int(health), Vector2(cx + 300, sz.y - 54), 20, Color(1.0, 0.6, 0.6), HORIZONTAL_ALIGNMENT_RIGHT)
	if shield < 1.0:
		_text("ARMOR BROKEN - find armor" if not low else "LOW HEALTH - find a health pack!", Vector2(cx, sz.y - 165), 24, hcol if low else Color(0.6, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER)

	var in_v: Node = p.get("in_vehicle")
	if in_v:
		var names := {"jeep": "JEEP", "mrap": "ARMORED TRUCK", "apc": "8-WHEEL APC"}
		var vname: String = names.get(String(in_v.get("kind")), "VEHICLE")
		var extra := "   LEFT CLICK fire roof gun" if bool(in_v.get("has_turret")) else ""
		_text(vname + "  -  W/S drive  A/D steer  SPACE brake  E get out" + extra, Vector2(cx, sz.y - 150), 24, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
		if bool(in_v.get("has_turret")):
			var cc := Vector2(cx, sz.y * 0.5)
			_c.draw_arc(cc, 20, 0, TAU, 32, Color(1.0, 0.7, 0.3, 0.9), 2.5)
			for i in 4:
				var dd := Vector2.from_angle(TAU * i / 4.0)
				_c.draw_line(cc + dd * 24, cc + dd * 36, Color(1.0, 0.7, 0.3, 0.9), 2.5)
		var vh := float(in_v.get("health"))
		var vmax := float((in_v.get("SPECS") as Dictionary)[String(in_v.get("kind"))]["health"])
		_bar(Rect2(cx - 300, sz.y - 190, 600, 10), vh / vmax, Color(1.0, 0.7, 0.3))
		return

	# crosshair
	var slots: Array = p.get("slots")
	var cur := int(p.get("current"))
	var w: Dictionary = slots[cur]
	var id := String(w["id"])
	var c := Vector2(cx, sz.y * 0.5)
	var col := Color(0.55, 0.9, 1.0, 0.9)
	var zoomed: bool = p.call("_zoomed_sniper")
	if zoomed:
		var r := sz.y * 0.45
		_c.draw_arc(c, r, 0, TAU, 64, Color(0, 0, 0, 0.9), 6.0)
		_c.draw_rect(Rect2(0, 0, c.x - r, sz.y), Color(0, 0, 0, 0.92))
		_c.draw_rect(Rect2(c.x + r, 0, sz.x - c.x - r, sz.y), Color(0, 0, 0, 0.92))
		_c.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.8), 2.0)
		_c.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.8), 2.0)
	else:
		match id:
			"shotgun":
				_c.draw_arc(c, 34, 0, TAU, 40, col, 2.5)
				_c.draw_circle(c, 3, col)
			"rocket":
				_c.draw_arc(c, 26, 0, TAU, 32, col, 2.5)
				_c.draw_rect(Rect2(c - Vector2(6, 6), Vector2(12, 12)), col, false, 2.0)
			"hammer":
				_c.draw_arc(c, 16, 0, TAU, 24, Color(0.6, 0.85, 1.0), 3.0)
			"pistol":
				_c.draw_circle(c, 3, col)
				for i in 4:
					var d := Vector2.from_angle(TAU * i / 4.0 + PI * 0.25)
					_c.draw_line(c + d * 9, c + d * 17, col, 2.5)
			_:
				_c.draw_arc(c, 18, 0, TAU, 32, col, 2.0)
				for i in 4:
					var d := Vector2.from_angle(TAU * i / 4.0)
					_c.draw_line(c + d * 22, c + d * 32, col, 2.5)
				_c.draw_circle(c, 2.5, col)
	if _hit > 0.0:
		var hc := Color(1.0, 0.3, 0.3, _hit) if _hit_head else Color(1, 1, 1, _hit)
		for i in 4:
			var d := Vector2.from_angle(TAU * i / 4.0 + PI * 0.25)
			_c.draw_line(c + d * 12, c + d * 26, hc, 3.0)

	# ammo, bottom right
	var d := Weapons.info(id)
	_text(String(d["name"]), Vector2(sz.x - 50, sz.y - 150), 28, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	if d.get("melee", false):
		_text("CLICK smash  /  RIGHT CLICK throw", Vector2(sz.x - 50, sz.y - 90), 28, Color(0.6, 0.85, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		var mag := int(w["mag"])
		_text("%d" % mag, Vector2(sz.x - 190, sz.y - 70), 72, Color(1, 0.35, 0.3) if mag == 0 else Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		_text("/ %d" % int(w["reserve"]), Vector2(sz.x - 50, sz.y - 74), 36, Color(0.8, 0.85, 0.9), HORIZONTAL_ALIGNMENT_RIGHT)
	# weapon slots: shows what you carry and the button for each
	var y := sz.y - 300.0
	for i in slots.size():
		var sw: Dictionary = slots[i]
		var on := i == cur
		var label := "[%d]  %s" % [i + 1, String(Weapons.info(sw["id"])["name"])]
		if on:
			_c.draw_rect(Rect2(sz.x - 330, y - 26, 290, 34), Color(0.35, 0.7, 1.0, 0.25))
		_text(label, Vector2(sz.x - 50, y), 24 if on else 21, Color(1, 1, 1) if on else Color(0.8, 0.85, 0.9, 0.65), HORIZONTAL_ALIGNMENT_RIGHT)
		y += 36.0
	if slots.size() > 1:
		_text("Q / mouse wheel = switch", Vector2(sz.x - 50, y + 4), 18, Color(0.7, 0.85, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)

	# pick-up / vehicle prompt
	var prompt := ""
	for v in get_tree().get_nodes_in_group("vehicles"):
		if (v as Node3D).global_position.distance_to((p as Node3D).global_position) < 3.6 and v.call("free_seat"):
			prompt = "[E]  Drive " + {"jeep": "JEEP", "mrap": "ARMORED TRUCK", "apc": "8-WHEEL APC"}.get(String(v.get("kind")), "VEHICLE")
	if prompt == "" and p.call("nearest_chest"):
		prompt = "[E]  Open supply chest"
	if prompt == "":
		var item: Node = p.call("nearest_pickup")
		if item and String(item.get("kind")) == "weapon":
			prompt = "[E]  Pick up " + String(item.call("label"))
	if prompt != "":
		_text(prompt, Vector2(cx, sz.y * 0.5 + 110), 30, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_radar(p: Node, sz: Vector2) -> void:
	# motion tracker: 40 m around you
	var c := Vector2(150, sz.y - 150)
	var r := 115.0
	_c.draw_circle(c, r, Color(0.05, 0.12, 0.2, 0.55))
	_c.draw_arc(c, r, 0, TAU, 48, Color(0.5, 0.8, 1.0, 0.7), 2.5)
	_c.draw_arc(c, r * 0.5, 0, TAU, 32, Color(0.5, 0.8, 1.0, 0.25), 1.5)
	var me := p as Node3D
	var yaw := me.global_rotation.y
	var vp: Node = p.get("in_vehicle")
	if vp:
		yaw = (vp.get("_pivot") as Node3D).global_rotation.y
	var range_m := 40.0
	for s in get_tree().get_nodes_in_group("soldiers"):
		var off := (s as Node3D).global_position - me.global_position
		var v := Vector2(off.x, off.z).rotated(yaw)
		if v.length() < range_m:
			_c.draw_circle(c + v / range_m * r, 4.0, Color(1.0, 0.85, 0.3))
	for b in get_tree().get_nodes_in_group("boss"):
		var off := (b as Node3D).global_position - me.global_position
		var v := Vector2(off.x, off.z).rotated(yaw)
		var pos := c + v.limit_length(range_m) / range_m * r
		_c.draw_circle(pos, 9.0 + sin(_time * 8.0) * 2.0, Color(1.0, 0.2, 0.2))
	_c.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(-6, 7), c + Vector2(6, 7)]), Color(0.6, 0.9, 1.0))


func _draw_start(sz: Vector2) -> void:
	var cx := sz.x * 0.5
	_c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.02, 0.04, 0.08, 0.72))
	_text("GOD HUNT", Vector2(cx, sz.y * 0.24), 120, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_CENTER)
	_text("100 soldiers.  2:00 to gear up.  Then THOR falls from the sky.", Vector2(cx, sz.y * 0.24 + 70), 34, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	var lines := [
		"WASD  move        SHIFT  sprint        SPACE  jump        C  crouch",
		"MOUSE  look        LEFT CLICK  fire        RIGHT CLICK  aim",
		"R  reload        E  pick up / drive        Q / wheel / 1 2 3  switch weapon (carry 3)",
		"Gamepad works too.   ESC frees the mouse.",
	]
	var y := sz.y * 0.48
	for l in lines:
		_text(l, Vector2(cx, y), 30, Color(1, 1, 1, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
		y += 46.0
	_text("CLICK TO DROP IN", Vector2(cx, sz.y * 0.8), 56, Color(0.55, 0.9, 1.0, 0.6 + 0.4 * sin(_time * 4.0)), HORIZONTAL_ALIGNMENT_CENTER)
