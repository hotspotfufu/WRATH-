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


static func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float = 0.5, metal: float = 0.6) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## a chunky gun model, pointing down -Z. Used both in your hands and as loot.
static func build_model(id: String) -> Node3D:
	var root := Node3D.new()
	var c: Color = info(id)["color"]
	var dark := c.darkened(0.4)
	var accent := Color(0.35, 0.75, 1.0)
	match id:
		"pistol":
			_part(root, Vector3(0.06, 0.07, 0.26), Vector3(0, 0, -0.06), c)
			_part(root, Vector3(0.05, 0.14, 0.07), Vector3(0, -0.09, 0.04), dark)
			_part(root, Vector3(0.02, 0.02, 0.05), Vector3(0, 0.045, -0.15), accent, 0.2, 0.0)
		"rifle":
			_part(root, Vector3(0.09, 0.12, 0.62), Vector3(0, 0, -0.12), c)
			_part(root, Vector3(0.04, 0.04, 0.22), Vector3(0, 0.01, -0.53), dark)
			_part(root, Vector3(0.06, 0.16, 0.08), Vector3(0, -0.13, -0.06), dark)
			_part(root, Vector3(0.07, 0.12, 0.07), Vector3(0, -0.1, 0.1), dark)
			_part(root, Vector3(0.08, 0.1, 0.2), Vector3(0, 0.0, 0.26), c.lightened(0.1))
			_part(root, Vector3(0.05, 0.05, 0.12), Vector3(0, 0.09, -0.1), Color(0.1, 0.1, 0.12))
			_part(root, Vector3(0.03, 0.05, 0.05), Vector3(0.05, 0.03, -0.2), accent, 0.2, 0.0)
		"shotgun":
			_part(root, Vector3(0.1, 0.11, 0.7), Vector3(0, 0, -0.15), c, 0.7, 0.2)
			_part(root, Vector3(0.06, 0.06, 0.55), Vector3(0, -0.07, -0.22), dark)
			_part(root, Vector3(0.08, 0.13, 0.22), Vector3(0, -0.05, 0.26), Color(0.42, 0.26, 0.14), 0.8, 0.0)
		"sniper":
			_part(root, Vector3(0.08, 0.1, 0.9), Vector3(0, 0, -0.2), c)
			_part(root, Vector3(0.035, 0.035, 0.35), Vector3(0, 0.01, -0.8), dark)
			_part(root, Vector3(0.07, 0.07, 0.3), Vector3(0, 0.11, -0.12), Color(0.08, 0.08, 0.1))
			_part(root, Vector3(0.05, 0.05, 0.02), Vector3(0, 0.11, -0.28), accent, 0.1, 0.0)
			_part(root, Vector3(0.07, 0.12, 0.25), Vector3(0, -0.03, 0.3), c.lightened(0.1))
		"rocket":
			_part(root, Vector3(0.2, 0.2, 1.0), Vector3(0, 0.02, -0.15), c, 0.7, 0.2)
			_part(root, Vector3(0.24, 0.24, 0.12), Vector3(0, 0.02, -0.66), dark)
			_part(root, Vector3(0.06, 0.15, 0.08), Vector3(0, -0.15, 0.0), dark)
			_part(root, Vector3(0.08, 0.06, 0.12), Vector3(0.12, 0.08, -0.1), Color(0.9, 0.5, 0.1), 0.4, 0.0)
		"hammer":
			_part(root, Vector3(0.055, 0.055, 0.5), Vector3(0, 0, 0.05), Color(0.35, 0.22, 0.12), 0.8, 0.0)
			_part(root, Vector3(0.36, 0.22, 0.24), Vector3(0, 0, -0.28), c, 0.3, 0.9)
			_part(root, Vector3(0.38, 0.04, 0.26), Vector3(0, 0.0, -0.28), Color(0.5, 0.75, 1.0), 0.1, 0.0)
	return root


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
