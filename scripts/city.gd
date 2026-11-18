extends Node3D
## Builds the city map: a 7 x 7 grid of blocks with roads between them.
## Blocks hold enterable buildings (several floors, a doorway, ramps up to the
## roof), solid skyscrapers, parks and plazas. Every building can be smashed.

const BLOCKS := 7
const BLOCK := 36.0
const ROAD := 14.0
const CELL := BLOCK + ROAD
const FLOOR_H := 4.0
const WALL := 0.4
const HALF := BLOCKS * CELL * 0.5           # map edge distance from the centre

var buildings: Array = []        # [{node, body, aabb, height, alive}]
var loot_points: Array[Vector3] = []
var road_nodes: Array[Vector3] = []       # intersections, for soldiers to walk between
var vehicle_points: Array[Transform3D] = []
var spawn_points: Array[Vector3] = []

var _rng := RandomNumberGenerator.new()
var _mat_cache := {}
var _debris_alive := 0
var _wall_shader: Shader

const WALL_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;
uniform vec3 base : source_color = vec3(0.6, 0.6, 0.62);
uniform vec3 trim : source_color = vec3(0.3, 0.32, 0.36);
uniform float windows = 1.0;
uniform float floor_h = 4.0;
uniform float win_w = 3.0;
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5); }
void fragment() {
	vec3 c = base;
	float rough = 0.85;
	float metal = 0.0;
	if (abs(wn.y) < 0.5 && windows > 0.5) {
		float u = abs(wn.x) > 0.5 ? wp.z : wp.x;
		float v = wp.y;
		vec2 cell = vec2(u / win_w, v / floor_h);
		vec2 f = fract(cell);
		float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.28, f.y) * step(f.y, 0.85);
		float lit = hash(floor(cell));
		vec3 glass = mix(vec3(0.10, 0.16, 0.24), vec3(0.32, 0.45, 0.58), f.y * 0.8 + lit * 0.2);
		c = mix(c, glass, win);
		rough = mix(rough, 0.12, win);
		metal = mix(0.0, 0.4, win);
		// floor band
		c = mix(c, trim, step(f.y, 0.06));
	}
	// grime toward the street
	c *= 0.82 + 0.18 * clamp(wp.y / 6.0, 0.0, 1.0);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""


func build(seed_value: int = 1) -> void:
	_rng.seed = seed_value
	_wall_shader = Shader.new()
	_wall_shader.code = WALL_SHADER
	_build_ground()
	_build_edges()
	var centre := int(BLOCKS / 2)
	for bx in BLOCKS:
		for bz in BLOCKS:
			var c := _block_centre(bx, bz)
			if bx == centre and bz == centre:
				_build_plaza(c)
			elif _rng.randf() < 0.12:
				_build_park(c)
			else:
				_fill_block(c)
	for ix in BLOCKS + 1:
		for iz in BLOCKS + 1:
			road_nodes.append(Vector3(-HALF + ix * CELL, 0, -HALF + iz * CELL))
	_build_street_props()


func _block_centre(bx: int, bz: int) -> Vector3:
	return Vector3(-HALF + ROAD * 0.5 + BLOCK * 0.5 + bx * CELL, 0, -HALF + ROAD * 0.5 + BLOCK * 0.5 + bz * CELL)


# ------------------------------------------------------------------ materials
func mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(), rough]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	_mat_cache[key] = m
	return m


func wall_mat(base: Color, windows: bool) -> ShaderMaterial:
	var key := "wall_%s_%s" % [base.to_html(), windows]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _wall_shader
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("trim", base.darkened(0.45))
	m.set_shader_parameter("windows", 1.0 if windows else 0.0)
	_mat_cache[key] = m
	return m


## a solid box: mesh + collision on the given body
func box(body: Node3D, size: Vector3, pos: Vector3, material: Material, collide: bool = true, rot_x: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.position = pos
	mi.rotation.x = rot_x
	body.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		cs.rotation.x = rot_x
		body.add_child(cs)
	return mi


# ------------------------------------------------------------------ ground & edges
func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	add_child(ground)
	var size := HALF * 2.0 + 120.0
	box(ground, Vector3(size, 2, size), Vector3(0, -1, 0), mat(Color(0.20, 0.21, 0.23), 0.95))
	# sidewalks / block plates (visual only, flush with the road so vehicles drive smoothly)
	var plate := mat(Color(0.52, 0.52, 0.5))
	var lines := mat(Color(0.92, 0.92, 0.88), 0.6)
	for bx in BLOCKS:
		for bz in BLOCKS:
			var c := _block_centre(bx, bz)
			box(ground, Vector3(BLOCK + 3.0, 0.06, BLOCK + 3.0), c + Vector3(0, 0.03, 0), plate, false)
	# dashed centre lines
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dash := BoxMesh.new()
	dash.size = Vector3(3.0, 0.02, 0.25)
	dash.material = lines
	mm.mesh = dash
	var xf: Array[Transform3D] = []
	for i in BLOCKS + 1:
		var r := -HALF + i * CELL
		var t := -HALF
		while t < HALF:
			xf.append(Transform3D(Basis(), Vector3(t, 0.02, r)))
			xf.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(r, 0.02, t)))
			t += 6.0
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_edges() -> void:
	# tall concrete walls around the map, with distant towers beyond them
	var edge := StaticBody3D.new()
	edge.name = "Edges"
	add_child(edge)
	var w := HALF + 10.0
	var m := wall_mat(Color(0.45, 0.46, 0.5), false)
	box(edge, Vector3(w * 2, 14, 2), Vector3(0, 7, -w), m)
	box(edge, Vector3(w * 2, 14, 2), Vector3(0, 7, w), m)
	box(edge, Vector3(2, 14, w * 2), Vector3(-w, 7, 0), m)
	box(edge, Vector3(2, 14, w * 2), Vector3(w, 7, 0), m)
	var far := Node3D.new()
	add_child(far)
	for i in 40:
		var a := TAU * i / 40.0
		var d := w + _rng.randf_range(30, 70)
		var h := _rng.randf_range(30, 90)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(14, 26), h, _rng.randf_range(14, 26))
		mi.mesh = bm
		mi.material_override = wall_mat(Color(0.5, 0.55, 0.62), true)
		mi.position = Vector3(cos(a) * d, h * 0.5, sin(a) * d)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.add_child(mi)


# ------------------------------------------------------------------ blocks
const PALETTE := [Color(0.72, 0.68, 0.6), Color(0.62, 0.58, 0.55), Color(0.55, 0.6, 0.66), Color(0.7, 0.55, 0.45), Color(0.48, 0.5, 0.52), Color(0.78, 0.76, 0.7)]


func _fill_block(c: Vector3) -> void:
	var roll := _rng.randf()
	if roll < 0.3:
		# one big skyscraper + a small enterable building
		_tower(c + Vector3(-7, 0, -7), Vector2(18, 18), _rng.randf_range(36, 70))
		_enterable(c + Vector3(9, 0, 9), Vector2(14, 14), 2, _rng.randi() % 4)
	elif roll < 0.75:
		# four mid-size enterable buildings
		for ox in [-1, 1]:
			for oz in [-1, 1]:
				if _rng.randf() < 0.8:
					var w := _rng.randf_range(12, 15)
					_enterable(c + Vector3(ox * 9.2, 0, oz * 9.2), Vector2(w, w), _rng.randi_range(2, 4), _rng.randi() % 4)
				else:
					_tower(c + Vector3(ox * 9.2, 0, oz * 9.2), Vector2(14, 14), _rng.randf_range(20, 40))
	else:
		# two long buildings with a courtyard between them
		_enterable(c + Vector3(0, 0, -10), Vector2(30, 13), _rng.randi_range(2, 3), 0)
		_enterable(c + Vector3(0, 0, 10), Vector2(30, 13), _rng.randi_range(2, 3), 2)
		loot_points.append(c + Vector3(0, 0.6, 0))
		loot_points.append(c + Vector3(8, 0.6, 0))
	spawn_points.append(c + Vector3(_rng.randf_range(-17, 17), 0.5, 17.5))


func _new_building(c: Vector3, footprint: Vector2, height: float) -> Dictionary:
	var root := StaticBody3D.new()
	root.name = "Building%d" % buildings.size()
	root.position = c
	add_child(root)
	var aabb := AABB(c + Vector3(-footprint.x * 0.5, 0, -footprint.y * 0.5), Vector3(footprint.x, height, footprint.y))
	var b := {"node": root, "aabb": aabb, "height": height, "alive": true, "color": PALETTE[0]}
	buildings.append(b)
	return b


func _tower(c: Vector3, fp: Vector2, h: float) -> void:
	var b := _new_building(c, fp, h)
	var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
	b["color"] = col
	var m := wall_mat(col, true)
	var root: Node3D = b["node"]
	# stepped skyscraper: base, middle, crown
	var h1 := h * 0.55
	box(root, Vector3(fp.x, h1, fp.y), Vector3(0, h1 * 0.5, 0), m)
	var h2 := h * 0.35
	box(root, Vector3(fp.x * 0.8, h2, fp.y * 0.8), Vector3(0, h1 + h2 * 0.5, 0), m)
	var h3 := h * 0.1
	box(root, Vector3(fp.x * 0.5, h3, fp.y * 0.5), Vector3(0, h1 + h2 + h3 * 0.5, 0), wall_mat(col.darkened(0.25), false))
	box(root, Vector3(0.4, 6, 0.4), Vector3(0, h + 3, 0), mat(Color(0.3, 0.3, 0.32)), false)


## a building you can walk into: doorway on one side, floors linked by ramps,
## and a flat roof with a low wall around it
func _enterable(c: Vector3, fp: Vector2, floors: int, door_side: int) -> void:
	if door_side == 3:
		door_side = 1          # the ramps run along the west wall, keep the door clear of them
	var h := floors * FLOOR_H
	var b := _new_building(c, fp, h + 1.0)
	var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
	b["color"] = col
	var root: Node3D = b["node"]
	var wm := wall_mat(col, true)
	var fm := mat(Color(0.42, 0.40, 0.38))
	var W := fp.x
	var D := fp.y
	var door_w := 3.4
	var door_h := 3.0
	# walls, floor by floor
	for f in floors:
		var y0 := f * FLOOR_H
		var cy := y0 + FLOOR_H * 0.5
		for side in 4:
			var along := W if side % 2 == 0 else D
			var off := (D if side % 2 == 0 else W) * 0.5 - WALL * 0.5
			var has_door := f == 0 and side == door_side
			var has_window := f > 0 and _rng.randf() < 0.35
			var pieces: Array = []      # [start, end, y_bottom, y_top] along the wall
			if has_door:
				pieces = [[-along * 0.5, -door_w * 0.5, y0, y0 + FLOOR_H], [door_w * 0.5, along * 0.5, y0, y0 + FLOOR_H], [-door_w * 0.5, door_w * 0.5, y0 + door_h, y0 + FLOOR_H]]
			elif has_window:
				# a real opening you can shoot through / jump out of
				pieces = [[-along * 0.5, -2.0, y0, y0 + FLOOR_H], [2.0, along * 0.5, y0, y0 + FLOOR_H], [-2.0, 2.0, y0, y0 + 1.1], [-2.0, 2.0, y0 + 3.0, y0 + FLOOR_H]]
			else:
				pieces = [[-along * 0.5, along * 0.5, y0, y0 + FLOOR_H]]
			for p in pieces:
				var plen: float = p[1] - p[0]
				var hgt: float = p[3] - p[2]
				var mid: float = (p[0] + p[1]) * 0.5
				var pos: Vector3
				var size: Vector3
				var py: float = (p[2] + p[3]) * 0.5
				if side == 0:
					pos = Vector3(mid, py, off)
					size = Vector3(plen, hgt, WALL)
				elif side == 2:
					pos = Vector3(mid, py, -off)
					size = Vector3(plen, hgt, WALL)
				elif side == 1:
					pos = Vector3(off, py, mid)
					size = Vector3(WALL, hgt, plen)
				else:
					pos = Vector3(-off, py, mid)
					size = Vector3(WALL, hgt, plen)
				box(root, size, pos, wm)
	# floors (with a hole above each ramp) and the ramps
	var rw := 2.6
	var run := 9.0
	var x0 := -W * 0.5 + WALL
	var z0 := -D * 0.5 + WALL
	for f in range(1, floors + 1):
		var y := f * FLOOR_H
		var slab := 0.3
		# slab A: everything to the right of the ramp column
		box(root, Vector3(W - rw - WALL, slab, D), Vector3(x0 + rw + (W - rw - WALL) * 0.5, y - slab * 0.5, 0), fm)
		# slab B: in the ramp column, in front of the hole
		var bz := D - WALL - run - 0.4
		if bz > 0.2:
			box(root, Vector3(rw, slab, bz), Vector3(x0 + rw * 0.5, y - slab * 0.5, z0 + run + 0.4 + bz * 0.5), fm)
	for f in floors:
		var y0 := f * FLOOR_H
		var length := sqrt(run * run + FLOOR_H * FLOOR_H)
		var ang := atan2(FLOOR_H, run)
		# rises from the front (low) to the back wall (high)
		box(root, Vector3(rw - 0.2, 0.25, length), Vector3(x0 + rw * 0.5, y0 + FLOOR_H * 0.5, z0 + run * 0.5), fm, true, ang)
		loot_points.append(c + Vector3(x0 + rw + 3.0, y0 + 0.6, 2.0))
	# roof wall
	var rm := wall_mat(col.darkened(0.2), false)
	var top := h + 0.5
	box(root, Vector3(W, 1.0, WALL), Vector3(0, top, D * 0.5 - WALL * 0.5), rm)
	box(root, Vector3(W, 1.0, WALL), Vector3(0, top, -D * 0.5 + WALL * 0.5), rm)
	box(root, Vector3(WALL, 1.0, D), Vector3(W * 0.5 - WALL * 0.5, top, 0), rm)
	box(root, Vector3(WALL, 1.0, D), Vector3(-W * 0.5 + WALL * 0.5, top, 0), rm)
	loot_points.append(c + Vector3(W * 0.25, h + 0.6, D * 0.2))


func _build_plaza(c: Vector3) -> void:
	# open square in the middle of the city: good place to fight Thor
	var body := StaticBody3D.new()
	add_child(body)
	box(body, Vector3(BLOCK, 0.3, BLOCK), c + Vector3(0, 0.15, 0), mat(Color(0.66, 0.62, 0.55)))
	box(body, Vector3(6, 1.2, 6), c + Vector3(0, 0.6, 0), mat(Color(0.55, 0.55, 0.58)))
	box(body, Vector3(1.2, 7, 1.2), c + Vector3(0, 4.5, 0), mat(Color(0.75, 0.7, 0.5), 0.4))
	for i in 6:
		var a := TAU * i / 6.0
		box(body, Vector3(4, 1.4, 1.0), c + Vector3(cos(a) * 12, 0.7, sin(a) * 12), mat(Color(0.5, 0.5, 0.52)))
		loot_points.append(c + Vector3(cos(a + 0.5) * 9, 0.9, sin(a + 0.5) * 9))
	spawn_points.append(c + Vector3(0, 1.0, 15))


func _build_park(c: Vector3) -> void:
	var body := StaticBody3D.new()
	add_child(body)
	box(body, Vector3(BLOCK, 0.2, BLOCK), c + Vector3(0, 0.1, 0), mat(Color(0.32, 0.55, 0.25)), false)
	var trunk := mat(Color(0.4, 0.28, 0.18))
	var leaf := mat(Color(0.22, 0.48, 0.2))
	for i in 9:
		var p := c + Vector3(_rng.randf_range(-14, 14), 0, _rng.randf_range(-14, 14))
		box(body, Vector3(0.6, 4, 0.6), p + Vector3(0, 2, 0), trunk)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.4
		sm.height = 4.0
		mi.mesh = sm
		mi.material_override = leaf
		mi.position = p + Vector3(0, 5, 0)
		body.add_child(mi)
	for i in 3:
		loot_points.append(c + Vector3(_rng.randf_range(-12, 12), 0.6, _rng.randf_range(-12, 12)))
	spawn_points.append(c + Vector3(0, 0.5, 0))


func _build_street_props() -> void:
	# parked cars for cover, plus spots where drivable jeeps wait
	var body := StaticBody3D.new()
	body.name = "Props"
	add_child(body)
	var car_cols := [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6), Color(0.85, 0.85, 0.82), Color(0.1, 0.1, 0.12), Color(0.85, 0.7, 0.2)]
	for i in BLOCKS + 1:
		var r := -HALF + i * CELL
		for j in BLOCKS:
			var t := -HALF + ROAD * 0.5 + BLOCK * 0.5 + j * CELL
			for k in 2:
				var horizontal := k == 0
				var off := _rng.randf_range(-14, 14)
				var side := 1.0 if _rng.randf() < 0.5 else -1.0
				var p := Vector3(t + off, 0, r + side * 5.0) if horizontal else Vector3(r + side * 5.0, 0, t + off)
				if _rng.randf() < 0.35:
					var cm := mat(car_cols[_rng.randi() % car_cols.size()], 0.35)
					var sz := Vector3(4.2, 1.2, 1.9) if horizontal else Vector3(1.9, 1.2, 4.2)
					box(body, sz, p + Vector3(0, 0.75, 0), cm)
					var top := Vector3(2.2, 0.7, 1.7) if horizontal else Vector3(1.7, 0.7, 2.2)
					box(body, top, p + Vector3(0, 1.7, 0), mat(Color(0.15, 0.2, 0.25), 0.1), false)
				elif _rng.randf() < 0.18:
					var yaw := 0.0 if horizontal else PI * 0.5
					vehicle_points.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 1.0, 0)))
				elif _rng.randf() < 0.4:
					loot_points.append(p + Vector3(0, 0.6, 0))
	# street lights
	var pole := mat(Color(0.25, 0.26, 0.28), 0.5)
	for n in road_nodes:
		var p: Vector3 = n + Vector3(ROAD * 0.5 + 0.8, 0, ROAD * 0.5 + 0.8)
		if absf(p.x) < HALF and absf(p.z) < HALF:
			box(body, Vector3(0.25, 7, 0.25), p + Vector3(0, 3.5, 0), pole)
			box(body, Vector3(1.6, 0.25, 0.4), p + Vector3(-0.7, 7, 0), pole, false)


# ------------------------------------------------------------------ destruction
func building_at(p: Vector3, margin: float = 2.0) -> int:
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if b["alive"] and (b["aabb"] as AABB).grow(margin).has_point(p):
			return i
	return -1


func nearest_building(p: Vector3, max_dist: float) -> int:
	var best := -1
	var bd := max_dist
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		if not b["alive"]:
			continue
		var a: AABB = b["aabb"]
		var cp := Vector3(clampf(p.x, a.position.x, a.end.x), 0, clampf(p.z, a.position.z, a.end.z))
		var d := Vector2(cp.x - p.x, cp.z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## collapse a building: it sinks into a cloud of dust while chunks fly off.
## Everything standing inside or on it takes heavy damage.
func smash(index: int, from: Vector3, by: Node = null) -> void:
	if index < 0 or index >= buildings.size():
		return
	var b: Dictionary = buildings[index]
	if not b["alive"]:
		return
	b["alive"] = false
	var root: StaticBody3D = b["node"]
	var aabb: AABB = b["aabb"]
	var h: float = b["height"]
	# hurt everyone inside / on top
	for group in ["player", "soldiers"]:
		for n in get_tree().get_nodes_in_group(group):
			if n is Node3D and aabb.grow(1.5).has_point((n as Node3D).global_position) and n.has_method("take_damage"):
				n.call("take_damage", 140.0, by)
	# stop blocking movement straight away, then sink out of sight
	root.collision_layer = 0
	var tw := create_tween()
	tw.tween_property(root, "position:y", -h - 2.0, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(root, "rotation:z", _rng.randf_range(-0.12, 0.12), 2.4)
	tw.tween_callback(root.queue_free)
	# rubble pile
	var rubble := StaticBody3D.new()
	add_child(rubble)
	var rm := mat((b["color"] as Color).darkened(0.35))
	for i in 6:
		var s := Vector3(_rng.randf_range(2, 5), _rng.randf_range(0.6, 1.8), _rng.randf_range(2, 5))
		var p := aabb.get_center() + Vector3(_rng.randf_range(-aabb.size.x, aabb.size.x) * 0.35, s.y * 0.5, _rng.randf_range(-aabb.size.z, aabb.size.z) * 0.35)
		var mi := box(rubble, s, Vector3(p.x, -2.0, p.z), rm)
		mi.rotation.y = _rng.randf() * TAU
		create_tween().tween_property(mi, "position:y", s.y * 0.5 - 0.2, 1.6).set_delay(0.8)
		var col := rubble.get_child(rubble.get_child_count() - 1) as Node3D
		col.position.y = s.y * 0.5 - 0.2
	# flying chunks and dust
	var chunks := mini(16, 40 - _debris_alive)
	for i in chunks:
		_debris(aabb, from, b["color"])
	FX.dust(get_parent(), aabb.get_center() + Vector3(0, 2, 0), maxf(aabb.size.x, aabb.size.z), 2.8)
	get_tree().call_group("game", "on_building_smashed", aabb.get_center())


func _debris(aabb: AABB, from: Vector3, col: Color) -> void:
	_debris_alive += 1
	var rb := RigidBody3D.new()
	rb.collision_layer = 64
	rb.collision_mask = 1
	var s := Vector3(_rng.randf_range(0.8, 2.2), _rng.randf_range(0.8, 2.2), _rng.randf_range(0.8, 2.2))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = s
	cs.shape = sh
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = wall_mat(col, true)
	rb.add_child(mi)
	add_child(rb)
	rb.global_position = aabb.position + Vector3(_rng.randf() * aabb.size.x, _rng.randf_range(0.3, 0.9) * aabb.size.y, _rng.randf() * aabb.size.z)
	var away := (rb.global_position - from)
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	rb.linear_velocity = away * _rng.randf_range(6, 16) + Vector3(0, _rng.randf_range(4, 12), 0)
	rb.angular_velocity = Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4), _rng.randf_range(-4, 4))
	var tw := rb.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(rb, "scale", Vector3(0.01, 0.01, 0.01), 0.6)
	tw.tween_callback(func():
		_debris_alive -= 1
		rb.queue_free())
