class_name Models
## Loads the bought 3D models (guns, soldier, ruined buildings, ammo box) and builds
## their materials. Everything is cached, so 25 soldiers share one copy of each mesh
## and texture. If a file is missing the game falls back to the old code-built look.

const DIR := "res://scripts/"

static var _cache := {}


static func has(file: String) -> bool:
	return ResourceLoader.exists(DIR + file)


static func res(file: String) -> Resource:
	if not _cache.has(file):
		_cache[file] = load(DIR + file) if has(file) else null
	return _cache[file]


## albedo + normal + packed AO/roughness/metal ("orm") material
static func pbr(prefix: String, ao := false) -> StandardMaterial3D:
	var key := "mat_" + prefix
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = res(prefix + "_a.jpg")
	var n: Texture2D = res(prefix + "_n.jpg")
	if n:
		m.normal_enabled = true
		m.normal_texture = n
	var o: Texture2D = res(prefix + "_orm.jpg")
	if o:
		m.roughness = 1.0
		m.roughness_texture = o
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic = 1.0
		m.metallic_texture = o
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		if ao:
			m.ao_enabled = true
			m.ao_texture = o
			m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_cache[key] = m
	return m


# ======================================================================= guns
## Grip spots on each bought gun (gun points down -Z): [right hand, left hand].
## The model is shifted so its right-hand grip sits where the old code-built gun's did,
## so the camera framing and the armored gloves line up with no other changes.
const GUN_GRIP := {
	"pistol":  [Vector3(0, -0.045, 0.05), Vector3(-0.012, -0.06, 0.06)],
	"rifle":   [Vector3(0, -0.07, 0.05), Vector3(0, -0.03, -0.25)],
	"shotgun": [Vector3(0, -0.03, 0.04), Vector3(0, -0.02, -0.45)],
	"sniper":  [Vector3(0, -0.06, 0.17), Vector3(0, -0.03, -0.2)],
}
## where the old models put the right hand (Weapons.GRIPS[id][0])
const OLD_RIGHT := {
	"pistol": Vector3(0, -0.07, 0.035),
	"rifle": Vector3(0, -0.08, 0.07),
	"shotgun": Vector3(0, -0.07, 0.11),
	"sniper": Vector3(0, -0.08, 0.1),
}


static func has_gun(id: String) -> bool:
	return GUN_GRIP.has(id) and has("gun_%s.res" % id)


## the bought gun as a Node3D pointing down -Z (same layout as Weapons.build_model)
static func gun(id: String) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = res("gun_%s.res" % id)
	mi.material_override = pbr("gun_" + id)
	# file: muzzle toward -X, up +Y. Turn it to point down -Z.
	mi.rotation.y = -PI * 0.5
	mi.position = OLD_RIGHT[id] - (GUN_GRIP[id][0] as Vector3)
	root.add_child(mi)
	return root


## where the left (support) hand goes on the bought gun, in the gun's own space
static func left_grip(id: String) -> Vector3:
	return (GUN_GRIP[id][1] as Vector3) + OLD_RIGHT[id] - (GUN_GRIP[id][0] as Vector3)


# ======================================================================= ammo box
static func ammo_box() -> Node3D:
	if not has("ammo_box.res"):
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = res("ammo_box.res")
	if not _cache.has("mat_ammo"):
		# the box came without its paint, so give it olive-drab military metal
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.29, 0.32, 0.2)
		m.roughness = 0.55
		m.metallic = 0.45
		_cache["mat_ammo"] = m
	mi.material_override = _cache["mat_ammo"]
	mi.scale = Vector3.ONE * 1.4
	var root := Node3D.new()
	root.add_child(mi)
	mi.position.y = -0.15
	return root


# ======================================================================= ruined buildings
const RUINS := ["ruin_building_01", "ruin_building_02", "ruin_building_03", "ruin_building_04",
	"ruin_building_05", "ruin_building_06", "ruin_building_07", "ruin_building_08",
	"ruin_building_09", "ruin_building_10", "ruin_building_11", "ruin_building_12"]
const PILES := ["ruin_pile_of_debris_01", "ruin_pile_of_debris_02"]


static func has_ruins() -> bool:
	return has(RUINS[0] + ".res")


static func ruin_mat(name: String) -> StandardMaterial3D:
	return pbr("bldg" if name.begins_with("bldg") else "ruin", true)


## a static ruined building (mesh + simplified collision) with its origin at the
## centre of its footprint, on the ground
static func ruin(name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = res(name + ".res")
	mi.material_override = ruin_mat(name)
	body.add_child(mi)
	var shape: Shape3D = res(name + "_col.res")
	if shape:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	return body


static func ruin_size(name: String) -> Vector3:
	var m: Mesh = res(name + ".res")
	return m.get_aabb().size if m else Vector3(15, 20, 12)


# ======================================================================= soldier
static func has_soldier() -> bool:
	return has("soldier.scn")
