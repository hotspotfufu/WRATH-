extends CharacterBody3D
## A computer-controlled soldier (99 of them).
## Before Thor arrives they roam the streets grabbing loot.
## Once he lands they surround him, keep their distance and open fire.
## They think a few times a second (not every frame) so 100 of them run smoothly.

enum S { LOOT, FIGHT, DEAD }
const CityScript := preload("res://scripts/city.gd")

const ARMOR_COLORS := [Color(0.25, 0.42, 0.75), Color(0.7, 0.2, 0.18), Color(0.35, 0.45, 0.25), Color(0.2, 0.65, 0.7), Color(0.75, 0.55, 0.2), Color(0.45, 0.45, 0.48), Color(0.5, 0.3, 0.6), Color(0.85, 0.85, 0.82)]
const NAMES := ["Rivera", "Okafor", "Chen", "Novak", "Silva", "Kowal", "Reyes", "Haddad", "Ito", "Brooks", "Mensah", "Dubois", "Ortiz", "Varga", "Nkemelu", "Park", "Hale", "Moreau", "Singh", "Larsen", "Costa", "Abara", "Kim", "Ferro"]

var callsign := ""
var health := 100.0
var shield := 50.0
var weapon_id := ""
var city: Node = null

var _s := S.LOOT
var _think := 0.0
var _path: Array[Vector3] = []
var _goal := Vector3.ZERO
var _fire_cd := 0.0
var _stuck := 0.0
var _side_step := Vector3.ZERO
var _side_t := 0.0
var _walk := 0.0
var _speed := 5.0
var _ring_angle := 0.0
var _ring_dist := 25.0

var _body: MeshInstance3D
var _leg_l: Node3D
var _leg_r: Node3D
var _gun: Node3D
var _rig: SoldierRig = null
var _sfx: AudioStreamPlayer3D
static var _meshes := {}


func _ready() -> void:
	add_to_group("soldiers")
	add_to_group("fighters")
	collision_layer = 4
	collision_mask = 1
	floor_max_angle = deg_to_rad(50)
	callsign = "%s" % NAMES[randi() % NAMES.size()]
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	if Models.has_soldier():
		# the bought tactical soldier, animated in code (soldier_rig.gd)
		_rig = SoldierRig.new()
		add_child(_rig)
		_gun = Node3D.new()
		add_child(_gun)
	else:
		var col: Color = ARMOR_COLORS[randi() % ARMOR_COLORS.size()]
		_body = MeshInstance3D.new()
		_body.mesh = _body_mesh(col)
		add_child(_body)
		_leg_l = _leg(col, -0.17)
		_leg_r = _leg(col, 0.17)
		var gm := MeshInstance3D.new()
		gm.mesh = _gun_mesh()
		gm.position = Vector3(0.18, 1.12, -0.42)
		add_child(gm)
		_gun = gm
	_ring_angle = randf() * TAU
	_ring_dist = randf_range(16.0, 38.0)
	_speed = randf_range(4.4, 5.6)
	_think = randf() * 0.5
	_sfx = AudioStreamPlayer3D.new()
	_sfx.unit_size = 12.0
	_sfx.max_distance = 140.0
	_sfx.volume_db = -8.0
	add_child(_sfx)


# ------------------------------------------------------------------ looks
## one mesh for torso + arms + helmet with a gold visor (vertex coloured, 1 draw call)
static func _body_mesh(col: Color) -> ArrayMesh:
	var key := "body_" + col.to_html()
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark := col.darkened(0.45)
	_cube(st, Vector3(0, 0.95, 0), Vector3(0.5, 0.2, 0.32), dark)           # belt / hips
	_cube(st, Vector3(0, 1.28, 0), Vector3(0.62, 0.5, 0.4), col)            # chest plate
	_cube(st, Vector3(0, 1.3, 0.24), Vector3(0.42, 0.42, 0.14), dark)       # backpack
	_cube(st, Vector3(-0.42, 1.42, 0), Vector3(0.24, 0.22, 0.34), col.lightened(0.1))   # shoulders
	_cube(st, Vector3(0.42, 1.42, 0), Vector3(0.24, 0.22, 0.34), col.lightened(0.1))
	_cube(st, Vector3(-0.36, 1.15, -0.12), Vector3(0.14, 0.4, 0.14), dark)  # arms reaching to the gun
	_cube(st, Vector3(0.36, 1.15, -0.18), Vector3(0.14, 0.4, 0.14), dark)
	_cube(st, Vector3(0, 1.72, 0), Vector3(0.34, 0.34, 0.38), col)          # helmet
	_cube(st, Vector3(0, 1.73, -0.17), Vector3(0.26, 0.14, 0.08), Color(0.95, 0.68, 0.2))   # gold visor
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.45
	m.metallic = 0.35
	st.set_material(m)
	_meshes[key] = st.commit()
	return _meshes[key]


func _leg(col: Color, x: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, 0.9, 0)
	add_child(pivot)
	var key := "leg_" + col.to_html()
	if not _meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_cube(st, Vector3(0, -0.4, 0), Vector3(0.2, 0.8, 0.24), col.darkened(0.3))
		_cube(st, Vector3(0, -0.85, -0.05), Vector3(0.22, 0.12, 0.32), Color(0.12, 0.12, 0.13))
		st.generate_normals()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.6
		st.set_material(m)
		_meshes[key] = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	pivot.add_child(mi)
	return pivot


static func _gun_mesh() -> ArrayMesh:
	if _meshes.has("gun"):
		return _meshes["gun"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cube(st, Vector3(0, 0, -0.1), Vector3(0.08, 0.12, 0.6), Color(0.15, 0.16, 0.17))
	_cube(st, Vector3(0, -0.1, 0.02), Vector3(0.06, 0.14, 0.08), Color(0.1, 0.1, 0.1))
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	st.set_material(m)
	_meshes["gun"] = st.commit()
	return _meshes["gun"]


static func _cube(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var v := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [3, 7, 6, 2], [0, 1, 5, 4]]
	st.set_color(col)
	for f in faces:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(c + v[f[i]])


# ------------------------------------------------------------------ brain
func _physics_process(delta: float) -> void:
	if _s == S.DEAD:
		return
	_think -= delta
	_fire_cd -= delta
	if _think <= 0.0:
		_think = randf_range(0.3, 0.55)
		_decide()

	# walk toward the next waypoint
	var move := Vector3.ZERO
	if _side_t > 0.0:
		_side_t -= delta
		move = _side_step
	elif _path.size() > 0:
		var to := _path[0] - global_position
		to.y = 0
		if to.length() < 1.2:
			_path.pop_front()
		else:
			move = to.normalized()
	velocity.x = move.x * _speed
	velocity.z = move.z * _speed
	if not is_on_floor():
		velocity.y -= 24.0 * delta
	move_and_slide()
	if move.length() > 0.1:
		if is_on_wall() and _side_t <= 0.0:
			_stuck += delta
			if _stuck > 0.4:
				_stuck = 0.0
				_side_step = move.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
				_side_t = randf_range(0.5, 1.0)
		var face := atan2(-move.x, -move.z)
		if _s != S.FIGHT:
			rotation.y = lerp_angle(rotation.y, face, minf(1.0, delta * 8.0))
	# leg swing
	var hv := Vector2(velocity.x, velocity.z).length()
	_walk += delta * hv * 1.8
	if _rig:
		_rig.aiming = _s == S.FIGHT
		_rig.animate(delta, hv)
		_gun.global_position = _rig.muzzle_position()
	else:
		var swing := sin(_walk) * 0.6 * minf(1.0, hv / 3.0)
		_leg_l.rotation.x = swing
		_leg_r.rotation.x = -swing
	if global_position.y < -20.0:
		take_damage(9999, null)


func _decide() -> void:
	var game := get_tree().get_first_node_in_group("game")
	var boss: Node3D = null
	if game:
		boss = game.get("boss") as Node3D
	if boss and is_instance_valid(boss) and not bool(boss.get("dead")):
		_s = S.FIGHT
		_fight(boss)
	else:
		_s = S.LOOT
		_loot()


func _loot() -> void:
	# pick up anything close by
	for p in get_tree().get_nodes_in_group("pickups"):
		var d := (p as Node3D).global_position.distance_to(global_position)
		if d < 1.6:
			p.call("take", self)
			break
	if _path.size() > 0:
		return
	# head for some loot on the street, or just wander to another corner
	var target := Vector3.ZERO
	var found := false
	var best := 60.0
	for p in get_tree().get_nodes_in_group("pickups"):
		var pos := (p as Node3D).global_position
		if pos.y > 1.6:
			continue
		var d := pos.distance_to(global_position)
		if d < best and randf() < 0.5:
			best = d
			target = pos
			found = true
	if not found and city:
		var nodes: Array = city.get("road_nodes")
		target = nodes[randi() % nodes.size()]
	_route_to(target)


func _fight(boss: Node3D) -> void:
	var bp := boss.global_position
	var to_boss := bp - global_position
	to_boss.y = 0
	var dist := to_boss.length()
	rotation.y = atan2(-to_boss.x, -to_boss.z)
	if weapon_id == "":
		weapon_id = "rifle" if randf() < 0.6 else "pistol"
		if _rig:
			_rig.set_gun(weapon_id)
	# keep a ring around Thor; back off if he gets too close
	_ring_angle += randf_range(-0.25, 0.25)
	var want := bp + Vector3(cos(_ring_angle), 0, sin(_ring_angle)) * _ring_dist
	if dist < 9.0:
		want = global_position - to_boss.normalized() * 10.0
	if dist > _ring_dist * 1.6 or dist < 9.0 or _path.is_empty():
		_path = [want]
	# shoot
	var d := Weapons.info(weapon_id)
	if _fire_cd <= 0.0 and dist < minf(float(d["range"]), 90.0):
		_fire_cd = maxf(float(d["rate"]) * 3.0, 0.35) + randf_range(0.0, 0.6)
		var eye := global_position + Vector3(0, 1.6, 0)
		var aim := bp + Vector3(randf_range(-1.5, 1.5), randf_range(2.0, 6.0), randf_range(-1.5, 1.5))
		var q := PhysicsRayQueryParameters3D.create(eye, aim, 1 | 8)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var end := aim
		if not hit.is_empty():
			end = hit["position"]
			var col: Node = hit["collider"]
			if col == boss or (col and col.get_parent() == boss):
				var accuracy := 0.55 if dist > 40.0 else 0.8
				if randf() < accuracy:
					boss.call("take_damage", float(d["damage"]) * float(d["pellets"]) * 1.6, self)   # 25 soldiers hit as hard as 100 used to
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(global_position) < 70.0:
			FX.tracer(get_parent(), _gun.global_position, end, Color(1.0, 0.85, 0.5), 0.04)
			if _rig:
				_rig.kick()
			_sfx.stream = Sounds.gun(weapon_id)
			_sfx.play()


## walk along the road grid so soldiers don't run into buildings
func _route_to(target: Vector3) -> void:
	_path.clear()
	if city == null:
		_path.append(target)
		return
	var a := _nearest_node(global_position)
	var b := _nearest_node(target)
	_path.append(a)
	_path.append(Vector3(a.x, 0, b.z))
	_path.append(b)
	_path.append(target)


func _nearest_node(p: Vector3) -> Vector3:
	var cell: float = CityScript.CELL
	var half: float = CityScript.HALF
	var x := -half + roundf((p.x + half) / cell) * cell
	var z := -half + roundf((p.z + half) / cell) * cell
	return Vector3(x, 0, z)


# ------------------------------------------------------------------ items & damage
func give_weapon(id: String) -> void:
	if id != "hammer":
		weapon_id = id
		if _rig:
			_rig.set_gun(id)


func give_ammo() -> void:
	pass


func give_armor() -> void:
	shield = minf(100.0, shield + 50.0)


func heal(amount: float) -> void:
	health = minf(100.0, health + amount)


func take_damage(amount: float, from: Node) -> void:
	if _s == S.DEAD:
		return
	if from and (from.is_in_group("fighters")):
		return            # no friendly fire
	var to_shield := minf(shield, amount)
	shield -= to_shield
	health -= amount - to_shield
	if health <= 0.0:
		_die(from)


func _die(from: Node) -> void:
	_s = S.DEAD
	remove_from_group("fighters")
	collision_layer = 0
	velocity = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", -PI * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position:y", position.y + 0.15, 0.35)
	tw.tween_interval(4.0)
	tw.tween_property(self, "position:y", position.y - 1.5, 1.5)
	tw.tween_callback(queue_free)
	get_tree().call_group("game", "on_fighter_died", self)
