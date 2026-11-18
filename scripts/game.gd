extends Node3D
## Runs a match of GOD HUNT:
##   1. LOOT (2:30) - 100 soldiers drop into the city and grab weapons, armor, jeeps
##   2. STORM - the sky darkens, thunder rolls
##   3. BOSS - Thor crashes down and tries to wipe everyone out
##   4. Kill Thor -> his hammer drops. Pick it up to claim Mjolnir.

const CityScript := preload("res://scripts/city.gd")
const LOOT_TIME := 150.0
const SOLDIERS := 99            # plus you = 100
const MAX_JEEPS := 10

var phase := "start"
var loot_left := LOOT_TIME
var alive := SOLDIERS + 1
var player: Node3D
var boss: Node3D
var city: Node3D
var hud: CanvasLayer

var _env: Environment
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
var _storm := 0.0
var _thunder_t := 5.0
var _shake := 0.0
var _spectate_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("game")
	_rng.randomize()
	_build_world()
	city = load("res://scripts/city.gd").new()
	city.name = "City"
	add_child(city)
	city.call("build", _rng.randi())
	hud = load("res://scripts/hud.gd").new()
	hud.set("game", self)
	add_child(hud)
	_spawn_loot()
	_spawn_jeeps()
	_spawn_player()
	_spawn_soldiers()


# ------------------------------------------------------------------ world
func _build_world() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_sky = ProceduralSkyMaterial.new()
	_sky.sky_top_color = Color(0.25, 0.48, 0.85)
	_sky.sky_horizon_color = Color(0.7, 0.8, 0.9)
	_sky.ground_horizon_color = Color(0.6, 0.65, 0.7)
	_sky.ground_bottom_color = Color(0.3, 0.32, 0.35)
	var sky := Sky.new()
	sky.sky_material = _sky
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.9
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.7, 0.78, 0.88)
	_env.fog_density = 0.0035
	_env.fog_sky_affect = 0.3
	_env.glow_enabled = true
	_env.glow_intensity = 0.4
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	_sun.light_energy = 1.3
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	add_child(_sun)


func _spawn_loot() -> void:
	var pts: Array[Vector3] = city.get("loot_points")
	pts.shuffle()
	var scene: Script = load("res://scripts/loot.gd")
	var count := mini(pts.size(), 220)
	for i in count:
		var l: Area3D = scene.new()
		var r := _rng.randf()
		if r < 0.55:
			l.set("kind", "weapon")
			l.set("id", Weapons.LOOT_TABLE[_rng.randi() % Weapons.LOOT_TABLE.size()])
		elif r < 0.72:
			l.set("kind", "ammo")
		elif r < 0.86:
			l.set("kind", "armor")
		else:
			l.set("kind", "health")
		add_child(l)
		l.global_position = pts[i]


func drop_weapon(id: String, at: Vector3) -> void:
	var l: Area3D = load("res://scripts/loot.gd").new()
	l.set("kind", "weapon")
	l.set("id", id)
	add_child(l)
	l.global_position = at


func _spawn_jeeps() -> void:
	var pts: Array[Transform3D] = city.get("vehicle_points")
	pts.shuffle()
	for i in mini(pts.size(), MAX_JEEPS):
		var j: VehicleBody3D = load("res://scripts/jeep.gd").new()
		add_child(j)
		j.global_transform = pts[i]


func _spawn_player() -> void:
	player = load("res://scripts/player.gd").new()
	player.name = "Player"
	add_child(player)
	# drop in on a street (not an edge road), looking down the road
	var half: float = CityScript.HALF
	var cell: float = CityScript.CELL
	var ix := _rng.randi_range(1, CityScript.BLOCKS - 1)
	var iz := _rng.randi_range(1, CityScript.BLOCKS - 1)
	var node := Vector3(-half + ix * cell, 0, -half + iz * cell)
	player.global_position = node + Vector3(cell * 0.25, 0.5, 0)
	player.rotation.y = -PI * 0.5 if node.x < 0 else PI * 0.5


func _spawn_soldiers() -> void:
	var script: Script = load("res://scripts/soldier.gd")
	var nodes: Array[Vector3] = city.get("road_nodes")
	for i in SOLDIERS:
		var s: CharacterBody3D = script.new()
		s.set("city", city)
		add_child(s)
		var n: Vector3 = nodes[_rng.randi() % nodes.size()]
		s.global_position = n + Vector3(_rng.randf_range(-5, 5), 0.3, _rng.randf_range(-5, 5))


# ------------------------------------------------------------------ match flow
func _unhandled_input(event: InputEvent) -> void:
	if phase == "start" and (event is InputEventMouseButton and (event as InputEventMouseButton).pressed or event is InputEventJoypadButton or (event is InputEventKey and (event as InputEventKey).pressed)):
		phase = "loot"
		hud.set("start_screen", false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.call("banner", "GEAR UP!", "Thor arrives in 2:30 - find weapons, armor and a jeep", 4.0)
		get_viewport().set_input_as_handled()
	elif phase in ["won_end", "lost"] and _spectate_t > 1.5:
		if (event is InputEventKey and (event as InputEventKey).keycode == KEY_ENTER) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
			get_tree().reload_current_scene()


func _process(delta: float) -> void:
	match phase:
		"loot":
			loot_left -= delta
			if loot_left <= 12.0:
				_storm = minf(1.0, _storm + delta / 10.0)
			if loot_left <= 12.0 and loot_left + delta > 12.0:
				hud.call("banner", "THE SKY DARKENS...", "Something is coming", 3.0)
			if loot_left <= 0.0:
				_summon_thor()
		"boss", "won":
			_storm = minf(1.0, _storm + delta / 3.0)
		"lost", "won_end":
			_spectate_t += delta
			_spectate(delta)
	_update_storm(delta)
	_apply_shake(delta)


func _summon_thor() -> void:
	phase = "boss"
	loot_left = 0.0
	boss = load("res://scripts/thor.gd").new()
	boss.set("city", city)
	add_child(boss)
	# lands in front of you, somewhere on the street, so you see the entrance
	var p := player.global_position if player and not bool(player.get("dead")) else Vector3.ZERO
	var fwd := -player.global_transform.basis.z if player else Vector3.FORWARD
	var spot := p + Vector3(fwd.x, 0, fwd.z).normalized() * 35.0
	spot = _snap_to_road(spot)
	boss.global_position = spot + Vector3(0, 120, 0)
	hud.call("banner", "THOR HAS ARRIVED!", "Kill the God of Thunder before he wipes everyone out", 4.0)


func _snap_to_road(p: Vector3) -> Vector3:
	var cell: float = CityScript.CELL
	var half: float = CityScript.HALF
	var x := -half + roundf((p.x + half) / cell) * cell
	var z := -half + roundf((p.z + half) / cell) * cell
	if absf(p.x - x) < absf(p.z - z):
		return Vector3(x, 0, clampf(p.z, -half, half))
	return Vector3(clampf(p.x, -half, half), 0, z)


func on_fighter_died(who: Node) -> void:
	alive = maxi(0, alive - 1)
	if who == player:
		phase = "lost"
		hud.set("end_title", "YOU DIED")
		hud.set("end_sub", "You placed #%d of 100.  Thor still stands." % (alive + 1))
		return
	var callsign := String(who.get("callsign"))
	if randf() < 0.5 or alive < 20:
		hud.call("feed", "Thor crushed Spartan %s" % callsign)
	if alive == 0 and phase == "boss":
		phase = "lost"
		hud.set("end_title", "THOR WINS")
		hud.set("end_sub", "Every soldier has fallen.")


func on_boss_defeated(at: Vector3) -> void:
	phase = "won"
	hud.call("banner", "THOR HAS FALLEN!", "Grab Mjolnir - it's yours now", 5.0)
	var p := at
	p.y = 0.8
	drop_weapon("hammer", p + Vector3(2.5, 0, 0))
	# the moment you pick it up, the level is won
	var watch := func():
		while is_inside_tree() and phase == "won":
			await get_tree().create_timer(0.3).timeout
			if player and not bool(player.get("dead")):
				for w in player.get("slots"):
					if w["id"] == "hammer":
						phase = "won_end"
						hud.set("end_title", "MJOLNIR IS YOURS")
						hud.set("end_sub", "%d soldiers survived.  Next: the Greek gods - ZEUS awaits." % alive)
						Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
						return
	watch.call()


func on_building_smashed(_at: Vector3) -> void:
	shake_at(_at, 0.35, 120.0)


func banner(t: String, s: String, secs: float) -> void:
	hud.call("banner", t, s, secs)


## damage everything in a radius. Friendly fire is off: soldiers' and your
## explosions only hurt Thor and vehicles; Thor's hurt everyone.
func explode(at: Vector3, radius: float, dmg: float, by: Node = null, knock: bool = false) -> void:
	var from_thor := by != null and by == boss
	if from_thor:
		for f in get_tree().get_nodes_in_group("fighters"):
			var d := (f as Node3D).global_position.distance_to(at)
			if d < radius:
				var k := 1.0 - d / radius * 0.6
				f.call("take_damage", dmg * k, by)
				if knock and f is CharacterBody3D:
					var away := ((f as Node3D).global_position - at)
					away.y = 0
					(f as CharacterBody3D).velocity += away.normalized() * 10.0 * k + Vector3(0, 6.0 * k, 0)
	elif boss and is_instance_valid(boss) and not bool(boss.get("dead")):
		var bd := (boss.global_position + Vector3(0, 3, 0)).distance_to(at)
		if bd < radius + 2.5:
			boss.call("take_damage", dmg * clampf(1.2 - bd / (radius + 2.5), 0.3, 1.0), by)
			if by == player:
				hud.call("hitmarker", false)
	for v in get_tree().get_nodes_in_group("vehicles"):
		var d := (v as Node3D).global_position.distance_to(at)
		if d < radius:
			v.call("take_damage", dmg * (1.0 - d / radius) * (1.0 if from_thor else 0.4), by)
			(v as RigidBody3D).apply_central_impulse(((v as Node3D).global_position - at).normalized() * 3000.0 * (1.0 - d / radius) + Vector3(0, 2500, 0) * (1.0 - d / radius))
	Sounds.play(self, Sounds.boom(), at, -2.0 if radius < 5.0 else 3.0)


func shake_at(at: Vector3, amount: float, rng: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var d := cam.global_position.distance_to(at)
		if d < rng:
			_shake = maxf(_shake, amount * (1.0 - d / rng))


func _apply_shake(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	cam.h_offset = randf_range(-1, 1) * _shake * 0.4
	cam.v_offset = randf_range(-1, 1) * _shake * 0.4


func _update_storm(delta: float) -> void:
	var s := _storm
	_sky.sky_top_color = Color(0.25, 0.48, 0.85).lerp(Color(0.12, 0.13, 0.2), s)
	_sky.sky_horizon_color = Color(0.7, 0.8, 0.9).lerp(Color(0.3, 0.32, 0.4), s)
	_sun.light_energy = lerpf(1.3, 0.45, s)
	_env.fog_density = lerpf(0.0035, 0.009, s)
	_env.fog_light_color = Color(0.7, 0.78, 0.88).lerp(Color(0.25, 0.27, 0.35), s)
	_env.ambient_light_energy = lerpf(0.9, 0.55, s)
	if s > 0.5 and phase in ["boss", "loot"]:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(3.0, 8.0)
			# distant flash
			_sun.light_energy = 3.0
			var p := player.global_position if player else Vector3.ZERO
			FX.lightning(self, p + Vector3(randf_range(-150, 150), 120, randf_range(-150, 150)), p + Vector3(randf_range(-150, 150), 30, randf_range(-150, 150)))
			Sounds.play(self, Sounds.thunder(), p + Vector3(0, 40, 0), -6.0)


func _spectate(delta: float) -> void:
	# after you die: a slow camera orbit around Thor (or the fallen god)
	var cam := get_viewport().get_camera_3d()
	if cam == null or boss == null or not is_instance_valid(boss):
		return
	var a := _spectate_t * 0.2
	var target := boss.global_position + Vector3(0, 4, 0)
	cam.global_position = cam.global_position.lerp(target + Vector3(cos(a) * 28, 14, sin(a) * 28), minf(1.0, delta * 2.0))
	cam.look_at(target, Vector3.UP)
