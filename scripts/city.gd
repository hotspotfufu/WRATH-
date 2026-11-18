extends Node3D
## Builds the city map: a 7 x 7 grid of blocks with roads between them.
## Blocks hold enterable buildings (several floors, a doorway, ramps up to the
## roof), solid skyscrapers, parks and plazas. Every building can be smashed.

const BLOCKS := 4
const BLOCK := 78.0
const ROAD := 27.0
const ARENA_R := 50.0                        # open boss arena around the centre crossroads
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
uniform sampler2D surface : source_color, filter_linear_mipmap, repeat_enable;
uniform float tex_size = 6.0;       // metres covered by one copy of the texture
uniform float raw_color = 0.0;      // 1 = use the texture's own colour (brick)
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5); }
void fragment() {
	// facade texture, projected in world space so it never stretches
	vec2 tuv = abs(wn.y) > 0.5 ? wp.xz : vec2(abs(wn.x) > 0.5 ? wp.z : wp.x, wp.y);
	vec3 tx = texture(surface, tuv / tex_size).rgb;
	vec3 c = mix(base * tx * 1.45, tx * (base / 0.6), raw_color);
	float rough = 0.85;
	float metal = 0.0;
	if (abs(wn.y) < 0.5 && windows > 0.5) {
		float u = abs(wn.x) > 0.5 ? wp.z : wp.x;
		float v = wp.y;
		vec2 cell = vec2(u / win_w, v / floor_h);
		vec2 f = fract(cell);
		float win = step(0.16, f.x) * step(f.x, 0.84) * step(0.26, f.y) * step(f.y, 0.86);
		float frame = step(0.13, f.x) * step(f.x, 0.87) * step(0.23, f.y) * step(f.y, 0.89) - win;
		float lit = hash(floor(cell));
		// sky reflection: lighter at the top of each pane, a few panes brighter
		vec3 glass = mix(vec3(0.07, 0.11, 0.17), vec3(0.42, 0.55, 0.68), pow(f.y, 1.5) * 0.85 + step(0.88, lit) * 0.35);
		glass = mix(glass, vec3(0.95, 0.82, 0.55), step(0.965, lit) * 0.6);     // warm lit office
		float mullion = step(abs(f.x - 0.5), 0.012);
		c = mix(c, trim * 0.8, frame);
		c = mix(c, glass, win * (1.0 - mullion));
		c = mix(c, trim, win * mullion);
		rough = mix(rough, 0.08, win);
		metal = mix(0.0, 0.5, win);
		// floor band + sill shadow under each window
		c = mix(c, trim, step(f.y, 0.06));
		c *= 1.0 - 0.25 * step(0.2, f.y) * step(f.y, 0.26) * step(0.16, f.x) * step(f.x, 0.84);
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
	var park := _rng.randi() % (BLOCKS * BLOCKS)
	var i := 0
	for bx in BLOCKS:
		for bz in BLOCKS:
			var c := _block_centre(bx, bz)
			if i == park and Vector2(c.x, c.z).length() > CELL:
				_build_park(c)
			else:
				_fill_block(c)
			i += 1
	for ix in BLOCKS + 1:
		for iz in BLOCKS + 1:
			road_nodes.append(Vector3(-HALF + ix * CELL, 0, -HALF + iz * CELL))
	_build_arena()
	_crosswalks()
	_trees_and_lamps()
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


func tex(name: String) -> Texture2D:
	var key := "tex_" + name
	if not _mat_cache.has(key):
		_mat_cache[key] = load(get_script().resource_path.get_base_dir() + "/tex_" + name + ".png")
	return _mat_cache[key]


## textured floor / surface material (world-projected so it tiles at real size)
func surface_mat(name: String, tint: Color = Color.WHITE, size_m: float = 2.0, rough: float = 0.85) -> StandardMaterial3D:
	var key := "surf_%s_%s_%s" % [name, tint.to_html(), size_m]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(name)
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / size_m
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat_cache[key] = m
	return m


func wall_mat(base: Color, windows: bool) -> ShaderMaterial:
	var key := "wall_%s_%s" % [base.to_html(), windows]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _wall_shader
	# warm colours become brick buildings, the rest precast concrete
	var brick := base.r > base.b + 0.08
	m.set_shader_parameter("surface", tex("brick") if brick else tex("concrete"))
	m.set_shader_parameter("tex_size", 2.6 if brick else 7.0)
	m.set_shader_parameter("raw_color", 1.0 if brick else 0.0)
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
	var asphalt := surface_mat("asphalt", Color(1, 1, 1), 6.0, 0.9)
	box(ground, Vector3(size, 2, size), Vector3(0, -1, 0), asphalt)
	# sidewalks with a raised curb look (visual only, flush with the road so vehicles drive smoothly)
	var plate := surface_mat("paver", Color(1, 1, 1), 3.0, 0.85)
	var curb := mat(Color(0.72, 0.71, 0.68), 0.8)
	var lines := mat(Color(0.92, 0.92, 0.88), 0.6)
	for bx in BLOCKS:
		for bz in BLOCKS:
			var c := _block_centre(bx, bz)
			box(ground, Vector3(BLOCK + 3.0, 0.08, BLOCK + 3.0), c + Vector3(0, 0.04, 0), plate, false)
			for sgn in [-1.0, 1.0]:
				box(ground, Vector3(BLOCK + 3.4, 0.16, 0.4), c + Vector3(0, 0.08, sgn * (BLOCK * 0.5 + 1.5)), curb, false)
				box(ground, Vector3(0.4, 0.16, BLOCK + 3.4), c + Vector3(sgn * (BLOCK * 0.5 + 1.5), 0.08, 0), curb, false)
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
const PALETTE := [Color(0.68, 0.64, 0.57), Color(0.55, 0.5, 0.47), Color(0.42, 0.48, 0.56), Color(0.62, 0.47, 0.38), Color(0.36, 0.38, 0.41), Color(0.7, 0.68, 0.62), Color(0.28, 0.32, 0.38)]


func _fill_block(c: Vector3) -> void:
	# four big lots per block; downtown (the middle blocks) grows taller
	var downtown := absf(c.x) < CELL and absf(c.z) < CELL
	for ox in [-1, 1]:
		for oz in [-1, 1]:
			var lot := c + Vector3(ox * 19.0, 0, oz * 19.0)
			if Vector2(lot.x, lot.z).length() < ARENA_R:
				continue          # leave room for the boss arena
			var w := _rng.randf_range(20, 28)
			var d := _rng.randf_range(20, 28)
			var door := 0 if oz > 0 else 2        # entrances face the street
			if _rng.randf() < 0.55:
				# a building you can go all the way up (ramps to the roof)
				_enterable(lot, Vector2(w, d), _rng.randi_range(2, 4), door)
			else:
				var h := _rng.randf_range(30, 70) + (28.0 if downtown else 0.0)
				_tower(lot, Vector2(w, d), h, door)
	# courtyard between the lots: loot + cover
	loot_points.append(c + Vector3(0, 0.6, 0))
	loot_points.append(c + Vector3(_rng.randf_range(-4, 4), 0.6, 4.5))
	spawn_points.append(c + Vector3(_rng.randf_range(-30, 30), 0.5, 37.0))


func _build_arena() -> void:
	# the open crossroads in the middle of the city where you fight the god
	var body := StaticBody3D.new()
	body.name = "Arena"
	add_child(body)
	var stone := mat(Color(0.62, 0.6, 0.56))
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = ARENA_R - 6.0
	cyl.bottom_radius = ARENA_R - 6.0
	cyl.height = 0.08
	cyl.radial_segments = 64
	cyl.material = mat(Color(0.48, 0.47, 0.45))
	ring.mesh = cyl
	ring.position.y = 0.04
	body.add_child(ring)
	var inner := MeshInstance3D.new()
	var cyl2 := CylinderMesh.new()
	cyl2.top_radius = 16.0
	cyl2.bottom_radius = 16.0
	cyl2.height = 0.1
	cyl2.radial_segments = 48
	cyl2.material = mat(Color(0.58, 0.56, 0.52))
	inner.mesh = cyl2
	inner.position.y = 0.05
	body.add_child(inner)
	# low cover walls in a broken ring, and planters
	for i in 10:
		var a := TAU * i / 10.0 + 0.15
		var p := Vector3(cos(a), 0, sin(a)) * 30.0
		var wall := box(body, Vector3(6.0, 1.3, 0.8), p + Vector3(0, 0.65, 0), stone)
		wall.rotation.y = -a + PI * 0.5
		(body.get_child(body.get_child_count() - 1) as Node3D).rotation.y = wall.rotation.y
		if i % 2 == 0:
			var q := Vector3(cos(a + 0.31), 0, sin(a + 0.31)) * 40.0
			box(body, Vector3(3, 0.8, 3), q + Vector3(0, 0.4, 0), mat(Color(0.4, 0.38, 0.35)))
			var bush := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 1.6
			sm.height = 2.4
			sm.material = mat(Color(0.2, 0.42, 0.22))
			bush.mesh = sm
			bush.position = q + Vector3(0, 1.6, 0)
			body.add_child(bush)
		loot_points.append(Vector3(cos(a + 0.2), 0, sin(a + 0.2)) * 24.0 + Vector3(0, 0.6, 0))
	# broken statue plinth in the centre
	box(body, Vector3(7, 1.0, 7), Vector3(0, 0.5, 0), stone)
	box(body, Vector3(5, 1.0, 5), Vector3(0, 1.5, 0), stone)
	box(body, Vector3(1.6, 5.0, 1.6), Vector3(0, 4.5, 0), mat(Color(0.55, 0.62, 0.58), 0.4))


func _crosswalks() -> void:
	var paint := mat(Color(0.9, 0.9, 0.86), 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.9, 0.03, 4.5)
	stripe.material = paint
	mm.mesh = stripe
	var xf: Array[Transform3D] = []
	for n in road_nodes:
		if Vector2(n.x, n.z).length() < ARENA_R:
			continue
		for side in [-1.0, 1.0]:
			for k in 8:
				var along := -ROAD * 0.35 + k * (ROAD * 0.7 / 7.0)
				xf.append(Transform3D(Basis(), n + Vector3(along, 0.03, side * (ROAD * 0.5 + 3.0))))
				xf.append(Transform3D(Basis(Vector3.UP, PI * 0.5), n + Vector3(side * (ROAD * 0.5 + 3.0), 0.03, along)))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _trees_and_lamps() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var trunk := mat(Color(0.37, 0.29, 0.22))
	var leaf_cols := [Color(0.2, 0.42, 0.24), Color(0.25, 0.47, 0.22), Color(0.18, 0.38, 0.26)]
	var pole := mat(Color(0.22, 0.23, 0.25), 0.4)
	var bulb := mat(Color(1.0, 0.92, 0.7), 0.3)
	bulb.emission_enabled = true
	bulb.emission = Color(1.0, 0.85, 0.55)
	bulb.emission_energy_multiplier = 1.5
	for bx in BLOCKS:
		for bz in BLOCKS:
			var c := _block_centre(bx, bz)
			for s in [-1.0, 1.0]:
				for off in [-27.0, 0.0, 27.0]:
					for horizontal in [true, false]:
						var p := c + (Vector3(off, 0, s * 37.0) if horizontal else Vector3(s * 37.0, 0, off))
						if Vector2(p.x, p.z).length() < ARENA_R + 4.0:
							continue
						if off == 0.0:
							# street lamp facing the road
							box(body, Vector3(0.25, 7.5, 0.25), p + Vector3(0, 3.75, 0), pole)
							var arm := (Vector3(0, 0, s) if horizontal else Vector3(s, 0, 0)) * 1.2
							box(body, Vector3(0.18, 0.18, 2.4) if horizontal else Vector3(2.4, 0.18, 0.18), p + arm + Vector3(0, 7.4, 0), pole, false)
							box(body, Vector3(0.6, 0.22, 0.6), p + arm * 2.0 + Vector3(0, 7.2, 0), bulb, false)
						else:
							box(body, Vector3(0.5, 4.0, 0.5), p + Vector3(0, 2.0, 0), trunk)
							var mi := MeshInstance3D.new()
							var sm := SphereMesh.new()
							sm.radius = 2.3
							sm.height = 4.0
							sm.radial_segments = 12
							sm.rings = 6
							sm.material = mat(leaf_cols[_rng.randi() % leaf_cols.size()])
							mi.mesh = sm
							mi.position = p + Vector3(0, 5.2, 0)
							body.add_child(mi)


func _new_building(c: Vector3, footprint: Vector2, height: float) -> Dictionary:
	var root := StaticBody3D.new()
	root.name = "Building%d" % buildings.size()
	root.position = c
	add_child(root)
	var aabb := AABB(c + Vector3(-footprint.x * 0.5, 0, -footprint.y * 0.5), Vector3(footprint.x, height, footprint.y))
	var b := {"node": root, "aabb": aabb, "height": height, "alive": true, "color": PALETTE[0]}
	buildings.append(b)
	return b


func _tower(c: Vector3, fp: Vector2, h: float, door_side: int = 0) -> void:
	var b := _new_building(c, fp, h)
	var col: Color = PALETTE[_rng.randi() % PALETTE.size()]
	b["color"] = col
	var m := wall_mat(col, true)
	var root: Node3D = b["node"]
	# lower floors you can go into: lobby + ramps up to the window floors (great for sniping)
	var inner_floors := 3 if h < 60.0 else 4
	var base := inner_floors * FLOOR_H
	_shell(root, c, fp, inner_floors, door_side, col.darkened(0.15), false)
	# solid stepped skyscraper above: body, setback, crown, antenna
	var h1 := maxf(h * 0.6, base + 8.0)
	box(root, Vector3(fp.x, h1 - base, fp.y), Vector3(0, base + (h1 - base) * 0.5, 0), m)
	var h2 := h * 0.3
	box(root, Vector3(fp.x * 0.8, h2, fp.y * 0.8), Vector3(0, h1 + h2 * 0.5, 0), m)
	var h3 := h * 0.1
	box(root, Vector3(fp.x * 0.5, h3, fp.y * 0.5), Vector3(0, h1 + h2 + h3 * 0.5, 0), wall_mat(col.darkened(0.25), false))
	box(root, Vector3(0.4, 6, 0.4), Vector3(0, h1 + h2 + h3 + 3, 0), mat(Color(0.3, 0.3, 0.32)), false)
	# metal canopy over the entrance
	var metal := mat(Color(0.5, 0.53, 0.56), 0.35)
	var sgn := 1.0 if door_side == 0 else -1.0
	box(root, Vector3(7.0, 0.3, 2.6), Vector3(0, 3.4, sgn * (fp.y * 0.5 + 1.3)), metal, false)
	# rooftop HVAC units on the setback
	for k in _rng.randi_range(2, 4):
		box(root, Vector3(3.0, 1.4, 2.4), Vector3(_rng.randf_range(-fp.x, fp.x) * 0.3, h1 + 0.7, (fp.y * 0.44 if k % 2 == 0 else -fp.y * 0.44)), metal, false)


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
	_shell(root, c, fp, floors, door_side, col, true)
	# roof wall
	var W := fp.x
	var D := fp.y
	var rm := wall_mat(col.darkened(0.2), false)
	var top := h + 0.5
	box(root, Vector3(W, 1.0, WALL), Vector3(0, top, D * 0.5 - WALL * 0.5), rm)
	box(root, Vector3(W, 1.0, WALL), Vector3(0, top, -D * 0.5 + WALL * 0.5), rm)
	box(root, Vector3(WALL, 1.0, D), Vector3(W * 0.5 - WALL * 0.5, top, 0), rm)
	box(root, Vector3(WALL, 1.0, D), Vector3(-W * 0.5 + WALL * 0.5, top, 0), rm)
	loot_points.append(c + Vector3(W * 0.25, h + 0.6, D * 0.2))


## walls with a doorway and window openings, floors and ramps.
## roof_access = false: the top floor is a closed ceiling (a skyscraper continues above)
func _shell(root: Node3D, c: Vector3, fp: Vector2, floors: int, door_side: int, col: Color, roof_access: bool) -> void:
	var wm := wall_mat(col, true)
	# floors alternate between wood and office carpet; ramps are concrete
	var fm: Material = surface_mat("wood", Color(1, 1, 1), 2.4, 0.7) if _rng.randf() < 0.5 else surface_mat("carpet", Color(1.15, 0.95, 0.75), 4.0, 0.95)
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
		if f == floors and not roof_access:
			box(root, Vector3(W - WALL * 2, slab, D - WALL * 2), Vector3(0, y - slab * 0.5, 0), fm)
			continue
		# slab A: everything to the right of the ramp column
		box(root, Vector3(W - rw - WALL, slab, D), Vector3(x0 + rw + (W - rw - WALL) * 0.5, y - slab * 0.5, 0), fm)
		# slab B: in the ramp column, in front of the hole
		var bz := D - WALL - run - 0.4
		if bz > 0.2:
			box(root, Vector3(rw, slab, bz), Vector3(x0 + rw * 0.5, y - slab * 0.5, z0 + run + 0.4 + bz * 0.5), fm)
	for f in floors:
		var y0 := f * FLOOR_H
		loot_points.append(c + Vector3(x0 + rw + 3.0, y0 + 0.6, 2.0))
		if f == floors - 1 and not roof_access:
			continue
		var length := sqrt(run * run + FLOOR_H * FLOOR_H)
		var ang := atan2(FLOOR_H, run)
		# rises from the front (low) to the back wall (high)
		box(root, Vector3(rw - 0.2, 0.25, length), Vector3(x0 + rw * 0.5, y0 + FLOOR_H * 0.5, z0 + run * 0.5), fm, true, ang)
	# ground floor surface + furniture on every floor
	box(root, Vector3(W - WALL * 2, 0.06, D - WALL * 2), Vector3(0, 0.12, 0), fm, false)
	_furnish(root, W, D, floors - (0 if roof_access else 0), door_side, x0 + rw + 0.6)


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
			for k in 4:
				var horizontal := k % 2 == 0
				var off := _rng.randf_range(-32, 32)
				var side := 1.0 if _rng.randf() < 0.5 else -1.0
				var p := Vector3(t + off, 0, r + side * 9.0) if horizontal else Vector3(r + side * 9.0, 0, t + off)
				if Vector2(p.x, p.z).length() < ARENA_R or absf(p.x) > HALF - 6.0 or absf(p.z) > HALF - 6.0:
					continue       # keep the boss arena and the map's outer walls clear
				if _rng.randf() < 0.5:
					var cm := mat(car_cols[_rng.randi() % car_cols.size()], 0.35)
					var sz := Vector3(4.2, 1.2, 1.9) if horizontal else Vector3(1.9, 1.2, 4.2)
					box(body, sz, p + Vector3(0, 0.75, 0), cm)
					var top := Vector3(2.2, 0.7, 1.7) if horizontal else Vector3(1.7, 0.7, 2.2)
					box(body, top, p + Vector3(0, 1.7, 0), mat(Color(0.15, 0.2, 0.25), 0.1), false)
				elif _rng.randf() < 0.45:
					var yaw := 0.0 if horizontal else PI * 0.5
					vehicle_points.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 1.0, 0)))
				elif _rng.randf() < 0.4:
					loot_points.append(p + Vector3(0, 0.6, 0))


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


# ------------------------------------------------------------------ furniture & chests
var _furn := {}            # material key -> SurfaceTool (merged per building)
var _furn_mats := {}


func _fadd(key: String, m: Material, size: Vector3, pos: Vector3) -> void:
	if not _furn.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_furn[key] = st
		_furn_mats[key] = m
	var st: SurfaceTool = _furn[key]
	var h := size * 0.5
	var faces := [
		[Vector3(0, 0, 1), [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
	]
	for fc in faces:
		var n: Vector3 = fc[0]
		var v: Array = fc[1]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.add_vertex(pos + v[i])


func _fsolid(root: Node3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	root.add_child(cs)


func _furnish(root: Node3D, W: float, D: float, floors: int, door_side: int, x_min: float) -> void:
	_furn.clear()
	_furn_mats.clear()
	var wood := surface_mat("wood", Color(0.85, 0.75, 0.65), 1.2, 0.6)
	var metal := surface_mat("metal", Color(0.45, 0.47, 0.5), 1.5, 0.4)
	var crate := surface_mat("metal", Color(0.36, 0.42, 0.3), 1.2, 0.6)
	var fabric_cols := [Color(0.25, 0.3, 0.42), Color(0.45, 0.2, 0.18), Color(0.3, 0.3, 0.32), Color(0.55, 0.5, 0.42)]
	var fabric := mat(fabric_cols[_rng.randi() % fabric_cols.size()], 0.95)
	var black := mat(Color(0.05, 0.05, 0.06), 0.3)
	var x_max := W * 0.5 - WALL - 0.4
	var z_max := D * 0.5 - WALL - 0.4
	var dz := 1.0 if door_side == 0 else -1.0       # which side the door is on
	var chest_script: Script = load(get_script().resource_path.get_base_dir() + "/chest.gd")
	for f in floors:
		var y := f * FLOOR_H + (0.15 if f == 0 else 0.0)
		var kind := _rng.randi() % 3
		var cx := (x_min + x_max) * 0.5
		# keep a clear lane from the door / ramp to the middle of the room
		var back := -dz * (z_max - 1.2)
		match kind:
			0:  # office: rows of desks with monitors and chairs, filing cabinets on the wall
				for row in 2:
					var zz := -dz * (z_max * 0.15 + row * 3.2)
					for k in 2:
						var xx := cx - 1.2 + k * 2.6
						if xx + 0.8 > x_max:
							continue
						_fadd("wood", wood, Vector3(1.6, 0.06, 0.8), Vector3(xx, y + 0.74, zz))
						_fadd("metal", metal, Vector3(0.06, 0.72, 0.7), Vector3(xx - 0.75, y + 0.36, zz))
						_fadd("metal", metal, Vector3(0.06, 0.72, 0.7), Vector3(xx + 0.75, y + 0.36, zz))
						_fadd("black", black, Vector3(0.6, 0.38, 0.04), Vector3(xx, y + 1.0, zz - 0.25))
						_fadd("fabric", fabric, Vector3(0.5, 0.45, 0.5), Vector3(xx, y + 0.25, zz + 0.65))
						_fadd("fabric", fabric, Vector3(0.5, 0.55, 0.08), Vector3(xx, y + 0.75, zz + 0.88))
						_fsolid(root, Vector3(1.6, 0.8, 0.8), Vector3(xx, y + 0.4, zz))
				for k in 3:
					var zz := -z_max * 0.6 + k * 0.8
					_fadd("metal", metal, Vector3(0.6, 1.3, 0.75), Vector3(x_max - 0.3, y + 0.65, zz))
				_fsolid(root, Vector3(0.6, 1.3, 2.4), Vector3(x_max - 0.3, y + 0.65, -z_max * 0.6 + 0.8))
			1:  # apartment: couch, coffee table, TV, bookshelf
				var zz := back
				_fadd("fabric", fabric, Vector3(2.4, 0.45, 0.95), Vector3(cx, y + 0.225, zz))
				_fadd("fabric", fabric, Vector3(2.4, 0.55, 0.22), Vector3(cx, y + 0.72, zz - dz * 0.36))
				_fadd("fabric", fabric, Vector3(0.22, 0.6, 0.95), Vector3(cx - 1.2, y + 0.4, zz))
				_fadd("fabric", fabric, Vector3(0.22, 0.6, 0.95), Vector3(cx + 1.2, y + 0.4, zz))
				_fsolid(root, Vector3(2.6, 0.9, 1.0), Vector3(cx, y + 0.45, zz))
				_fadd("wood", wood, Vector3(1.2, 0.08, 0.6), Vector3(cx, y + 0.42, zz + dz * 1.4))
				_fadd("wood", wood, Vector3(1.1, 0.38, 0.5), Vector3(cx, y + 0.19, zz + dz * 1.4))
				_fadd("wood", wood, Vector3(1.8, 0.5, 0.45), Vector3(cx, y + 0.25, zz + dz * 3.4))
				_fadd("black", black, Vector3(1.6, 0.9, 0.06), Vector3(cx, y + 1.0, zz + dz * 3.45))
				_fsolid(root, Vector3(1.8, 0.5, 0.5), Vector3(cx, y + 0.25, zz + dz * 3.4))
				_fadd("wood", wood, Vector3(0.4, 2.0, 1.8), Vector3(x_max - 0.2, y + 1.0, 0))
				for sh in 4:
					_fadd("black", black, Vector3(0.05, 0.04, 1.7), Vector3(x_max - 0.39, y + 0.3 + sh * 0.5, 0))
				_fsolid(root, Vector3(0.4, 2.0, 1.8), Vector3(x_max - 0.2, y + 1.0, 0))
			2:  # storage: stacks of crates and metal shelving
				for k in 3:
					var p := Vector3(_rng.randf_range(cx - 1.5, x_max - 0.7), y, _rng.randf_range(-z_max + 0.8, z_max - 0.8) * 0.5 + back * 0.5)
					var stack := _rng.randi_range(1, 2)
					for s in stack:
						_fadd("crate", crate, Vector3(1.1, 1.0, 1.1), p + Vector3(0, 0.5 + s * 1.0, 0))
					_fsolid(root, Vector3(1.1, stack * 1.0, 1.1), p + Vector3(0, stack * 0.5, 0))
				for lvl in 4:
					_fadd("metal", metal, Vector3(0.6, 0.04, 3.0), Vector3(x_max - 0.3, y + 0.3 + lvl * 0.55, -z_max * 0.4))
				for zz in [-z_max * 0.4 - 1.45, -z_max * 0.4 + 1.45]:
					_fadd("metal", metal, Vector3(0.6, 2.0, 0.05), Vector3(x_max - 0.3, y + 1.0, zz))
				_fsolid(root, Vector3(0.6, 2.0, 3.0), Vector3(x_max - 0.3, y + 1.0, -z_max * 0.4))
		# a supply chest on about half the floors
		if _rng.randf() < 0.5:
			var ch: StaticBody3D = chest_script.new()
			ch.position = Vector3(x_max - 0.5, y, z_max * 0.55 * dz)
			ch.rotation.y = -PI * 0.5
			root.add_child(ch)
	for key in _furn:
		var mi := MeshInstance3D.new()
		var st: SurfaceTool = _furn[key]
		mi.mesh = st.commit()
		mi.material_override = _furn_mats[key]
		root.add_child(mi)
	_furn.clear()
