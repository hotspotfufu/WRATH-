extends Area3D
## Loot lying around the city.
##   kind "weapon": press E to pick up (id = pistol / rifle / shotgun / sniper / rocket / hammer)
##   kind "ammo", "armor", "health": picked up just by walking over them

var kind := "weapon"
var id := "rifle"
var _t := 0.0
var _model: Node3D
var _taken := false

const COLORS := {"weapon": Color(0.4, 0.8, 1.0), "ammo": Color(1.0, 0.8, 0.3), "armor": Color(0.3, 0.6, 1.0), "health": Color(0.4, 1.0, 0.45)}


func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 16
	collision_mask = 2 | 4
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 0.9
	cs.shape = sp
	add_child(cs)
	var col: Color = COLORS.get(kind, Color.WHITE)
	if kind == "weapon":
		_model = Weapons.build_model(id)
		_model.scale = Vector3.ONE * (1.6 if id != "hammer" else 2.2)
	elif kind == "ammo" and Models.has("ammo_box.res"):
		_model = Models.ammo_box()          # the bought military ammo can
	else:
		_model = Node3D.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 0.3, 0.35) if kind != "armor" else Vector3(0.5, 0.55, 0.2)
		var m := StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.2)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.6
		bm.material = m
		mi.mesh = bm
		_model.add_child(mi)
		if kind == "health":
			var cross := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = Vector3(0.12, 0.32, 0.37)
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color.WHITE
			cb.material = wm
			cross.mesh = cb
			_model.add_child(cross)
	add_child(_model)
	# glowing ring on the ground + light beam so loot is easy to spot
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.65
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = col
	tm.material = rm
	ring.mesh = tm
	ring.position.y = -0.5
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.25
	cyl.height = 3.0
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.albedo_color = Color(col.r, col.g, col.b, 0.25)
	cyl.material = bmat
	beam.mesh = cyl
	beam.position.y = 1.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	_t = randf() * 10.0
	body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_t += delta
	_model.rotation.y = _t * 1.5
	_model.position.y = sin(_t * 2.0) * 0.08


func label() -> String:
	if kind == "weapon":
		return Weapons.info(id)["name"]
	return kind.to_upper()


func _on_body(body: Node) -> void:
	if kind != "weapon":
		take(body)


func take(by: Node) -> void:
	if _taken or by == null:
		return
	match kind:
		"weapon":
			if by.has_method("give_weapon"):
				by.call("give_weapon", id)
			else:
				return
		"ammo":
			if by.has_method("give_ammo"):
				by.call("give_ammo")
		"armor":
			if by.has_method("give_armor"):
				by.call("give_armor")
		"health":
			if by.has_method("heal"):
				by.call("heal", 40.0)
	_taken = true
	if by.is_in_group("player"):
		Sounds.play(get_parent(), Sounds.pickup(), global_position, -4.0)
	queue_free()
