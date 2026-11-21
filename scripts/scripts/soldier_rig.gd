class_name SoldierRig
extends Node3D
## The bought tactical soldier model, dressed from its parts and animated in code.
##
## The model has a full skeleton but came without animations, so this script moves
## the bones itself every frame:
##   * legs swing and knees bend while walking or running
##   * both arms reach for the gun with two-bone IK (right hand on the grip, left
##     hand on the fore-end), gun up when fighting, lower while running around
##   * a kick on every shot
## A detailed version is drawn up close and a light one far away.
##
## The skeleton is "Z-up" (Unreal style): up = +Z, the soldier faces -Y.
## Skeleton3D's own transform turns that into the game's Y-up space, so
## skeleton.global_transform * bone pose = a bone's real position in the world.

const ALWAYS := ["Body", "Balaclava", "Helmet5", "Gloves4", "Pants5", "Armor4", "Shoes_Low", "Magazine_Pocket4", "Radio", "Helmet_Headphones"]
const FAR_PARTS := ["Body", "Balaclava", "Helmet5", "Gloves4", "Pants5", "Armor4", "Shoes_Low", "Jacket", "Pullover4", "Backpack2"]
const NEAR_DIST := 22.0

## camouflage palettes: [main, second, dark, armour, helmet, balaclava]
const CAMO := [
	[Color(0.36, 0.38, 0.25), Color(0.25, 0.29, 0.18), Color(0.15, 0.14, 0.1), Color(0.27, 0.29, 0.2), Color(0.3, 0.32, 0.23), Color(0.12, 0.12, 0.1)],   # woodland
	[Color(0.66, 0.58, 0.44), Color(0.54, 0.45, 0.32), Color(0.38, 0.3, 0.21), Color(0.52, 0.44, 0.32), Color(0.55, 0.48, 0.36), Color(0.45, 0.38, 0.28)],  # desert
	[Color(0.2, 0.21, 0.23), Color(0.12, 0.13, 0.14), Color(0.06, 0.06, 0.07), Color(0.1, 0.1, 0.11), Color(0.13, 0.13, 0.14), Color(0.06, 0.06, 0.06)],    # black ops
	[Color(0.47, 0.49, 0.5), Color(0.33, 0.35, 0.37), Color(0.2, 0.21, 0.23), Color(0.3, 0.32, 0.34), Color(0.36, 0.38, 0.4), Color(0.15, 0.15, 0.16)],    # urban grey
]
const SKIN := [Color(0.85, 0.66, 0.52), Color(0.62, 0.45, 0.33), Color(0.42, 0.29, 0.21), Color(0.78, 0.6, 0.45)]

var gun_id := ""
var aiming := false

var _model: Node3D
var _sk: Skeleton3D
var _near: Array[MeshInstance3D] = []
var _far: Array[MeshInstance3D] = []
var _is_near := true
var _lod_t := 0.0
var _gun: Node3D
var _muzzle: Node3D
var _phase := 0.0
var _kick := 0.0
var _raise := 0.0
var _skip := 0
var _b := {}
var _len := {}

static var _mats := {}


func _ready() -> void:
	var ps: PackedScene = Models.res("soldier.scn")
	_model = ps.instantiate()
	_model.rotation.y = PI          # the model faces +Z, soldiers face -Z
	add_child(_model)
	_sk = _model.get_node("Skeleton")
	for n in ["pelvis", "spine_01", "spine_03", "spine_05", "neck_01", "head",
			"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
			"thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
		_b[n] = _sk.find_bone(n)
	for side in ["l", "r"]:
		_len["up_" + side] = _bone_dist("upperarm_" + side, "lowerarm_" + side)
		_len["lo_" + side] = _bone_dist("lowerarm_" + side, "hand_" + side)
	_dress()
	_muzzle = Node3D.new()
	add_child(_muzzle)
	set_gun("rifle")


func _bone_dist(a: String, b: String) -> float:
	return (_sk.get_bone_global_rest(_b[a]).origin - _sk.get_bone_global_rest(_b[b]).origin).length()


# ------------------------------------------------------------------ looks
func _dress() -> void:
	var camo: int = randi() % CAMO.size()
	var skin: int = randi() % SKIN.size()
	var top := "Jacket" if randf() < 0.55 else "Pullover4"
	var head_gear: String = ["Helmet_Night_Vision", "Helmet_Accesories_Low_2", ""][randi() % 3]
	var pack: String = ["Backpack2", "Back_Bag", ""][randi() % 3]
	var wanted := ALWAYS.duplicate()
	wanted.append(top)
	if head_gear != "":
		wanted.append(head_gear)
	if pack != "":
		wanted.append(pack)
	if randf() < 0.5:
		wanted.append("Glassess_Low")
	if randf() < 0.4:
		wanted.append("Helmet_Light")
	for c in _model.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var near := mi.name.begins_with("hi_")
		var part := String(mi.name).substr(3)
		var on := part in wanted and (near or part in FAR_PARTS)
		mi.visible = false
		if not on:
			mi.queue_free()
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for s in mi.mesh.get_surface_count():
			mi.set_surface_override_material(s, _mat(mi.mesh.surface_get_name(s), camo, skin))
		if near:
			_near.append(mi)
		else:
			_far.append(mi)
	_set_lod(true)


## colour (or the real texture, if it was supplied) for each kind of clothing
static func _mat(surface: String, camo: int, skin: int) -> Material:
	var key := "%s_%d_%d" % [surface, camo, skin]
	if _mats.has(key):
		return _mats[key]
	var tex_name := "sol_" + surface.to_lower()
	var m: StandardMaterial3D
	if Models.has(tex_name + "_a.jpg"):
		m = Models.pbr(tex_name)
	else:
		m = StandardMaterial3D.new()
		var p: Array = CAMO[camo]
		var s := surface.to_lower()
		m.roughness = 0.9
		if s.begins_with("body"):
			m.albedo_color = SKIN[skin]
			m.roughness = 0.6
		elif s.begins_with("balak"):
			m.albedo_color = p[5]
		elif s.begins_with("pants") or s.begins_with("jacket") or s.begins_with("pullover"):
			m.albedo_color = Color.WHITE
			m.albedo_texture = _camo_tex(camo, s.begins_with("pull"))
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 2.2
		elif s.begins_with("armor") or s.begins_with("magazine") or s.begins_with("backpack"):
			m.albedo_color = p[3]
			m.roughness = 0.85
		elif s == "helmet":
			m.albedo_color = p[4]
			m.roughness = 0.6
			m.metallic = 0.15
		elif s.begins_with("helmet_acc"):
			m.albedo_color = Color(0.09, 0.09, 0.1)
			m.roughness = 0.45
			m.metallic = 0.5
		elif s.begins_with("gloves"):
			m.albedo_color = Color(0.1, 0.1, 0.1)
		elif s.begins_with("shoes"):
			m.albedo_color = Color(0.22, 0.17, 0.12)
		elif s.contains("glass"):
			m.albedo_color = Color(0.05, 0.05, 0.06)
			m.roughness = 0.1
			m.metallic = 0.6
		else:
			m.albedo_color = p[2]
	_mats[key] = m
	return m


## a small seamless camouflage pattern made from noise in the palette's colours
static func _camo_tex(camo: int, plain: bool) -> Texture2D:
	var key := "camo_%d_%s" % [camo, plain]
	if _mats.has(key):
		return _mats[key]
	var p: Array = CAMO[camo]
	var t := NoiseTexture2D.new()
	t.width = 128
	t.height = 128
	t.seamless = true
	var n := FastNoiseLite.new()
	n.seed = 7 + camo
	n.frequency = 0.035
	n.fractal_octaves = 2
	t.noise = n
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	if plain:
		g.set_color(0, (p[0] as Color).darkened(0.08))
		g.set_color(1, p[0])
	else:
		g.set_color(0, p[2])
		g.set_offset(1, 0.38)
		g.set_color(1, p[1])
		g.add_point(0.55, p[0])
		g.add_point(0.8, (p[0] as Color).lightened(0.12))
	t.color_ramp = g
	_mats[key] = t
	return t


func _set_lod(near: bool) -> void:
	_is_near = near
	for mi in _near:
		mi.visible = near
	for mi in _far:
		mi.visible = not near


## put this kind of gun in the soldier's hands (the bought models)
func set_gun(id: String) -> void:
	if id == "" or id == "hammer" or id == "rocket":
		id = "rifle"
	if id == gun_id:
		return
	gun_id = id
	if _gun:
		_gun.queue_free()
	if Models.has_gun(id):
		_gun = Models.gun(id)
	else:
		_gun = Weapons.build_model(id)
	_gun.rotation.y = PI          # the model space faces +Z
	_model.add_child(_gun)
	for c in _gun.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## where shots come out (for tracers)
func muzzle_position() -> Vector3:
	return _muzzle.global_position


func kick() -> void:
	_kick = 1.0


# ------------------------------------------------------------------ animation
## speed: how fast the soldier is moving (m/s)
func animate(delta: float, speed: float) -> void:
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.4
		var cam := get_viewport().get_camera_3d()
		if cam:
			var d := cam.global_position.distance_to(global_position)
			var want_near := d < NEAR_DIST
			if want_near != _is_near:
				_set_lod(want_near)
			# far away soldiers don't need every frame of animation
			_skip = 0 if d < 40.0 else (1 if d < 90.0 else 3)
	_phase += delta * (2.4 + speed * 1.25)
	_kick = maxf(0.0, _kick - delta * 9.0)
	_raise = move_toward(_raise, 1.0 if aiming else 0.0, delta * 3.0)
	if _skip > 0 and Engine.get_physics_frames() % (_skip + 1) != 0:
		return
	_pose(minf(1.0, speed / 5.0))


func _pose(run: float) -> void:
	_sk.reset_bone_poses()
	var up := Vector3(0, 0, 1)
	var fwd := Vector3(0, -1, 0)
	var right := Vector3(-1, 0, 0)
	var s := sin(_phase)
	var c := cos(_phase)
	# --- body: lean into the run, bob, lean back a touch when firing
	_turn("spine_01", right, -0.12 * run - 0.06 * _raise + 0.05 * _kick)
	_turn("pelvis", up, s * 0.08 * run)
	_turn("spine_03", up, -s * 0.1 * run)
	# --- legs: swing from the hip, bend the knee on the forward swing
	var amp := 0.75 * run
	_turn("thigh_l", right, s * amp)
	_turn("thigh_r", right, -s * amp)
	_turn("calf_l", right, -maxf(0.0, -c) * 1.1 * run - 0.05)
	_turn("calf_r", right, -maxf(0.0, c) * 1.1 * run - 0.05)
	_turn("foot_l", right, 0.25 * s * run)
	_turn("foot_r", right, -0.25 * s * run)
	# --- the gun: shouldered when fighting, low-ready while running around
	var chest := _gp(_b["spine_05"]).origin
	var low := 1.0 - _raise
	var gun_pos := chest + fwd * (0.3 - 0.07 * _kick) + right * (0.13 + 0.03 * low) + up * (-0.03 - 0.22 * low + 0.025 * sin(_phase * 2.0) * run)
	var aim_basis := Basis(right, -0.45 * low + 0.12 * _kick)     # tip the muzzle down while running
	var gun_skel := Transform3D(aim_basis * Basis(Vector3(0, 0, 1), PI) * Basis(Vector3(1, 0, 0), PI * 0.5), gun_pos)
	# skeleton space -> model space for the gun node (the gun model points down -Z)
	var to_model := _sk.transform
	var gm := to_model * gun_skel
	_gun.transform = Transform3D(gm.basis, gm.origin)
	# grips, in skeleton space
	var grip_r := Weapons.GRIPS.get(gun_id, Weapons.GRIPS["rifle"])[0] as Vector3
	var grip_l: Vector3 = Models.left_grip(gun_id) if Models.has_gun(gun_id) else Weapons.GRIPS.get(gun_id, Weapons.GRIPS["rifle"])[1]
	var gun_in_skel := to_model.affine_inverse() * _gun.transform
	_two_bone("r", gun_in_skel * grip_r, right * 0.6 - up)
	_two_bone("l", gun_in_skel * grip_l, -right * 0.4 - up)
	# muzzle for tracers
	_muzzle.global_position = _gun.global_transform * Vector3(0, 0, -0.9)
	# head follows the aim a little
	_turn("head", right, 0.15 * _raise)


## a bone's pose in skeleton space, built from the local poses we just set
## (Skeleton3D only refreshes its own copy later in the frame)
func _gp(b: int) -> Transform3D:
	var t := _sk.get_bone_pose(b)
	var p := _sk.get_bone_parent(b)
	while p >= 0:
		t = _sk.get_bone_pose(p) * t
		p = _sk.get_bone_parent(p)
	return t


## rotate a bone about an axis given in skeleton space
func _turn(bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0005:
		return
	var b: int = _b[bone]
	var g := _gp(b)
	_set_global_basis(b, Basis(axis, angle) * g.basis)


func _set_global_basis(b: int, basis: Basis) -> void:
	var p := _sk.get_bone_parent(b)
	var pb := _gp(p).basis if p >= 0 else Basis()
	_sk.set_bone_pose_rotation(b, (pb.orthonormalized().inverse() * basis.orthonormalized()).get_rotation_quaternion())


## point a bone so that its child lies along `dir`
func _aim(bone: int, child: int, dir: Vector3) -> void:
	var g := _gp(bone)
	var cur := _gp(child).origin - g.origin
	if cur.length() < 0.0001 or dir.length() < 0.0001:
		return
	var q := Quaternion(cur.normalized(), dir.normalized())
	_set_global_basis(bone, Basis(q) * g.basis)


## two-bone arm IK: shoulder -> elbow -> hand on `target`, elbow pushed toward `pole`
func _two_bone(side: String, target: Vector3, pole: Vector3) -> void:
	var ub: int = _b["upperarm_" + side]
	var lb: int = _b["lowerarm_" + side]
	var hb: int = _b["hand_" + side]
	var a: float = _len["up_" + side]
	var bl: float = _len["lo_" + side]
	var sh := _gp(ub).origin
	var to := target - sh
	var d := clampf(to.length(), absf(a - bl) + 0.01, a + bl - 0.002)
	var dir := to.normalized()
	var x := (a * a - bl * bl + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, a * a - x * x))
	var side_dir := (pole - dir * pole.dot(dir)).normalized()
	var elbow := sh + dir * x + side_dir * h
	_aim(ub, lb, elbow - sh)
	_aim(lb, hb, sh + dir * d - elbow)
