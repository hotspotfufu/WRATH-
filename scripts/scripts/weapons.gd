class_name Weapons
extends RefCounted
## Weapon stats, the gun models you hold, and the rocket projectile.

const DATA := {
	"pistol":  {"name": "PISTOL", "damage": 24.0, "rate": 0.22, "auto": false, "mag": 12, "reserve": 72, "spread": 0.6, "pellets": 1, "range": 140.0, "reload": 1.2, "zoom": 60.0, "color": Color(0.22, 0.22, 0.25)},
	"rifle":   {"name": "ASSAULT RIFLE", "damage": 17.0, "rate": 0.085, "auto": true, "mag": 32, "reserve": 192, "spread": 1.3, "pellets": 1, "range": 160.0, "reload": 1.8, "zoom": 52.0, "color": Color(0.2, 0.26, 0.2)},
	"shotgun": {"name": "SHOTGUN", "damage": 13.0, "rate": 0.8, "auto": false, "mag": 6, "reserve": 30, "spread": 5.5, "pellets": 9, "range": 45.0, "reload": 2.4, "zoom": 62.0, "color": Color(0.32, 0.22, 0.15)},
	"sniper":  {"name": "SNIPER RIFLE", "damage": 140.0, "rate": 1.1, "auto": false, "mag": 4, "reserve": 20, "spread": 0.0, "pellets": 1, "range": 400.0, "reload": 2.2, "zoom": 18.0, "color": Color(0.18, 0.2, 0.24)},
	"rocket":  {"name": "ROCKET LAUNCHER", "damage": 260.0, "rate": 1.3, "auto": false, "mag": 2, "reserve": 8, "spread": 0.0, "pellets": 1, "range": 300.0, "reload": 2.8, "zoom": 50.0, "color": Color(0.3, 0.33, 0.22), "rocket": true},
	"hammer":  {"name": "MJOLNIR", "damage": 220.0, "rate": 0.55, "auto": false, "mag": 1, "reserve": 0, "spread": 0.0, "pellets": 1, "range": 3.5, "reload": 0.0, "zoom": 70.0, "color": Color(0.6, 0.62, 0.66), "melee": true},
}

const LOOT_TABLE := ["pistol", "rifle", "rifle", "rifle", "rifle", "shotgun", "shotgun", "shotgun", "sniper", "sniper", "rocket"]


static func info(id: String) -> Dictionary:
	return DATA.get(id, DATA["pistol"])


static var _mcache := {}


## material: gunmetal / polymer / wood / accents. Metal parts get a scratched texture.
static func _mat(color: Color, rough: float, metal: float, textured: bool = true, glow: float = 0.0) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s_%s" % [color.to_html(), rough, metal, textured, glow]
	if _mcache.has(key):
		return _mcache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if textured:
		m.albedo_texture = load("res://scripts/tex_metal.png")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * 3.0
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	_mcache[key] = m
	return m


static func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float = 0.45, metal: float = 0.7, textured: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color, rough, metal, textured)
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## a round part (barrel, scope, rocket tube) lying along Z
static func _tube(parent: Node3D, radius: float, length: float, pos: Vector3, color: Color, rough: float = 0.35, metal: float = 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 12
	cm.rings = 1
	cm.material = _mat(color, rough, metal)
	mi.mesh = cm
	mi.rotation.x = PI * 0.5
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


const GUNMETAL := Color(0.16, 0.17, 0.18)
const POLYMER := Color(0.1, 0.1, 0.11)
const STEEL := Color(0.42, 0.43, 0.45)


## a detailed gun model, pointing down -Z. Used in your hands and as loot.
static func build_model(id: String) -> Node3D:
	# the bought, fully textured gun models (pistol, rifle, shotgun, sniper)
	if Models.has_gun(id):
		return Models.gun(id)
	var root := Node3D.new()
	var c: Color = info(id)["color"]
	var glow := _mat(Color(0.35, 0.75, 1.0), 0.2, 0.0, false, 2.0)
	match id:
		"pistol":
			_part(root, Vector3(0.034, 0.045, 0.22), Vector3(0, 0.012, -0.07), STEEL, 0.3, 0.9)          # slide
			for i in 6:
				_part(root, Vector3(0.036, 0.03, 0.006), Vector3(0, 0.014, 0.01 + i * 0.012), GUNMETAL)  # slide serrations
			_part(root, Vector3(0.03, 0.03, 0.2), Vector3(0, -0.022, -0.06), POLYMER, 0.7, 0.1, false)   # frame
			var g := _part(root, Vector3(0.032, 0.12, 0.055), Vector3(0, -0.085, 0.03), POLYMER, 0.8, 0.0, false)
			g.rotation.x = -0.25
			_part(root, Vector3(0.008, 0.012, 0.012), Vector3(0, 0.04, -0.17), GUNMETAL)                 # front sight
			_part(root, Vector3(0.026, 0.012, 0.01), Vector3(0, 0.04, 0.03), GUNMETAL)                   # rear sight
			_part(root, Vector3(0.02, 0.025, 0.05), Vector3(0, -0.045, -0.01), GUNMETAL)                 # trigger guard
		"rifle":
			_part(root, Vector3(0.06, 0.075, 0.36), Vector3(0, 0, -0.06), c, 0.5, 0.5)                   # receiver
			_part(root, Vector3(0.064, 0.012, 0.42), Vector3(0, 0.044, -0.09), GUNMETAL)                 # top rail
			for i in 12:
				_part(root, Vector3(0.066, 0.008, 0.012), Vector3(0, 0.054, -0.28 + i * 0.034), GUNMETAL)
			_part(root, Vector3(0.068, 0.07, 0.24), Vector3(0, 0.0, -0.36), POLYMER, 0.75, 0.0, false)   # handguard
			for i in 4:
				_part(root, Vector3(0.07, 0.04, 0.012), Vector3(0, -0.005, -0.28 - i * 0.05), GUNMETAL)  # vents
			_tube(root, 0.012, 0.22, Vector3(0, 0.006, -0.57), GUNMETAL)                                 # barrel
			_tube(root, 0.02, 0.06, Vector3(0, 0.006, -0.68), STEEL)                                     # muzzle brake
			var mag := _part(root, Vector3(0.04, 0.18, 0.08), Vector3(0, -0.12, -0.1), POLYMER, 0.7, 0.1, false)
			mag.rotation.x = 0.22
			var grip := _part(root, Vector3(0.035, 0.12, 0.05), Vector3(0, -0.09, 0.07), POLYMER, 0.85, 0.0, false)
			grip.rotation.x = -0.3
			_part(root, Vector3(0.05, 0.07, 0.22), Vector3(0, -0.005, 0.24), POLYMER, 0.75, 0.0, false)  # stock
			_part(root, Vector3(0.055, 0.1, 0.03), Vector3(0, -0.015, 0.36), Color(0.2, 0.2, 0.2), 0.9, 0.0, false)
			# holo sight
			_part(root, Vector3(0.045, 0.05, 0.08), Vector3(0, 0.08, -0.12), POLYMER, 0.5, 0.3)
			_part(root, Vector3(0.036, 0.034, 0.004), Vector3(0, 0.088, -0.16), Color(0.2, 0.5, 0.6), 0.05, 0.0, false)
			_part(root, Vector3(0.006, 0.006, 0.002), Vector3(0, 0.088, -0.163), Color(1, 0.2, 0.2), 0.1, 0.0, false)
			_part(root, Vector3(0.02, 0.03, 0.04), Vector3(0.04, 0.02, -0.06), glow.albedo_color, 0.2, 0.0, false)   # ammo counter
		"shotgun":
			_part(root, Vector3(0.065, 0.08, 0.3), Vector3(0, 0, -0.02), GUNMETAL, 0.45, 0.8)           # receiver
			_tube(root, 0.018, 0.55, Vector3(0, 0.018, -0.44), GUNMETAL)                                 # barrel
			_tube(root, 0.016, 0.45, Vector3(0, -0.022, -0.38), STEEL)                                   # tube magazine
			var pump := _part(root, Vector3(0.06, 0.06, 0.18), Vector3(0, -0.02, -0.32), Color(0.38, 0.24, 0.13), 0.8, 0.0, false)
			for i in 5:
				_part(root, Vector3(0.062, 0.062, 0.008), Vector3(0, -0.02, -0.25 - i * 0.03), Color(0.28, 0.17, 0.09), 0.9, 0.0, false)
			pump.name = "Pump"
			var grip := _part(root, Vector3(0.04, 0.11, 0.06), Vector3(0, -0.08, 0.12), Color(0.38, 0.24, 0.13), 0.8, 0.0, false)
			grip.rotation.x = -0.35
			_part(root, Vector3(0.055, 0.09, 0.26), Vector3(0, -0.04, 0.28), Color(0.38, 0.24, 0.13), 0.8, 0.0, false)  # wood stock
			_part(root, Vector3(0.01, 0.014, 0.01), Vector3(0, 0.04, -0.7), Color(1.0, 0.5, 0.2), 0.3, 0.0, false)    # bead sight
			for i in 4:
				_part(root, Vector3(0.014, 0.02, 0.02), Vector3(0.04, -0.01, 0.0 + i * 0.03), Color(0.75, 0.1, 0.08), 0.6, 0.0, false)   # side shells
		"sniper":
			_part(root, Vector3(0.06, 0.075, 0.42), Vector3(0, 0, -0.05), c, 0.5, 0.5)
			_tube(root, 0.014, 0.6, Vector3(0, 0.005, -0.55), GUNMETAL)
			_part(root, Vector3(0.05, 0.05, 0.1), Vector3(0, 0.005, -0.88), STEEL)                        # muzzle brake
			_tube(root, 0.03, 0.34, Vector3(0, 0.11, -0.08), POLYMER, 0.4, 0.4)                           # scope
			_tube(root, 0.038, 0.06, Vector3(0, 0.11, -0.27), POLYMER, 0.4, 0.4)
			_tube(root, 0.036, 0.05, Vector3(0, 0.11, 0.1), POLYMER, 0.4, 0.4)
			_part(root, Vector3(0.05, 0.003, 0.003), Vector3(0, 0.11, -0.302), Color(0.3, 0.7, 1.0), 0.05, 0.0, false)
			_part(root, Vector3(0.02, 0.04, 0.02), Vector3(0, 0.07, -0.16), GUNMETAL)                     # scope rings
			_part(root, Vector3(0.02, 0.04, 0.02), Vector3(0, 0.07, 0.0), GUNMETAL)
			var mag := _part(root, Vector3(0.04, 0.1, 0.08), Vector3(0, -0.08, -0.08), POLYMER, 0.7, 0.1, false)
			var grip := _part(root, Vector3(0.035, 0.12, 0.05), Vector3(0, -0.09, 0.1), POLYMER, 0.85, 0.0, false)
			grip.rotation.x = -0.3
			_part(root, Vector3(0.055, 0.11, 0.3), Vector3(0, -0.02, 0.32), c.lightened(0.05), 0.7, 0.1, false)
			_part(root, Vector3(0.01, 0.06, 0.01), Vector3(0.035, 0.03, 0.02), STEEL)                     # bolt handle
			for side in [-1.0, 1.0]:
				var leg := _part(root, Vector3(0.012, 0.16, 0.012), Vector3(side * 0.025, -0.07, -0.55), GUNMETAL)
				leg.rotation.x = 1.2
		"rocket":
			_tube(root, 0.075, 1.0, Vector3(0, 0.03, -0.15), Color(0.33, 0.36, 0.25), 0.7, 0.2)
			_tube(root, 0.09, 0.12, Vector3(0, 0.03, -0.66), GUNMETAL)
			_tube(root, 0.085, 0.1, Vector3(0, 0.03, 0.36), GUNMETAL)
			_part(root, Vector3(0.05, 0.13, 0.07), Vector3(0, -0.11, 0.0), POLYMER, 0.8, 0.0, false)
			_part(root, Vector3(0.05, 0.12, 0.07), Vector3(0, -0.1, -0.3), POLYMER, 0.8, 0.0, false)
			_part(root, Vector3(0.05, 0.06, 0.14), Vector3(-0.1, 0.09, -0.15), POLYMER, 0.5, 0.3)        # sight
			_part(root, Vector3(0.04, 0.04, 0.003), Vector3(-0.1, 0.09, -0.222), Color(0.9, 0.5, 0.15), 0.1, 0.0, false)
			_part(root, Vector3(0.16, 0.012, 0.3), Vector3(0, 0.11, -0.1), Color(0.9, 0.75, 0.2), 0.6, 0.0, false)  # warning stripe
		"hammer":
			_tube(root, 0.028, 0.5, Vector3(0, 0, 0.05), Color(0.35, 0.22, 0.12), 0.85, 0.0)
			for i in 6:
				_tube(root, 0.031, 0.02, Vector3(0, 0, 0.2 - i * 0.06), Color(0.25, 0.15, 0.08), 0.9, 0.0)   # leather wrap
			_part(root, Vector3(0.36, 0.22, 0.24), Vector3(0, 0, -0.28), Color(0.6, 0.62, 0.66), 0.25, 0.95)
			_part(root, Vector3(0.38, 0.04, 0.26), Vector3(0, 0.0, -0.28), Color(0.5, 0.75, 1.0), 0.1, 0.0, false)
			_part(root, Vector3(0.04, 0.24, 0.26), Vector3(0.19, 0, -0.28), Color(0.5, 0.52, 0.56), 0.3, 0.9)
			_part(root, Vector3(0.04, 0.24, 0.26), Vector3(-0.19, 0, -0.28), Color(0.5, 0.52, 0.56), 0.3, 0.9)
	return root


# ======================================================================= armored hands
## where each hand grabs the gun: [right grip, left support] in gun space
const GRIPS := {
	"pistol": [Vector3(0, -0.07, 0.035), Vector3(-0.012, -0.08, 0.05)],
	"rifle": [Vector3(0, -0.08, 0.07), Vector3(0, -0.045, -0.36)],
	"shotgun": [Vector3(0, -0.07, 0.11), Vector3(0, -0.055, -0.32)],
	"sniper": [Vector3(0, -0.08, 0.1), Vector3(0, -0.05, -0.3)],
	"rocket": [Vector3(0, -0.13, 0.0), Vector3(0, -0.12, -0.3)],
	"hammer": [Vector3(0, 0, 0.12), Vector3(0, 0, 0.24)],
}

const GLOVE := Color(0.2, 0.3, 0.32)          # dark teal glove (like the reference art)
const PLATE := Color(0.58, 0.6, 0.62)         # grey armor plates


static func _glove_mat() -> StandardMaterial3D:
	if _mcache.has("glove"):
		return _mcache["glove"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://scripts/tex_glove.png")
	m.albedo_color = Color(1.1, 1.18, 1.18)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 8.0
	m.roughness = 0.85
	_mcache["glove"] = m
	return m


static func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## one armored hand wrapped around a grip, with its forearm reaching back to the camera.
## side = 1 right hand, -1 left hand
static func _hand(parent: Node3D, at: Vector3, side: float, elbow: Vector3, vertical_grip: bool) -> void:
	var glove := _glove_mat()
	var plate := _mat(PLATE, 0.4, 0.75)
	var dark := _mat(Color(0.12, 0.13, 0.14), 0.5, 0.6)
	var hand := Node3D.new()
	hand.position = at
	if not vertical_grip:
		hand.rotation.z = -side * 1.1        # support hand cups the handguard from below / the side
	parent.add_child(hand)
	# palm + back-of-hand armor plate (on the outside)
	_box(hand, Vector3(0.05, 0.095, 0.09), Vector3(side * 0.035, 0.0, 0.0), glove)
	_box(hand, Vector3(0.016, 0.085, 0.08), Vector3(side * 0.064, 0.005, 0.0), plate)
	_box(hand, Vector3(0.006, 0.03, 0.03), Vector3(side * 0.073, 0.02, 0.0), dark)
	# four fingers curled around the grip, each with an armor plate on the knuckle
	for i in 4:
		var y := 0.035 - i * 0.024
		var f := Node3D.new()
		f.position = Vector3(side * 0.03, y, -0.04)
		hand.add_child(f)
		_box(f, Vector3(0.02, 0.02, 0.045), Vector3(0, 0, -0.018), glove)                     # first segment, reaching forward
		_box(f, Vector3(0.022, 0.012, 0.028), Vector3(0, 0, -0.022), plate).position.x = side * 0.004
		_box(f, Vector3(0.019, 0.019, 0.04), Vector3(-side * 0.03, 0, -0.04), glove, Vector3(0, -side * 1.3, 0))   # curled around
		_box(f, Vector3(0.016, 0.017, 0.03), Vector3(-side * 0.06, 0, -0.02), glove, Vector3(0, -side * 2.4, 0))
		_box(f, Vector3(0.012, 0.02, 0.022), Vector3(-side * 0.03, 0, -0.05), plate, Vector3(0, -side * 1.3, 0))
	# thumb over the top
	_box(hand, Vector3(0.02, 0.02, 0.05), Vector3(-side * 0.02, 0.055, -0.02), glove, Vector3(0, side * 0.6, 0))
	_box(hand, Vector3(0.022, 0.01, 0.03), Vector3(-side * 0.02, 0.066, -0.025), plate, Vector3(0, side * 0.6, 0))
	# wrist cuff
	_box(hand, Vector3(0.075, 0.09, 0.04), Vector3(side * 0.035, -0.005, 0.06), dark)
	# forearm: from the wrist back toward the elbow (bottom of the screen)
	var arm := Node3D.new()
	parent.add_child(arm)
	var w_local := at + Vector3(side * 0.035, -0.005, 0.07)
	var dirv := elbow - w_local
	var length := dirv.length()
	arm.position = w_local + dirv * 0.5
	arm.basis = Basis.looking_at(dirv.normalized(), Vector3.UP)
	_box(arm, Vector3(0.07, 0.07, length), Vector3.ZERO, glove)
	_box(arm, Vector3(0.074, 0.018, length * 0.55), Vector3(0, 0.038, -length * 0.15), plate)          # forearm armor
	_box(arm, Vector3(0.018, 0.045, length * 0.4), Vector3(side * 0.037, 0.008, -length * 0.1), plate)
	_box(arm, Vector3(0.02, 0.012, 0.03), Vector3(0, 0.064, -length * 0.25), _mat(Color(0.35, 0.8, 1.0), 0.2, 0.0, false, 2.0))   # status light


## adds both armored hands (and forearms) to a gun model for the first-person view
static func add_hands(model: Node3D, id: String) -> void:
	var g: Array = (GRIPS.get(id, GRIPS["rifle"]) as Array).duplicate()
	if Models.has_gun(id):
		g[1] = Models.left_grip(id)       # support hand on the bought gun's fore-end
	if id == "hammer":
		_hand(model, g[0], 1.0, Vector3(0.12, -0.32, 0.55), true)
		return
	_hand(model, g[0], 1.0, Vector3(0.14, -0.3, 0.5), true)
	if id == "pistol":
		_hand(model, g[1], -1.0, Vector3(-0.2, -0.32, 0.45), true)
	else:
		_hand(model, g[1], -1.0, Vector3(-0.28, -0.3, 0.2), false)


# ======================================================================= rocket
class Rocket extends Area3D:
	var dir := Vector3.FORWARD
	var speed := 42.0
	var damage := 260.0
	var radius := 7.0
	var owner_node: Node = null
	var _t := 0.0
	var _done := false

	func _ready() -> void:
		collision_layer = 0
		collision_mask = 1 | 8 | 32
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 0.25
		cs.shape = sp
		add_child(cs)
		var body := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.09
		cyl.height = 0.6
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 0.42, 0.35)
		cyl.material = m
		body.mesh = cyl
		body.rotation.x = PI * 0.5
		add_child(body)
		var trail := CPUParticles3D.new()
		trail.amount = 50
		trail.lifetime = 0.6
		trail.local_coords = false
		trail.direction = Vector3(0, 0, 1)
		trail.spread = 8.0
		trail.initial_velocity_min = 1.0
		trail.initial_velocity_max = 2.0
		trail.gravity = Vector3(0, 1.0, 0)
		var q := QuadMesh.new()
		q.size = Vector2(0.45, 0.45)
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.albedo_texture = FX.soft_texture()
		pm.vertex_color_use_as_albedo = true
		q.material = pm
		trail.mesh = q
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
		g.set_color(1, Color(0.6, 0.6, 0.6, 0.0))
		trail.color_ramp = g
		trail.position = Vector3(0, 0, 0.3)
		add_child(trail)
		body_entered.connect(func(_b): _boom.call_deferred())

	func _physics_process(delta: float) -> void:
		if _done:
			return
		_t += delta
		global_position += dir * speed * delta
		if _t > 4.0:
			_boom()

	func _boom() -> void:
		if _done:
			return
		_done = true
		FX.explosion(get_parent(), global_position, radius * 0.6)
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.call("explode", global_position, radius, damage, owner_node)
		queue_free()
