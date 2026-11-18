extends SceneTree
## Headless project check used by GitHub Actions (and usable locally).
##
## Loads every script, shader, scene and resource in the project.
## Scripts must compile; scenes must load and instantiate.
## Godot prints the exact file:line of any parse error just above our report.
##
## Run:  godot --headless --path . --script res://tools/ci_verify.gd
## Exit code 0 = everything loaded, 1 = at least one failure.

const CHECKED_EXTENSIONS := ["gd", "gdshader", "tscn", "tres"]

var _failures: PackedStringArray = []
var _checked: int = 0


func _initialize() -> void:
	var files: PackedStringArray = []
	_collect("res://", files)
	print("CI_VERIFY: checking %d files" % files.size())
	for path in files:
		_check(path)
	if _failures.is_empty():
		print("CI_VERIFY: PASS (%d files loaded)" % _checked)
		quit(0)
	else:
		for failure in _failures:
			printerr("CI_FAIL: " + failure)
		print("CI_VERIFY: FAIL (%d problems)" % _failures.size())
		quit(1)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir_path):
		if sub.begins_with(".") or sub == "build":
			continue
		_collect(dir_path.path_join(sub), out)
	for file_name in DirAccess.get_files_at(dir_path):
		if file_name.get_extension() in CHECKED_EXTENSIONS:
			out.append(dir_path.path_join(file_name))


func _check(path: String) -> void:
	_checked += 1
	var res: Resource = ResourceLoader.load(path)
	if res == null:
		_failures.append("%s: could not be loaded (see the ERROR lines above it in this log)" % path)
		return
	if res is GDScript:
		var script := res as GDScript
		if not script.can_instantiate():
			_failures.append("%s: script does not compile (see 'Parse Error' lines with line numbers above)" % path)
			return
	elif res is PackedScene:
		var scene := res as PackedScene
		var instance := scene.instantiate()
		if instance == null:
			_failures.append("%s: scene loaded but could not be instantiated" % path)
			return
		instance.free()
	print("CI_VERIFY: ok   " + path)
