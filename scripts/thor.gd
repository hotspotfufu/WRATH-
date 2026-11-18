extends CharacterBody3D
## THOR, GOD OF THUNDER - the first boss.
## Crashes down from the sky, then hunts every soldier on the map:
##   * HAMMER THROW - Mjolnir flies at a target, smashes what it hits, flies back
##   * BUILDING SMASH - leaps onto a building with soldiers in it and brings it down
##   * LIGHTNING - calls bolts down on groups of soldiers (watch for the blue circles)
##   * STOMP - shockwave when you get too close
##   * LEAP - jumps across the city to reach far-away soldiers
## Gets faster and angrier below half health. Headshots do double damage.

signal defeated

enum S { FALL, ROAR, IDLE, WALK, THROW, LEAP, SMASH, LIGHTNING, STOMP, DEAD }

## Thor has 3 health bars. Each bar is a full god's worth of health:
## bar 3 = blue, bar 2 = purple, bar 1 = gold. Breaking a bar makes him stronger.
const BARS := 3
const BAR_HP := 20000.0
var max_hp := BAR_HP * BARS
var hp := BAR_HP * BARS
var damage_taken := 0.4           ## Thor only takes 40% of incoming damage
var _phase_shield := 0.0          ## brief invulnerability when a bar breaks
var dead := false
var city: Node = null

var _s := S.FALL
var _t := 0.0
var _target: Node3D = null
var _cd := {"throw": 2.0, "smash": 6.0, "lightning": 5.0, "stomp": 0.0, "leap": 8.0}
var _hammer_out := false
var _enraged := false
var _rage_level := 0             ## 0, 1, 2: rises with each broken health bar
var _did := false
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
var _smash_index := -1
var _walk := 0.0
var _flash := 0.0
var _strikes: Array = []

# body parts (pivots for simple animation)
var _rig: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _hammer_hand: Node3D
var _cape: MeshInstance3D
var _mats: Array[StandardMaterial3D] = []
var _flash_mats: Array[StandardMaterial3D] = []
var _voice: AudioStreamPlayer3D

const H := 7.0     # height in metres


func _ready() -> void:
	add_to_group("boss")
	collision_layer = 8
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 1.3
	cap.height = H
	cs.shape = cap
	cs.position.y = H * 0.5
	add_child(cs)
	var head := Area3D.new()
	head.name = "HeadHitbox"
	head.collision_layer = 8
	head.collision_mask = 0
	var hs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.75
	hs.shape = sp
	head.add_child(hs)
	head.position.y = H - 0.7
	add_child(head)
	_build_model()
	_voice = AudioStreamPlayer3D.new()
	_voice.unit_size = 60.0
	_voice.max_distance = 600.0
	add_child(_voice)
	velocity = Vector3(0, -60, 0)


# ------------------------------------------------------------------ model
func _m(col: Color, rough: float = 0.6, metal: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	else:
		_flash_mats.append(m)
	_mats.append(m)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_model() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var skin := _m(Color(0.86, 0.66, 0.52))
	var armor := _m(Color(0.62, 0.64, 0.7), 0.3, 0.85)
	var dark := _m(Color(0.16, 0.16, 0.2), 0.7)
	var cloth := _m(Color(0.2, 0.22, 0.32), 0.85)
	var red := _m(Color(0.7, 0.08, 0.08), 0.8)
	var hair := _m(Color(0.85, 0.55, 0.2), 0.9)
	var eyes := _m(Color(0.6, 0.85, 1.0), 0.2, 0.0, 4.0)
	var s := H / 7.0
	# legs
	_leg_l = Node3D.new(); _leg_l.position = Vector3(-0.55, 3.1, 0) * s; _rig.add_child(_leg_l)
	_leg_r = Node3D.new(); _leg_r.position = Vector3(0.55, 3.1, 0) * s; _rig.add_child(_leg_r)
	for leg in [_leg_l, _leg_r]:
		_box(leg, Vector3(0.8, 1.7, 0.85) * s, Vector3(0, -0.85, 0) * s, cloth)
		_box(leg, Vector3(0.85, 1.3, 0.9) * s, Vector3(0, -2.35, 0) * s, dark)
		_box(leg, Vector3(0.9, 0.4, 1.3) * s, Vector3(0, -2.9, -0.2) * s, dark)
	# torso
	_box(_rig, Vector3(2.0, 0.45, 1.1) * s, Vector3(0, 3.25, 0) * s, dark)              # belt
	_box(_rig, Vector3(2.3, 2.0, 1.25) * s, Vector3(0, 4.45, 0) * s, armor)             # chest
	for i in 3:
		_box(_rig, Vector3(0.36, 0.36, 0.1) * s, Vector3((i - 1) * 0.7, 4.6, -0.66) * s, _m(Color(0.75, 0.78, 0.85), 0.2, 0.9))   # chest discs
	_box(_rig, Vector3(2.9, 0.5, 1.4) * s, Vector3(0, 5.5, 0) * s, armor)               # shoulders
	# cape
	_cape = _box(_rig, Vector3(2.6, 4.4, 0.12) * s, Vector3(0, 3.6, 0.72) * s, red)
	# head
	_box(_rig, Vector3(0.5, 0.35, 0.5) * s, Vector3(0, 5.9, 0) * s, skin)
	_box(_rig, Vector3(0.95, 1.0, 0.95) * s, Vector3(0, 6.45, 0) * s, skin)
	_box(_rig, Vector3(1.0, 0.75, 0.4) * s, Vector3(0, 6.05, -0.4) * s, hair)          # beard
	_box(_rig, Vector3(1.05, 0.5, 1.05) * s, Vector3(0, 6.9, 0.05) * s, armor)          # helmet
	_box(_rig, Vector3(0.18, 0.12, 0.05) * s, Vector3(-0.22, 6.55, -0.48) * s, eyes)
	_box(_rig, Vector3(0.18, 0.12, 0.05) * s, Vector3(0.22, 6.55, -0.48) * s, eyes)
	for side in [-1.0, 1.0]:
		var wing := _box(_rig, Vector3(0.1, 0.7, 0.6) * s, Vector3(side * 0.62, 7.05, 0.1) * s, _m(Color(0.92, 0.92, 0.95), 0.4, 0.3))
		wing.rotation.z = -side * 0.5
		_box(_rig, Vector3(0.6, 1.2, 0.5) * s, Vector3(side * 0.6, 6.2, 0.45) * s, hair)   # long hair
	# arms
	_arm_l = Node3D.new(); _arm_l.position = Vector3(-1.4, 5.4, 0) * s; _rig.add_child(_arm_l)
	_arm_r = Node3D.new(); _arm_r.position = Vector3(1.4, 5.4, 0) * s; _rig.add_child(_arm_r)
	for arm in [_arm_l, _arm_r]:
		_box(arm, Vector3(0.65, 1.3, 0.65) * s, Vector3(0, -0.65, 0) * s, skin)
		_box(arm, Vector3(0.72, 1.2, 0.72) * s, Vector3(0, -1.85, 0) * s, armor)
		_box(arm, Vector3(0.6, 0.5, 0.6) * s, Vector3(0, -2.65, 0) * s, skin)
	# Mjolnir
	_hammer_hand = Node3D.new()
	_hammer_hand.position = Vector3(0, -2.75, -0.3) * s
	_arm_r.add_child(_hammer_hand)
	_build_hammer(_hammer_hand, s)


func _build_hammer(parent: Node3D, s: float) -> void:
	_box(parent, Vector3(0.18, 1.6, 0.18) * s, Vector3(0, -0.2, 0) * s, _m(Color(0.35, 0.22, 0.12), 0.8))
	_box(parent, Vector3(1.3, 0.8, 0.85) * s, Vector3(0, -1.1, 0) * s, _m(Color(0.62, 0.64, 0.68), 0.25, 0.9))
	_box(parent, Vector3(1.32, 0.12, 0.87) * s, Vector3(0, -1.1, 0) * s, _m(Color(0.55, 0.8, 1.0), 0.1, 0.0, 3.0))


# ------------------------------------------------------------------ brain
func _physics_process(delta: float) -> void:
	_t += delta
	for k in _cd:
		_cd[k] -= delta * (1.0 + 0.45 * _rage_level)
	_phase_shield = maxf(0.0, _phase_shield - delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	match _s:
		S.FALL:
			velocity.y -= 40.0 * delta
			move_and_slide()
			if is_on_floor():
				_land()
		S.ROAR:
			_pose(0.0, -2.6, -2.6, 0.0)
			if _t > 2.2:
				_go(S.IDLE)
		S.IDLE:
			_pose(0.0, 0.2, -0.3, 0.0)
			velocity.x = 0
			velocity.z = 0
			_gravity(delta)
			if _t > maxf(0.15, 0.6 - 0.2 * _rage_level):
				_choose()
		S.WALK:
			_walk_toward(delta)
		S.THROW:
			_do_throw(delta)
		S.LEAP:
			_do_leap(delta)
		S.SMASH:
			_do_smash(delta)
		S.LIGHTNING:
			_do_lightning(delta)
		S.STOMP:
			_do_stomp(delta)
		S.DEAD:
			pass
	_update_strikes(delta)
	_tint()


func _tint() -> void:
	# red flash when hit
	var shield := _phase_shield > 0.0
	for m in _flash_mats:
		m.emission_enabled = _flash > 0.03 or shield
		m.emission = Color(0.5, 0.75, 1.0) if shield else Color(1.0, 0.25, 0.2)
		m.emission_energy_multiplier = (0.8 + 0.4 * sin(_t * 20.0)) if shield else _flash * 0.5
	_rig.scale = Vector3.ONE * (1.0 + _flash * 0.03)
	if _cape:
		_cape.rotation.x = 0.15 + sin(_t * 3.0) * 0.08 + velocity.length() * 0.02


func _gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 30.0 * delta
	else:
		velocity.y = 0
	move_and_slide()


func _go(s: S) -> void:
	_s = s
	_t = 0.0
	_did = false


func _pick_target() -> void:
	var fighters := get_tree().get_nodes_in_group("fighters")
	if fighters.is_empty():
		_target = null
		return
	# prefer someone close, sometimes go after the real player
	var best: Node3D = null
	var bd := INF
	for f in fighters:
		var d := (f as Node3D).global_position.distance_to(global_position)
		if f.is_in_group("player"):
			d *= 0.7
		d += randf() * 15.0
		if d < bd:
			bd = d
			best = f
	_target = best


func _choose() -> void:
	_pick_target()
	if _target == null:
		_go(S.IDLE)
		return
	var tp := _target.global_position
	var dist := Vector2(tp.x - global_position.x, tp.z - global_position.z).length()
	_face(tp)
	var near := _count_near(8.0)
	if near >= 2 and _cd["stomp"] <= 0.0:
		_go(S.STOMP)
	elif city and _cd["smash"] <= 0.0 and city.call("building_at", tp, 1.5) >= 0 and dist < 70.0:
		_smash_index = city.call("building_at", tp, 1.5)
		_go(S.SMASH)
	elif dist > 70.0 and _cd["leap"] <= 0.0:
		_leap_to = tp + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		_go(S.LEAP)
	elif _cd["lightning"] <= 0.0 and dist < 60.0:
		_go(S.LIGHTNING)
	elif not _hammer_out and _cd["throw"] <= 0.0 and dist > 6.0 and dist < 80.0:
		_go(S.THROW)
	else:
		_go(S.WALK)


func _face(p: Vector3) -> void:
	var to := p - global_position
	if Vector2(to.x, to.z).length() > 0.1:
		rotation.y = atan2(-to.x, -to.z)


func _count_near(r: float) -> int:
	var n := 0
	for f in get_tree().get_nodes_in_group("fighters"):
		if (f as Node3D).global_position.distance_to(global_position) < r:
			n += 1
	return n


## arms / legs pose: leg swing, left arm, right arm, lean
func _pose(legs: float, arm_l: float, arm_r: float, lean: float) -> void:
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, legs, 0.2)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -legs, 0.2)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arm_l, 0.2)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, arm_r, 0.2)
	_rig.rotation.x = lerpf(_rig.rotation.x, lean, 0.15)


# ------------------------------------------------------------------ actions
func _walk_toward(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or _t > 2.5:
		_go(S.IDLE)
		return
	var to := _target.global_position - global_position
	to.y = 0
	_face(_target.global_position)
	var speed := 5.5 + 1.8 * _rage_level
	velocity.x = -sin(rotation.y) * speed
	velocity.z = -cos(rotation.y) * speed
	_gravity(delta)
	_walk += delta * speed * 0.9
	var sw := sin(_walk) * 0.5
	_pose(sw, -sw * 0.6, 0.3 + sw * 0.3, 0.08)
	if absf(sin(_walk)) > 0.98 and fmod(_walk, PI) < 0.2:
		_shake(0.05, 30.0)
	# crush anything he walks through
	for f in get_tree().get_nodes_in_group("fighters"):
		if (f as Node3D).global_position.distance_to(global_position) < 2.2:
			f.call("take_damage", 25.0 * delta * 10.0, self)
	if is_on_wall() and city:
		var i: int = city.call("nearest_building", global_position, 4.0)
		if i >= 0:
			city.call("smash", i, global_position, self)
	if to.length() < 7.0:
		_go(S.STOMP if _cd["stomp"] <= 0.0 else S.IDLE)


func _do_throw(_delta: float) -> void:
	velocity = Vector3.ZERO
	if _target == null or not is_instance_valid(_target):
		_go(S.IDLE)
		return
	_face(_target.global_position)
	if _t < 0.55:
		_pose(0.0, 0.3, 2.6, -0.1)        # wind up behind his head
		return
	if not _did:
		_did = true
		_pose(0.0, -0.3, -1.4, 0.15)
		_cd["throw"] = 3.0
		var lead := Vector3.ZERO
		if _target is CharacterBody3D:
			lead = (_target as CharacterBody3D).velocity * 0.4
		_throw_hammer(_target.global_position + Vector3(0, 0.8, 0) + lead)
	_pose(0.0, -0.3, -1.4, 0.15)
	if _t > 0.9:
		_go(S.IDLE)


func _throw_hammer(at: Vector3) -> void:
	_hammer_out = true
	_hammer_hand.visible = false
	var start := _hammer_hand.global_position
	var model := Node3D.new()
	get_parent().add_child(model)
	model.global_position = start
	_build_hammer(model, H / 7.0)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.8, 1.0)
	glow.light_energy = 3.0
	glow.omni_range = 10.0
	model.add_child(glow)
	# stop at the first wall in the way, and smash that building
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, at + (at - start).normalized() * 3.0, 1 | 32))
	var end := at
	var smash_i := -1
	if not hit.is_empty():
		end = hit["position"]
		if city:
			smash_i = city.call("building_at", end, 1.0)
	var t := start.distance_to(end) / 55.0
	var on_hit := func():
		_boom(end, 5.0, 85.0)
		if smash_i >= 0:
			city.call("smash", smash_i, end, self)
	var fly_back := func(k: float):
		if is_instance_valid(self) and is_instance_valid(model):
			model.global_position = end.lerp(_hammer_hand.global_position, k)
			model.rotation.x += 0.4
	var caught := func():
		model.queue_free()
		if is_instance_valid(self):
			_hammer_out = false
			_hammer_hand.visible = not dead
	var tw := model.create_tween()
	tw.tween_property(model, "global_position", end, t)
	tw.parallel().tween_property(model, "rotation:x", -TAU * 4.0 * t, t)
	tw.tween_callback(on_hit)
	tw.tween_interval(0.25)
	tw.tween_method(fly_back, 0.0, 1.0, maxf(0.5, t))
	tw.tween_callback(caught)


func _do_leap(delta: float) -> void:
	if _t < 0.4:
		_pose(-0.6, -1.0, -1.0, 0.3)       # crouch
		_leap_from = global_position
		return
	var k := clampf((_t - 0.4) / 1.4, 0.0, 1.0)
	var p := _leap_from.lerp(_leap_to, k)
	p.y = _leap_from.y + sin(k * PI) * 40.0
	global_position = p
	_pose(0.6, -2.8, -2.8, -0.2)
	if k >= 1.0:
		_cd["leap"] = 10.0
		_shockwave(global_position, 12.0, 70.0)
		_go(S.IDLE)
		_gravity(delta)


func _do_smash(_delta: float) -> void:
	if _smash_index < 0 or city == null:
		_go(S.IDLE)
		return
	var b: Dictionary = (city.get("buildings") as Array)[_smash_index]
	var aabb: AABB = b["aabb"]
	if _t < 0.01:
		_leap_from = global_position
		var c := aabb.get_center()
		var away := (global_position - c)
		away.y = 0
		_leap_to = c + away.normalized() * (maxf(aabb.size.x, aabb.size.z) * 0.5 + 2.0)
		_leap_to.y = 0.0
	if _t < 0.35:
		_pose(-0.5, -1.0, -1.0, 0.3)
		return
	var k := clampf((_t - 0.35) / 1.0, 0.0, 1.0)
	var p := _leap_from.lerp(_leap_to, k)
	p.y = sin(k * PI) * (aabb.size.y + 10.0)
	global_position = p
	_face(aabb.get_center())
	_pose(0.4, -2.9, -2.9, -0.2)          # hammer raised over his head
	if k >= 1.0 and not _did:
		_did = true
		_pose(0.0, -0.4, -0.2, 0.5)
		city.call("smash", _smash_index, global_position, self)
		_shockwave(global_position, 10.0, 60.0)
		_cd["smash"] = 9.0
	if _t > 1.9:
		_go(S.IDLE)


func _do_lightning(_delta: float) -> void:
	velocity = Vector3.ZERO
	_pose(0.0, -0.2, -3.0, -0.1)           # hammer to the sky
	if not _did:
		_did = true
		_cd["lightning"] = 7.0
		_voice.stream = Sounds.thunder()
		_voice.play()
		var fighters := get_tree().get_nodes_in_group("fighters")
		fighters.shuffle()
		var n := 3 + 2 * _rage_level
		for f in fighters:
			if n <= 0:
				break
			var fp := (f as Node3D).global_position
			if fp.distance_to(global_position) < 70.0:
				_add_strike(fp)
				n -= 1
	if _t > 1.4:
		_go(S.IDLE)


func _do_stomp(_delta: float) -> void:
	velocity = Vector3.ZERO
	if _t < 0.4:
		_pose(-0.9, -1.5, -2.6, 0.0)
		return
	if not _did:
		_did = true
		_pose(0.0, 0.3, 0.3, 0.2)
		_cd["stomp"] = 4.0
		_shockwave(global_position, 11.0, 45.0)
	if _t > 1.0:
		_go(S.IDLE)


# ------------------------------------------------------------------ lightning strikes with warning circles
func _add_strike(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.2
	tm.outer_radius = 3.6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.5, 0.75, 1.0)
	tm.material = m
	ring.mesh = tm
	get_parent().add_child(ring)
	ring.global_position = Vector3(at.x, at.y + 0.15, at.z)
	_strikes.append({"ring": ring, "pos": ring.global_position, "t": 1.1})


func _update_strikes(delta: float) -> void:
	for s in _strikes.duplicate():
		s["t"] -= delta
		var ring: MeshInstance3D = s["ring"]
		ring.scale = Vector3.ONE * (0.6 + 0.4 * sin(s["t"] * 20.0) * 0.1 + (1.1 - s["t"]) * 0.4)
		if s["t"] <= 0.0:
			var p: Vector3 = s["pos"]
			FX.lightning(get_parent(), p + Vector3(randf_range(-4, 4), 60, randf_range(-4, 4)), p)
			Sounds.play(get_parent(), Sounds.thunder(), p, 4.0)
			_boom(p, 4.0, 75.0)
			ring.queue_free()
			_strikes.erase(s)


# ------------------------------------------------------------------ damage helpers
func _land() -> void:
	_shockwave(global_position, 18.0, 70.0)
	FX.lightning(get_parent(), global_position + Vector3(0, 80, 0), global_position)
	_voice.stream = Sounds.thunder()
	_voice.play()
	if city:
		var i: int = city.call("nearest_building", global_position, 3.0)
		if i >= 0:
			city.call("smash", i, global_position, self)
	_go(S.ROAR)


func _shockwave(at: Vector3, radius: float, dmg: float) -> void:
	FX.dust(get_parent(), at + Vector3(0, 0.5, 0), radius * 0.8, 1.8)
	FX.flash(get_parent(), at + Vector3(0, 2, 0), Color(0.7, 0.8, 1.0), radius * 2.5, 0.3)
	Sounds.play(get_parent(), Sounds.boom(), at, 6.0)
	_shake(0.5, radius * 4.0)
	# expanding ring on the ground
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.85, 1.0, 0.9)
	tm.material = m
	ring.mesh = tm
	get_parent().add_child(ring)
	ring.global_position = at + Vector3(0, 0.2, 0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1, radius), 0.4)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)
	_boom(at, radius, dmg, true)


func _boom(at: Vector3, radius: float, dmg: float, knock: bool = false) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.call("explode", at, radius, dmg, self, knock)


func _shake(amount: float, rng: float) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game:
		game.call("shake_at", global_position, amount, rng)


func take_damage(amount: float, _from: Node) -> void:
	if dead or _s == S.FALL:
		return
	if _phase_shield > 0.0:
		return
	var bars_before := bars_left()
	amount *= damage_taken
	hp = maxf(0.0, hp - amount)
	_flash = minf(0.6, _flash + amount / 120.0)
	if hp <= 0.0:
		_die()
		return
	if bars_left() < bars_before:
		_break_bar(bars_left())


func bars_left() -> int:
	return int(ceil(hp / BAR_HP - 0.0001))


func _break_bar(left: int) -> void:
	# a health bar breaks: he roars, shields himself for a moment and powers up
	_phase_shield = 2.5
	_enraged = true
	_rage_level = BARS - left
	_shockwave(global_position, 16.0, 60.0)
	for i in 6:
		var a := TAU * i / 6.0
		_add_strike(global_position + Vector3(cos(a), 0, sin(a)) * randf_range(8.0, 20.0))
	if left == 2:
		get_tree().call_group("game", "banner", "THOR IS ENRAGED!", "Health bar 2 of 3 - he's faster and calls more lightning", 3.0)
	else:
		get_tree().call_group("game", "banner", "GOD OF THUNDER UNLEASHED!", "Final health bar - finish him!", 3.0)
	_go(S.ROAR)


func _die() -> void:
	dead = true
	_s = S.DEAD
	collision_layer = 0
	remove_from_group("boss")
	for s in _strikes:
		(s["ring"] as Node).queue_free()
	_strikes.clear()
	_hammer_hand.visible = false
	FX.lightning(get_parent(), global_position + Vector3(0, 80, 0), global_position + Vector3(0, 4, 0))
	var tw := create_tween()
	tw.tween_property(_rig, "rotation:x", -0.5, 0.6)
	tw.tween_property(_rig, "position:y", -2.0, 0.6)
	tw.tween_property(_rig, "rotation:x", -1.45, 0.5).set_trans(Tween.TRANS_BOUNCE)
	var thud := func(): _shake(0.6, 80.0)
	tw.tween_callback(thud)
	defeated.emit()
	get_tree().call_group("game", "on_boss_defeated", global_position)
