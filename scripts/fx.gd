class_name FX
extends RefCounted
## Small visual effects shared by everything: explosions, dust clouds,
## muzzle flashes, bullet tracers, sparks and lightning bolts.

static var _soft: GradientTexture2D


static func soft_texture() -> GradientTexture2D:
	if _soft:
		return _soft
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	_soft = GradientTexture2D.new()
	_soft.gradient = g
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(0.5, 0.0)
	_soft.width = 64
	_soft.height = 64
	return _soft


static func _particles(parent: Node, at: Vector3, color: Color, amount: int, size: float, speed: float, life: float, gravity: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.spread = 180.0
	p.direction = Vector3.UP
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = soft_texture()
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


static func explosion(parent: Node, at: Vector3, radius: float) -> void:
	_particles(parent, at, Color(1.0, 0.75, 0.3, 1.0), 26, radius * 0.9, radius * 3.0, 0.5, 2.0, true)
	_particles(parent, at, Color(0.25, 0.22, 0.2, 0.85), 18, radius * 1.1, radius * 1.6, 1.4, 1.5, false)
	flash(parent, at, Color(1.0, 0.7, 0.3), radius * 3.0, 0.25)


static func dust(parent: Node, at: Vector3, radius: float, life: float = 2.0) -> void:
	_particles(parent, at, Color(0.62, 0.58, 0.52, 0.8), 40, radius * 0.6, radius * 0.9, life, -0.5, false)


static func sparks(parent: Node, at: Vector3, color: Color = Color(1.0, 0.85, 0.4)) -> void:
	_particles(parent, at, color, 8, 0.12, 5.0, 0.25, -12.0, true)


static func blood(parent: Node, at: Vector3) -> void:
	_particles(parent, at, Color(0.75, 0.1, 0.08, 1.0), 8, 0.18, 3.0, 0.35, -14.0, false)


static func flash(parent: Node, at: Vector3, color: Color, rng: float, life: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 6.0
	l.omni_range = rng
	parent.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, life)
	tw.tween_callback(l.queue_free)


## a bright streak from a to b that fades fast
static func tracer(parent: Node, a: Vector3, b: Vector3, color: Color = Color(1.0, 0.9, 0.55), width: float = 0.05) -> void:
	var dist := a.distance_to(b)
	if dist < 0.1:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, dist)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	bm.material = m
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.global_position = (a + b) * 0.5
	if absf((b - a).normalized().dot(Vector3.UP)) < 0.99:
		mi.look_at(b, Vector3.UP)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mi.queue_free)


## jagged lightning bolt from the sky down to a point
static func lightning(parent: Node, from: Vector3, to: Vector3) -> void:
	var pts: Array[Vector3] = [from]
	var steps := 9
	for i in range(1, steps):
		var t := float(i) / steps
		var p := from.lerp(to, t) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)) * (1.0 - absf(t - 0.5))
		pts.append(p)
	pts.append(to)
	for i in pts.size() - 1:
		tracer(parent, pts[i], pts[i + 1], Color(0.75, 0.85, 1.0), 0.35)
		tracer(parent, pts[i], pts[i + 1], Color(1, 1, 1), 0.12)
	flash(parent, to + Vector3(0, 2, 0), Color(0.7, 0.8, 1.0), 40.0, 0.35)
	_particles(parent, to, Color(0.7, 0.85, 1.0, 1.0), 20, 0.3, 8.0, 0.4, -6.0, true)
