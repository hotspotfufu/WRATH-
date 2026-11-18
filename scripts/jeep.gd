extends VehicleBody3D
## A drivable jeep (like Halo's Warthog).  E to get in / out.
## W / S drive, A / D steer, Space handbrake. Third-person camera, mouse looks around.
## Running into Thor hurts him; Thor can smash the jeep.

var driver: Node = null
var health := 400.0
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
	mass = 900.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.4, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.1, 0.9, 4.0)
	cs.shape = bs
	cs.position.y = 0.55
	add_child(cs)
	_build_model()
	for x in [-0.95, 0.95]:
		for z in [-1.35, 1.35]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, 0.1, z)
			w.wheel_radius = 0.45
			w.suspension_travel = 0.3
			w.suspension_stiffness = 40.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.2
			w.wheel_friction_slip = 2.6
			w.wheel_roll_influence = 0.15
			w.use_as_steering = z < 0.0
			w.use_as_traction = true
			add_child(w)
			var tyre := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.45
			cyl.bottom_radius = 0.45
			cyl.height = 0.38
			var tm := StandardMaterial3D.new()
			tm.albedo_color = Color(0.08, 0.08, 0.09)
			tm.roughness = 0.95
			cyl.material = tm
			tyre.mesh = cyl
			tyre.rotation.z = PI * 0.5
			w.add_child(tyre)
			_wheels.append(w)
	_pivot = Node3D.new()
	_pivot.top_level = true
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 900.0
	_cam.position = Vector3(0, 2.6, 8.0)
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
		engine_force = -throttle * 2600.0 if absf(fwd_speed) < 30.0 or signf(throttle) != signf(fwd_speed) else 0.0
		steering = move_toward(steering, steer_in * 0.5, delta * 2.5)
		brake = 6.0 if Input.is_action_pressed("jump") else 0.0
		(driver as Node3D).global_position = global_position + Vector3(0, 1.0, 0)
		# keep the driver's view following the jeep
		var lx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
		if absf(lx) > 0.15:
			_yaw -= lx * delta * 2.0
		_engine.pitch_scale = 0.7 + absf(fwd_speed) / 25.0
		# ram damage
		if absf(fwd_speed) > 8.0:
			for t in get_tree().get_nodes_in_group("boss"):
				if (t as Node3D).global_position.distance_to(global_position) < 4.0 and t.has_method("take_damage"):
					t.call("take_damage", absf(fwd_speed) * 4.0, driver)
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
