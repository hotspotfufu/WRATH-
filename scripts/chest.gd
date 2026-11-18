extends StaticBody3D
## A military supply chest. Walk up and press E (gamepad X) to pop it open:
## the lid swings up, a glow bursts out, and 2 guns (sometimes armor or health) pop out.

var opened := false
var _lid: Node3D
var _glow: OmniLight3D
var _beam: MeshInstance3D

const CHEST_LOOT := ["rifle", "rifle", "shotgun", "shotgun", "sniper", "sniper", "rocket"]


func _ready() -> void:
	add_to_group("chests")
	collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.3, 0.75, 0.8)
	cs.shape = bs
	cs.position.y = 0.375
	add_child(cs)
	var dir: String = get_script().resource_path.get_base_dir()
	var metal := StandardMaterial3D.new()
	metal.albedo_texture = load(dir + "/tex_metal.png")
	metal.albedo_color = Color(0.36, 0.42, 0.3)
	metal.roughness = 0.5
	metal.metallic = 0.4
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.15, 0.15, 0.16)
	trim.metallic = 0.7
	trim.roughness = 0.35
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.75, 0.25)
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.7, 0.2)
	gold.emission_energy_multiplier = 1.2
	_part(self, Vector3(1.3, 0.55, 0.8), Vector3(0, 0.275, 0), metal)
	_part(self, Vector3(1.34, 0.08, 0.84), Vector3(0, 0.05, 0), trim)
	for x in [-0.55, 0.55]:
		_part(self, Vector3(0.08, 0.57, 0.84), Vector3(x, 0.285, 0), trim)
	# lid hinged at the back
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.55, -0.4)
	add_child(_lid)
	_part(_lid, Vector3(1.3, 0.2, 0.8), Vector3(0, 0.1, 0.4), metal)
	_part(_lid, Vector3(1.34, 0.06, 0.84), Vector3(0, 0.2, 0.4), trim)
	_part(_lid, Vector3(0.22, 0.14, 0.05), Vector3(0, 0.02, 0.82), gold)      # glowing latch
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.8, 0.4)
	_glow.light_energy = 0.6
	_glow.omni_range = 3.0
	_glow.position = Vector3(0, 0.9, 0.5)
	add_child(_glow)


func _part(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func open(by: Node) -> void:
	if opened:
		return
	opened = true
	remove_from_group("chests")
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_glow.light_energy = 3.0
	create_tween().tween_property(_glow, "light_energy", 0.0, 1.2)
	FX.sparks(get_parent(), global_position + Vector3(0, 0.9, 0), Color(1.0, 0.85, 0.4))
	Sounds.play(get_parent(), Sounds.pickup(), global_position, 0.0)
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var fwd := global_transform.basis.z
	var side := global_transform.basis.x
	for k in 2:
		var id: String = CHEST_LOOT[randi() % CHEST_LOOT.size()]
		game.call("drop_weapon", id, global_position + fwd * 1.1 + side * (k - 0.5) * 1.1 + Vector3(0, 0.6, 0))
	if randf() < 0.6:
		var l: Area3D = load("res://scripts/loot.gd").new()
		l.set("kind", "armor" if randf() < 0.5 else "health")
		game.add_child(l)
		l.global_position = global_position + fwd * 1.8 + Vector3(0, 0.6, 0)
