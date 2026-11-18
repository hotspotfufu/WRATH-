extends CharacterBody3D
## You: first-person soldier.
## Mouse / keyboard:  WASD move, Shift sprint, Space jump, C or Ctrl crouch,
##   left click fire, right click aim, R reload, E pick up / enter vehicle,
##   1 / 2 / Q / mouse wheel switch weapon, Esc release the mouse.
## Gamepad: left stick move, right stick look, RT fire, LT aim, A jump,
##   B crouch, X reload / use, Y switch weapon, L3 sprint.

signal died

const WALK := 6.0
const SPRINT := 9.5
const CROUCH := 3.2
const JUMP := 8.0
const EYE := 1.62

var health := 100.0
var max_health := 100.0
var shield := 100.0
var max_shield := 100.0
var dead := false
var in_vehicle: Node = null
var kills := 0

var slots: Array = [{"id": "pistol", "mag": 12, "reserve": 48}]
var current := 0
var mouse_sens := 0.0022
var pad_sens := 2.6

var cam: Camera3D
var _head: Node3D
var _view: Node3D          # weapon model holder
var _gun: Node3D
var _fire_cd := 0.0
var _reload_t := 0.0
var _ads := 0.0
var _recoil := 0.0
var _bob := 0.0
var _crouch := 0.0
var _since_hit := 10.0
var _swap_t := 0.0
var _throwing := false
var _sfx: AudioStreamPlayer
var _hud: Node


func _ready() -> void:
	add_to_group("player")
	add_to_group("fighters")
	collision_layer = 2
	collision_mask = 1 | 8 | 32
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	cs.name = "Shape"
	add_child(cs)
	_head = Node3D.new()
	_head.position.y = EYE
	add_child(_head)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 900.0
	_head.add_child(cam)
	cam.current = true
	_view = Node3D.new()
	cam.add_child(_view)
	_sfx = AudioStreamPlayer.new()
	add_child(_sfx)
	_setup_input()
	_equip(0)
	_hud = get_tree().get_first_node_in_group("hud")


# ------------------------------------------------------------------ input map
func _setup_input() -> void:
	var keys := {
		"move_f": [KEY_W, KEY_UP], "move_b": [KEY_S, KEY_DOWN], "move_l": [KEY_A, KEY_LEFT], "move_r": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "reload": [KEY_R],
		"use": [KEY_E, KEY_F], "slot1": [KEY_1], "slot2": [KEY_2], "swap": [KEY_Q], "release_mouse": [KEY_ESCAPE],
	}
	for a in keys:
		_ensure(a)
		for k in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)
	_ensure("fire")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)
	_ensure("aim")
	var mr := InputEventMouseButton.new()
	mr.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("aim", mr)
	# gamepad
	_pad_axis("move_f", JOY_AXIS_LEFT_Y, -1.0)
	_pad_axis("move_b", JOY_AXIS_LEFT_Y, 1.0)
	_pad_axis("move_l", JOY_AXIS_LEFT_X, -1.0)
	_pad_axis("move_r", JOY_AXIS_LEFT_X, 1.0)
	_pad_axis("fire", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_pad_axis("aim", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_pad_btn("jump", JOY_BUTTON_A)
	_pad_btn("crouch", JOY_BUTTON_B)
	_pad_btn("reload", JOY_BUTTON_X)
	_pad_btn("use", JOY_BUTTON_X)
	_pad_btn("swap", JOY_BUTTON_Y)
	_pad_btn("sprint", JOY_BUTTON_LEFT_STICK)


func _ensure(a: String) -> void:
	if InputMap.has_action(a):
		InputMap.erase_action(a)
	InputMap.add_action(a, 0.25)


func _pad_axis(a: String, axis: JoyAxis, v: float) -> void:
	if not InputMap.has_action(a):
		_ensure(a)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = v
	InputMap.action_add_event(a, e)


func _pad_btn(a: String, b: JoyButton) -> void:
	if not InputMap.has_action(a):
		_ensure(a)
	var e := InputEventJoypadButton.new()
	e.button_index = b
	InputMap.action_add_event(a, e)


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if in_vehicle:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		var s := mouse_sens * lerpf(1.0, 0.45, _ads) * (0.4 if _zoomed_sniper() else 1.0)
		_look(-m.relative.x * s, -m.relative.y * s)
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP or b == MOUSE_BUTTON_WHEEL_DOWN:
			_switch()
	if event.is_action_pressed("slot1"):
		_equip(0)
	elif event.is_action_pressed("slot2") and slots.size() > 1:
		_equip(1)
	elif event.is_action_pressed("swap"):
		_switch()
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("use"):
		_use()


func _look(yaw: float, pitch: float) -> void:
	rotate_y(yaw)
	_head.rotation.x = clampf(_head.rotation.x + pitch, deg_to_rad(-88), deg_to_rad(88))


# ------------------------------------------------------------------ movement
func _physics_process(delta: float) -> void:
	if dead or in_vehicle:
		return
	# gamepad look
	var lx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ly := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(lx) > 0.15 or absf(ly) > 0.15:
		var s := pad_sens * delta * lerpf(1.0, 0.5, _ads)
		_look(-lx * absf(lx) * s, -ly * absf(ly) * s * 0.7)

	var input := Input.get_vector("move_l", "move_r", "move_f", "move_b")
	var crouching := Input.is_action_pressed("crouch")
	var sprinting := Input.is_action_pressed("sprint") and input.y < -0.3 and not crouching and _ads < 0.2
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * 6.0)
	_head.position.y = EYE - 0.6 * _crouch
	var speed := CROUCH if crouching else (SPRINT if sprinting else WALK)
	speed *= lerpf(1.0, 0.6, _ads)
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	var target := dir * speed
	var accel := 12.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP
	move_and_slide()

	# head bob & weapon sway
	var hv := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hv > 0.5:
		_bob += delta * hv * 1.6
	_update_weapon(delta, hv, sprinting)

	# shield recharge, Halo style
	_since_hit += delta
	if _since_hit > 4.0 and shield < max_shield:
		shield = minf(max_shield, shield + 45.0 * delta)
	if global_position.y < -30:
		take_damage(9999, null)


# ------------------------------------------------------------------ weapons
func weapon() -> Dictionary:
	return slots[current]


func _equip(i: int) -> void:
	current = clampi(i, 0, slots.size() - 1)
	_reload_t = 0.0
	_swap_t = 0.35
	if _gun:
		_gun.queue_free()
	_gun = Weapons.build_model(weapon()["id"])
	_view.add_child(_gun)


func _switch() -> void:
	if slots.size() > 1:
		_equip(1 - current)


func give_weapon(id: String) -> void:
	var d := Weapons.info(id)
	for i in slots.size():
		if slots[i]["id"] == id:
			slots[i]["reserve"] = mini(slots[i]["reserve"] + int(d["mag"]) * 2, int(d["reserve"]))
			return
	var w := {"id": id, "mag": int(d["mag"]), "reserve": int(d["reserve"]) / 2}
	if id == "hammer":
		w["reserve"] = 0
	if slots.size() < 2:
		slots.append(w)
		_equip(slots.size() - 1)
	else:
		# swap: drop what you hold
		var old: Dictionary = slots[current]
		get_tree().call_group("game", "drop_weapon", old["id"], global_position + -transform.basis.z * 1.2 + Vector3(0, 0.5, 0))
		slots[current] = w
		_equip(current)


func give_ammo() -> void:
	for w in slots:
		var d := Weapons.info(w["id"])
		w["reserve"] = mini(int(w["reserve"]) + int(d["mag"]) * 2, int(d["reserve"]))


func give_armor() -> void:
	max_shield = 150.0
	shield = max_shield


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)


func _start_reload() -> void:
	var w := weapon()
	var d := Weapons.info(w["id"])
	if d.get("melee", false) or _reload_t > 0.0 or int(w["mag"]) >= int(d["mag"]) or int(w["reserve"]) <= 0:
		return
	_reload_t = float(d["reload"])


func _update_weapon(delta: float, hv: float, sprinting: bool) -> void:
	var w := weapon()
	var d := Weapons.info(w["id"])
	_fire_cd -= delta
	_swap_t = maxf(0.0, _swap_t - delta)
	var aiming: bool = Input.is_action_pressed("aim") and not sprinting and _reload_t <= 0.0 and not d.get("melee", false)
	_ads = move_toward(_ads, 1.0 if aiming else 0.0, delta * 7.0)
	cam.fov = lerpf(75.0, float(d["zoom"]), _ads)
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)

	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			var need := int(d["mag"]) - int(w["mag"])
			var take := mini(need, int(w["reserve"]))
			w["mag"] = int(w["mag"]) + take
			w["reserve"] = int(w["reserve"]) - take

	# where the gun sits: hip, aimed, sprinting, reloading, switching
	var hip := Vector3(0.24, -0.22, -0.45)
	var ads := Vector3(0.0, -0.13 if w["id"] != "sniper" else -0.2, -0.32)
	var pos := hip.lerp(ads, _ads)
	pos += Vector3(sin(_bob) * 0.015, -absf(cos(_bob)) * 0.012, 0) * (1.0 - _ads)
	pos.z += _recoil * 0.08
	var rot := Vector3(_recoil * 0.25, 0, 0)
	if sprinting:
		pos += Vector3(-0.05, -0.06, 0.05)
		rot += Vector3(-0.3, 0.6, 0.2)
	if _reload_t > 0.0:
		rot.x -= 0.6
		pos.y -= 0.12
	pos.y -= _swap_t * 0.8
	if _zoomed_sniper():
		_gun.visible = false
	else:
		_gun.visible = true
	_gun.position = _gun.position.lerp(pos, minf(1.0, delta * 18.0))
	_gun.rotation = _gun.rotation.lerp(rot, minf(1.0, delta * 14.0))

	if sprinting or _swap_t > 0.0 or _reload_t > 0.0:
		return
	var want := Input.is_action_pressed("fire") if d["auto"] else Input.is_action_just_pressed("fire")
	if want and _fire_cd <= 0.0:
		if d.get("melee", false):
			_swing_hammer(d)
			return
		if int(w["mag"]) <= 0:
			_start_reload()
			return
		_fire(w, d)
	if Input.is_action_just_pressed("aim") and d.get("melee", false):
		_throw_hammer(d)


func _zoomed_sniper() -> bool:
	return weapon()["id"] == "sniper" and _ads > 0.8


func _fire(w: Dictionary, d: Dictionary) -> void:
	_fire_cd = float(d["rate"])
	w["mag"] = int(w["mag"]) - 1
	_recoil = minf(1.0, _recoil + (0.9 if w["id"] in ["sniper", "shotgun", "rocket"] else 0.35))
	_head.rotation.x += deg_to_rad(0.6 if w["id"] == "rifle" else 1.8) * (1.0 - _ads * 0.5)
	_play_shot(w["id"])
	var origin := cam.global_position
	var muzzle := _gun.global_position + -cam.global_transform.basis.z * 0.6
	FX.flash(get_parent(), muzzle, Color(1.0, 0.8, 0.45), 6.0, 0.06)
	if d.get("rocket", false):
		var r := Weapons.Rocket.new()
		r.dir = -cam.global_transform.basis.z
		r.damage = float(d["damage"])
		r.owner_node = self
		get_parent().add_child(r)
		r.global_position = origin + r.dir * 1.0
		r.look_at(r.global_position + r.dir, Vector3.UP)
		return
	var spread := deg_to_rad(float(d["spread"]) * lerpf(1.0, 0.35, _ads))
	for i in int(d["pellets"]):
		var dir := -cam.global_transform.basis.z
		dir = dir.rotated(cam.global_transform.basis.x, randf_range(-spread, spread))
		dir = dir.rotated(cam.global_transform.basis.y, randf_range(-spread, spread))
		var to := origin + dir * float(d["range"])
		var q := PhysicsRayQueryParameters3D.create(origin, to, 1 | 8 | 32)
		q.exclude = [get_rid()]
		q.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var end := to
		if not hit.is_empty():
			end = hit["position"]
			var col: Object = hit["collider"]
			var target: Node = col as Node
			while target and not target.has_method("take_damage") and target.get_parent():
				target = target.get_parent()
				if target is Window:
					target = null
			if target and target.has_method("take_damage") and target != self:
				var mult := 1.0
				if col is Node and String((col as Node).name).begins_with("Head"):
					mult = 2.0
				target.call("take_damage", float(d["damage"]) * mult, self)
				if _hud:
					_hud.call("hitmarker", mult > 1.0)
				FX.sparks(get_parent(), end, Color(0.6, 0.85, 1.0))
			else:
				FX.sparks(get_parent(), end)
		if i == 0 or randf() < 0.3:
			FX.tracer(get_parent(), muzzle, end)


func _swing_hammer(d: Dictionary) -> void:
	_fire_cd = float(d["rate"])
	_recoil = 1.0
	_play_shot("hammer")
	var p := global_position + -transform.basis.z * 2.2 + Vector3(0, 1, 0)
	get_tree().call_group("game", "explode", p, 3.5, float(d["damage"]), self)
	FX.lightning(get_parent(), p + Vector3(0, 25, 0), p)


func _throw_hammer(d: Dictionary) -> void:
	if _throwing:
		return
	_throwing = true
	_gun.visible = false
	var dir := -cam.global_transform.basis.z
	var start := cam.global_position + dir
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, start + dir * 60.0, 1 | 8))
	var end: Vector3 = hit["position"] if not hit.is_empty() else start + dir * 60.0
	var model := Weapons.build_model("hammer")
	model.scale = Vector3.ONE * 2.5
	get_parent().add_child(model)
	model.global_position = start
	var tw := model.create_tween()
	tw.tween_property(model, "global_position", end, start.distance_to(end) / 45.0)
	tw.parallel().tween_property(model, "rotation:x", -TAU * 3.0, start.distance_to(end) / 45.0)
	tw.tween_callback(func():
		get_tree().call_group("game", "explode", end, 5.0, 300.0, self)
		FX.lightning(get_parent(), end + Vector3(0, 30, 0), end))
	tw.tween_method(func(t: float): model.global_position = end.lerp(cam.global_position, t), 0.0, 1.0, 0.6)
	tw.tween_callback(func():
		model.queue_free()
		_throwing = false
		_gun.visible = true)


func _play_shot(id: String) -> void:
	_sfx.stream = Sounds.gun(id)
	_sfx.pitch_scale = randf_range(0.94, 1.06)
	_sfx.play()


# ------------------------------------------------------------------ interaction
func _use() -> void:
	# nearest jeep first, then loot
	var best: Node = null
	var bd := 3.6
	for v in get_tree().get_nodes_in_group("vehicles"):
		var d := (v as Node3D).global_position.distance_to(global_position)
		if d < bd and v.call("free_seat"):
			bd = d
			best = v
	if best:
		best.call("enter", self)
		return
	var item := nearest_pickup()
	if item:
		item.call("take", self)


func nearest_pickup() -> Node:
	var best: Node = null
	var bd := 2.6
	for p in get_tree().get_nodes_in_group("pickups"):
		var d := (p as Node3D).global_position.distance_to(global_position + Vector3(0, 0.6, 0))
		if d < bd:
			bd = d
			best = p
	return best


func set_in_vehicle(v: Node) -> void:
	in_vehicle = v
	($Shape as CollisionShape3D).disabled = v != null
	_view.visible = v == null
	if v == null:
		cam.current = true


# ------------------------------------------------------------------ damage
func take_damage(amount: float, from: Node) -> void:
	if dead:
		return
	if in_vehicle and in_vehicle.has_method("take_damage") and amount < 9000:
		in_vehicle.call("take_damage", amount, from)
		amount *= 0.3
	_since_hit = 0.0
	var to_shield := minf(shield, amount)
	shield -= to_shield
	health -= amount - to_shield
	if _hud:
		_hud.call("damage_flash", from)
	if health <= 0.0:
		health = 0.0
		dead = true
		remove_from_group("fighters")
		if in_vehicle:
			in_vehicle.call("exit")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		died.emit()
		get_tree().call_group("game", "on_fighter_died", self)
