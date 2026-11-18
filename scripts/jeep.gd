extends VehicleBody3D
## A drivable jeep (like Halo's Warthog).  E to get in / out.
## W / S drive, A / D steer, Space handbrake. Third-person camera, mouse looks around.
## Running into Thor hurts him; Thor can smash the jeep.

## kind = "jeep" (fast), "mrap" (tan armored truck, roof gun) or "apc" (green 8-wheel, roof gun)
var kind := "jeep"
var driver: Node = null
var health := 400.0
var has_turret := false
var _turret: Node3D
var _gun_pivot: Node3D
var _muzzle: Node3D
var _fire_cd := 0.0
var _engine_force := 2600.0
var _top_speed := 30.0
var _gun_sfx: AudioStreamPlayer
static var _mats := {}

const SPECS := {
	"jeep": {"mass": 900.0, "health": 400.0, "box": Vector3(2.1, 0.9, 4.0), "box_y": 0.55, "wheels": [[-0.95, -1.35], [0.95, -1.35], [-0.95, 1.35], [0.95, 1.35]], "r": 0.45, "force": 2600.0, "top": 30.0, "cam": Vector3(0, 2.6, 8.0)},
	"mrap": {"mass": 2600.0, "health": 1400.0, "box": Vector3(2.5, 2.0, 6.0), "box_y": 1.35, "wheels": [[-1.1, -1.95], [1.1, -1.95], [-1.1, 1.85], [1.1, 1.85]], "r": 0.62, "force": 9800.0, "top": 24.0, "cam": Vector3(0, 4.0, 11.0)},
	"apc": {"mass": 3600.0, "health": 2200.0, "box": Vector3(2.7, 1.6, 6.8), "box_y": 1.2, "wheels": [[-1.2, -2.45], [1.2, -2.45], [-1.2, -1.0], [1.2, -1.0], [-1.2, 0.75], [1.2, 0.75], [-1.2, 2.2], [1.2, 2.2]], "r": 0.56, "force": 9500.0, "top": 20.0, "cam": Vector3(0, 4.4, 12.0)},
}
var _cam: Camera3D
var _pivot: Node3D
var _yaw := 0.0
var _pitch := -0.25
var _wheels: Array[VehicleWheel3D] = []
var _engine: AudioStreamPlayer
var _dead := false
var _entered_frame := -10


func _ready() -> void:
	add_to_group("vehicles")
	collision_layer = 32
	collision_mask = 1 | 8 | 32 | 64
	var spec: Dictionary = SPECS.get(kind, SPECS["jeep"])
	mass = spec["mass"]
	health = spec["health"]
	_engine_force = spec["force"]
	_top_speed = spec["top"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.4, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = spec["box"]
	cs.shape = bs
	cs.position.y = spec["box_y"]
	add_child(cs)
	match kind:
		"mrap":
			_build_mrap()
		"apc":
			_build_apc()
		_:
			_build_model()
	var radius: float = spec["r"]
	for wp in spec["wheels"]:
			var x: float = wp[0]
			var z: float = wp[1]
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.1, z)
			w.wheel_radius = radius
			w.suspension_travel = 0.3
			w.suspension_stiffness = 40.0 if kind == "jeep" else 70.0
			# strong enough to hold the vehicle's weight (heavy trucks crush the default springs)
			w.suspension_max_force = mass * 30.0 / float((spec["wheels"] as Array).size()) * 2.5
			w.damping_compression = 0.9
			w.damping_relaxation = 1.2
			w.wheel_friction_slip = 2.6
			w.wheel_roll_influence = 0.15
			w.use_as_steering = z < (-0.5 if kind == "apc" else 0.0)
			w.use_as_traction = true
			add_child(w)
			var tyre := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius
			cyl.bottom_radius = radius
			cyl.height = 0.38 if kind == "jeep" else 0.5
			cyl.radial_segments = 16
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.08, 0.08, 0.09)
			tm.roughness = 0.95
			cyl.material = tm
			tyre.mesh = cyl
			tyre.rotation.z = PI * 0.5
			w.add_child(tyre)
			if kind != "jeep":
				# chunky rim / hub
				var hub := MeshInstance3D.new()
				var hc := CylinderMesh.new()
				hc.top_radius = radius * 0.5
				hc.bottom_radius = radius * 0.5
				hc.height = 0.52
				hc.material = _vmat("tan" if kind == "mrap" else "green", 0.6)
				hub.mesh = hc
				hub.rotation.z = PI * 0.5
				w.add_child(hub)
			_wheels.append(w)
	_pivot = Node3D.new()
	_pivot.top_level = true
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 900.0
	_cam.position = spec["cam"]
	_gun_sfx = AudioStreamPlayer.new()
	_gun_sfx.volume_db = -6.0
	add_child(_gun_sfx)
	_pivot.add_child(_cam)
	_engine = AudioStreamPlayer.new()
	_engine.volume_db = -14.0
	add_child(_engine)


func _build_model() -> void:
	var body_col := Color(0.32, 0.38, 0.26)
	var parts := [
		[Vector3(2.0, 0.55, 3.9), Vector3(0, 0.6, 0), body_col],
		[Vector3(1.9, 0.45, 1.3), Vector3(0, 1.05, -1.25), body_col.darkened(0.1)],
		[Vector3(1.8, 0.08, 0.6), Vector3(0, 1.55, -0.45), Color(0.15, 0.22, 0.28)],
		[Vector3(0.08, 0.6, 0.08), Vector3(-0.85, 1.25, -0.4), Color(0.2, 0.2, 0.2)],
		[Vector3(0.08, 0.6, 0.08), Vector3(0.85, 1.25, -0.4), Color(0.2, 0.2, 0.2)],
		[Vector3(1.9, 0.12, 0.18), Vector3(0, 0.6, -2.0), Color(0.2, 0.2, 0.2)],
		[Vector3(0.4, 0.35, 0.4), Vector3(-0.45, 1.05, 0.3), Color(0.15, 0.15, 0.16)],
		[Vector3(0.4, 0.35, 0.4), Vector3(0.45, 1.05, 0.3), Color(0.15, 0.15, 0.16)],
		[Vector3(0.3, 0.12, 0.05), Vector3(-0.7, 0.75, -1.98), Color(1.0, 0.95, 0.75)],
		[Vector3(0.3, 0.12, 0.05), Vector3(0.7, 0.75, -1.98), Color(1.0, 0.95, 0.75)],
		[Vector3(0.25, 0.1, 0.05), Vector3(-0.8, 0.75, 1.98), Color(0.9, 0.1, 0.1)],
		[Vector3(0.25, 0.1, 0.05), Vector3(0.8, 0.75, 1.98), Color(0.9, 0.1, 0.1)],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		var m := StandardMaterial3D.new()
		m.albedo_color = p[2]
		m.roughness = 0.6
		bm.material = m
		mi.mesh = bm
		mi.position = p[1]
		add_child(mi)


func free_seat() -> bool:
	return driver == null and not _dead


func enter(who: Node) -> void:
	if not free_seat():
		return
	driver = who
	_entered_frame = Engine.get_process_frames()
	brake = 0.0
	can_sleep = false
	sleeping = false
	if who.has_method("set_in_vehicle"):
		who.call("set_in_vehicle", self)
	if who.is_in_group("player"):
		_yaw = rotation.y
		_cam.current = true
		_engine.stream = _engine_loop()
		_engine.play()


func exit() -> void:
	if driver == null:
		return
	var who := driver
	driver = null
	can_sleep = true
	engine_force = 0.0
	brake = 2.0
	_engine.stop()
	if is_instance_valid(who) and who is Node3D:
		(who as Node3D).global_position = global_position + global_transform.basis.x * -2.2 + Vector3(0, 0.5, 0)
		who.call("set_in_vehicle", null)


func _unhandled_input(event: InputEvent) -> void:
	if driver == null or not driver.is_in_group("player"):
		return
	if event.is_action_pressed("use") and Engine.get_process_frames() - _entered_frame > 2:
		exit()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_yaw -= m.relative.x * 0.003
		_pitch = clampf(_pitch - m.relative.y * 0.003, -0.9, 0.3)


func _physics_process(delta: float) -> void:
	if driver and is_instance_valid(driver) and driver.is_in_group("player"):
		var throttle := Input.get_axis("move_b", "move_f")
		var steer_in := Input.get_axis("move_r", "move_l")
		var fwd_speed := -linear_velocity.dot(global_transform.basis.z)
		engine_force = -throttle * _engine_force if absf(fwd_speed) < _top_speed or signf(throttle) != signf(fwd_speed) else 0.0
		steering = move_toward(steering, steer_in * 0.5, delta * 2.5)
		brake = 6.0 if Input.is_action_pressed("jump") else 0.0
		(driver as Node3D).global_position = global_position + Vector3(0, 1.0, 0)
		# keep the driver's view following the jeep
		var lx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		if absf(lx) > 0.15:
			_yaw -= lx * delta * 2.0
		_engine.pitch_scale = (0.55 if kind != "jeep" else 0.7) + absf(fwd_speed) / 25.0
		if has_turret:
			_update_turret(delta)
		# ram damage
		if absf(fwd_speed) > 8.0:
			for t in get_tree().get_nodes_in_group("boss"):
				if (t as Node3D).global_position.distance_to(global_position) < (4.0 if kind == "jeep" else 5.0) and t.has_method("take_damage"):
					t.call("take_damage", absf(fwd_speed) * (4.0 if kind == "jeep" else 9.0), driver)
	else:
		engine_force = 0.0
	_pivot.global_position = global_position + Vector3(0, 0.8, 0)
	_pivot.rotation = Vector3(_pitch, _yaw, 0)


func take_damage(amount: float, _from: Node) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_dead = true
		var d := driver
		exit()
		if d and is_instance_valid(d) and d.has_method("take_damage"):
			d.call("take_damage", 60.0, null)
		FX.explosion(get_parent(), global_position + Vector3(0, 1, 0), 5.0)
		Sounds.play(get_parent(), Sounds.boom(), global_position)
		for c in get_children():
			if c is MeshInstance3D:
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.08, 0.07, 0.07)
				(c as MeshInstance3D).material_override = m
		apply_central_impulse(Vector3(randf_range(-1, 1), 7, randf_range(-1, 1)) * mass * 0.8)


# ======================================================================= armored vehicles
func _vmat(paint: String, rough: float = 0.7, metal: float = 0.3) -> StandardMaterial3D:
	var key := "%s_%s_%s" % [paint, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match paint:
		"tan", "green":
			m.albedo_texture = load("res://scripts/tex_%s.png" % paint)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.5
		"dark":
			m.albedo_color = Color(0.13, 0.14, 0.15)
		"glass":
			m.albedo_color = Color(0.12, 0.18, 0.22)
			rough = 0.08
			metal = 0.6
		"tyre":
			m.albedo_color = Color(0.07, 0.07, 0.08)
			rough = 0.95
			metal = 0.0
		"steel":
			m.albedo_color = Color(0.32, 0.33, 0.34)
		"light":
			m.albedo_color = Color(1.0, 0.95, 0.8)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.9, 0.7)
			m.emission_energy_multiplier = 1.5
		"red":
			m.albedo_color = Color(0.8, 0.1, 0.08)
			m.emission_enabled = true
			m.emission = Color(0.8, 0.1, 0.08)
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


func _p(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## tan Mine-Resistant Ambush-Protected truck, like the reference photo
func _build_mrap() -> void:
	var tan := _vmat("tan")
	var dark := _vmat("dark", 0.6, 0.4)
	var glass := _vmat("glass")
	# chassis + V-hull underneath
	_p(self, Vector3(1.6, 0.35, 5.6), Vector3(0, 0.45, 0), dark)
	_p(self, Vector3(1.2, 0.3, 4.6), Vector3(0, 0.3, 0.1), dark, Vector3(0, 0, 0))
	# crew box (tall rear) and cab
	_p(self, Vector3(2.45, 1.75, 3.6), Vector3(0, 1.6, 0.9), tan)
	_p(self, Vector3(2.4, 1.3, 1.4), Vector3(0, 1.55, -1.55), tan)
	# sloped hood and engine bay
	_p(self, Vector3(2.3, 0.75, 1.5), Vector3(0, 1.1, -2.85), tan)
	_p(self, Vector3(2.3, 0.12, 1.55), Vector3(0, 1.5, -2.75), tan, Vector3(-0.18, 0, 0))
	# grille + bull bar + headlights
	_p(self, Vector3(1.5, 0.55, 0.06), Vector3(0, 1.1, -3.6), dark)
	for i in 6:
		_p(self, Vector3(1.4, 0.03, 0.07), Vector3(0, 0.88 + i * 0.09, -3.62), tan)
	_p(self, Vector3(2.3, 0.14, 0.18), Vector3(0, 0.75, -3.72), dark)
	for x in [-0.95, 0.95]:
		_p(self, Vector3(0.3, 0.2, 0.06), Vector3(x, 1.25, -3.61), _vmat("light"))
		_p(self, Vector3(0.22, 0.12, 0.06), Vector3(x * 0.95, 1.9, 2.71), _vmat("red"))
	# armored windscreen and side windows
	_p(self, Vector3(2.1, 0.55, 0.08), Vector3(0, 1.95, -2.24), glass, Vector3(-0.3, 0, 0))
	for side in [-1.0, 1.0]:
		for z in [-1.5, 0.0, 1.4]:
			_p(self, Vector3(0.05, 0.45, 0.55), Vector3(side * 1.23, 2.0, z), glass)
		# doors, steps, fenders, side storage boxes
		_p(self, Vector3(0.04, 1.2, 0.9), Vector3(side * 1.24, 1.5, -1.55), tan)
		_p(self, Vector3(0.35, 0.08, 0.6), Vector3(side * 1.3, 0.75, -1.0), dark)
		_p(self, Vector3(0.5, 0.5, 2.0), Vector3(side * 1.25, 0.95, 0.9), tan)
		for z in [-1.95, 1.85]:
			_p(self, Vector3(0.4, 0.1, 1.5), Vector3(side * 1.12, 1.25, z), tan)
		_p(self, Vector3(0.06, 0.06, 0.4), Vector3(side * 1.35, 2.2, -2.0), dark)      # mirrors
		_p(self, Vector3(0.05, 0.35, 0.25), Vector3(side * 1.55, 2.0, -2.15), dark)
	# rear door
	_p(self, Vector3(1.2, 1.4, 0.06), Vector3(0, 1.55, 2.72), tan)
	# roof turret with a gun shield and heavy machine gun
	_add_turret(Vector3(0, 2.5, 0.8), tan, true)


## green 8-wheel armored personnel carrier, like the reference photo
func _build_apc() -> void:
	var green := _vmat("green")
	var dark := _vmat("dark", 0.6, 0.4)
	# main hull with sloped glacis and slanted upper sides
	_p(self, Vector3(2.4, 1.0, 6.6), Vector3(0, 1.05, 0), green)
	_p(self, Vector3(2.0, 0.5, 6.2), Vector3(0, 1.8, 0.15), green)
	_p(self, Vector3(2.4, 0.12, 1.5), Vector3(0, 1.45, -3.55), green, Vector3(-0.5, 0, 0))     # front glacis
	_p(self, Vector3(2.3, 0.6, 0.12), Vector3(0, 0.8, -3.35), green, Vector3(0.6, 0, 0))       # lower nose
	for side in [-1.0, 1.0]:
		_p(self, Vector3(0.1, 0.6, 6.2), Vector3(side * 1.1, 1.75, 0.15), green, Vector3(0, 0, side * 0.35))   # slanted sides
		_p(self, Vector3(0.2, 0.15, 6.8), Vector3(side * 1.3, 0.75, 0), dark)                        # lower skirt
		for z in [-2.45, -1.0, 0.75, 2.2]:
			_p(self, Vector3(0.12, 0.08, 1.3), Vector3(side * 1.32, 1.12, z), green)                  # wheel arches
		for i in 5:
			_p(self, Vector3(0.05, 0.25, 0.4), Vector3(side * 1.22, 1.45, -2.0 + i * 1.0), dark)       # stowage
		_p(self, Vector3(0.04, 2.5, 0.04), Vector3(side * 0.8, 3.3, 2.9), dark)                        # antennas
	# driver hatch, periscopes, headlights, rear ramp
	_p(self, Vector3(0.7, 0.15, 0.7), Vector3(-0.6, 2.1, -2.3), dark)
	for i in 3:
		_p(self, Vector3(0.15, 0.08, 0.06), Vector3(-0.8 + i * 0.2, 2.2, -2.68), _vmat("glass"))
	for x in [-0.95, 0.95]:
		_p(self, Vector3(0.25, 0.15, 0.06), Vector3(x, 1.25, -3.42), _vmat("light"))
		_p(self, Vector3(0.18, 0.1, 0.06), Vector3(x, 1.3, 3.32), _vmat("red"))
	_p(self, Vector3(1.6, 1.3, 0.08), Vector3(0, 1.35, 3.33), green)
	# remote weapon station on top
	_add_turret(Vector3(0.3, 2.1, -0.6), green, false)


func _add_turret(at: Vector3, paint: Material, shield: bool) -> void:
	has_turret = true
	var dark := _vmat("dark", 0.5, 0.5)
	var steel := _vmat("steel", 0.35, 0.8)
	_turret = Node3D.new()
	_turret.position = at
	add_child(_turret)
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.65
	rc.bottom_radius = 0.7
	rc.height = 0.25
	rc.material = dark
	ring.mesh = rc
	_turret.add_child(ring)
	if shield:
		_p(_turret, Vector3(1.3, 0.75, 0.08), Vector3(0, 0.5, -0.55), paint)
		_p(_turret, Vector3(0.08, 0.75, 0.9), Vector3(-0.66, 0.5, -0.15), paint)
		_p(_turret, Vector3(0.08, 0.75, 0.9), Vector3(0.66, 0.5, -0.15), paint)
		_p(_turret, Vector3(0.5, 0.18, 0.06), Vector3(0, 0.62, -0.6), _vmat("glass"))
	else:
		_p(_turret, Vector3(0.8, 0.5, 0.7), Vector3(0, 0.35, 0), paint)
		_p(_turret, Vector3(0.3, 0.25, 0.3), Vector3(0.45, 0.45, -0.1), dark)    # sensor box
		_p(_turret, Vector3(0.18, 0.12, 0.03), Vector3(0.45, 0.47, -0.26), _vmat("glass"))
	_gun_pivot = Node3D.new()
	_gun_pivot.position = Vector3(0, 0.45, -0.1)
	_turret.add_child(_gun_pivot)
	_p(_gun_pivot, Vector3(0.22, 0.22, 0.75), Vector3(0, 0, -0.3), dark)
	var barrel := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 0.045
	bc.bottom_radius = 0.045
	bc.height = 1.1
	bc.material = steel
	barrel.mesh = bc
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.02, -1.2)
	_gun_pivot.add_child(barrel)
	_p(_gun_pivot, Vector3(0.12, 0.12, 0.12), Vector3(0, 0.02, -1.75), dark)
	_p(_gun_pivot, Vector3(0.18, 0.25, 0.3), Vector3(0.2, -0.05, -0.2), _vmat("green" if paint == _vmat("green") else "tan"))   # ammo box
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -1.85)
	_gun_pivot.add_child(_muzzle)


## the roof gun follows where you look and fires with left click
func _update_turret(delta: float) -> void:
	_fire_cd -= delta
	var origin := _cam.global_position
	var dir := -_cam.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 260.0, 1 | 8)
	q.exclude = [get_rid()]
	q.collide_with_areas = true
	var hit := space.intersect_ray(q)
	var target: Vector3 = hit["position"] if not hit.is_empty() else origin + dir * 260.0
	var local := _turret.to_local(target)
	_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(-local.x, -local.z) + _turret.rotation.y, minf(1.0, delta * 10.0))
	var lp := _gun_pivot.to_local(target)
	_gun_pivot.rotation.x = clampf(_gun_pivot.rotation.x + atan2(lp.y, -lp.z) * minf(1.0, delta * 10.0), -0.35, 0.9)
	if Input.is_action_pressed("fire") and _fire_cd <= 0.0:
		_fire_cd = 0.09
		var m := _muzzle.global_position
		var q2 := PhysicsRayQueryParameters3D.create(m, m + (target - m).normalized() * 260.0, 1 | 8)
		q2.exclude = [get_rid()]
		q2.collide_with_areas = true
		var h2 := space.intersect_ray(q2)
		var end: Vector3 = h2["position"] if not h2.is_empty() else m + (target - m).normalized() * 260.0
		if not h2.is_empty():
			var t: Node = h2["collider"] as Node
			while t and not t.has_method("take_damage") and t.get_parent():
				t = t.get_parent()
				if t is Window:
					t = null
			if t and t != self and t.has_method("take_damage") and t.is_in_group("boss"):
				t.call("take_damage", 32.0, driver)
				var hud := get_tree().get_first_node_in_group("hud")
				if hud:
					hud.call("hitmarker", false)
			FX.sparks(get_parent(), end, Color(1.0, 0.8, 0.4))
		FX.tracer(get_parent(), m, end, Color(1.0, 0.85, 0.45), 0.07)
		FX.flash(get_parent(), m, Color(1.0, 0.75, 0.4), 5.0, 0.05)
		_gun_sfx.stream = Sounds.gun("rifle")
		_gun_sfx.pitch_scale = randf_range(0.7, 0.8)
		_gun_sfx.play()


static func _engine_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		ph += TAU * 55.0 / rate
		var s := sin(ph) * 0.4 + sin(ph * 2.0) * 0.2 + randf_range(-0.08, 0.08)
		data.encode_s16(i * 2, int(s * 0.6 * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w
