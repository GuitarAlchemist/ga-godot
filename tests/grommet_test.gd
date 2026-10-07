extends SceneTree
## Headless checks for the rope grommet and the governance:render bridge message.
##   godot --headless --path . --script res://tests/grommet_test.gd     (exit 0 = pass)

const GrommetMesh = preload("res://scripts/grommet_mesh.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_check_rules()
	_check_mesh()
	await _check_scene()
	if _failures.is_empty():
		print("grommet test passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append("FAIL: " + what)


func _check_rules() -> void:
	_expect(GrommetMesh.check(1.515, 0.05, 0.038, 3, 41).is_empty(), "the scene's grommet (3, 41) can be laid")
	_expect(GrommetMesh.check(1.515, 0.05, 0.038, 3, 42).begins_with("grommet: gcd(3, 42) = 3"), "(3, 42) closes as 3 loops and is refused")
	_expect(GrommetMesh.check(1.515, 0.05, 0.045, 3, 41).begins_with("grommet: strands overlap"), "a strand too thick for its lay is refused")
	_expect(not GrommetMesh.check(1.515, 0.05, 0.038, 1, 41).is_empty(), "p = 1 is refused")
	_expect(GrommetMesh.build(1.515, 0.05, 0.045) == null, "build refuses what check refuses")


func _check_mesh() -> void:
	var samples := 656
	var sides := 8
	var mesh := GrommetMesh.build(1.515, 0.05, 0.038, 3, 41, samples, sides)
	_expect(mesh != null, "build returns a mesh")
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_expect(verts.size() == samples * sides, "vertex count %d" % verts.size())
	_expect(indices.size() == samples * sides * 6, "index count %d" % indices.size())
	# Godot's front faces are clockwise seen from outside: (B - A) x (C - A) points inward.
	var outward := 0
	for k in range(0, indices.size(), 3):
		var a := verts[indices[k]]
		var face := (verts[indices[k + 1]] - a).cross(verts[indices[k + 2]] - a)
		if face.dot(normals[indices[k]]) >= 0.0:
			outward += 1
	_expect(outward == 0, "%d triangles wound counter-clockwise from outside" % outward)
	# The strand stays within the lay: every vertex lies between R - a - s and R + a + s from the axis.
	var worst := 0.0
	for v in verts:
		worst = maxf(worst, absf(Vector2(v.x, v.z).length() - 1.515))
	_expect(worst <= 0.05 + 0.038 + 1e-4, "radial extent %.4f" % worst)


func _check_scene() -> void:
	var scene: Node = load("res://scenes/prime_radiant.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var rings: Array = scene.get("moon_rings")
	_expect(rings.size() == 6, "6 moon rings, got %d" % rings.size())
	_expect(scene.get("moon_ring_style") == "ring", "starts as the thin ring")
	_expect(rings.all(func(r): return r.mesh is TorusMesh), "baseline rings are TorusMesh")
	scene.call("_handle_web_message", {"type": "governance:render", "target": "grommet", "action": "on"})
	_expect(scene.get("moon_ring_style") == "grommet", "RENDER GROMMET ON switches to the grommet")
	_expect(rings.all(func(r): return r.mesh is ArrayMesh and r.mesh == rings[0].mesh), "every ring shares one grommet mesh")
	_expect(rings.all(func(r): return r.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED), "grommet is opaque")
	scene.call("_handle_web_message", {"type": "governance:render", "target": "grommet", "action": "toggle"})
	_expect(scene.get("moon_ring_style") == "ring", "TOGGLE goes back to the ring")
	scene.call("_handle_web_message", {"type": "governance:render", "target": "bloom", "action": "on"})
	_expect(scene.get("moon_ring_style") == "ring", "another target leaves the rings alone")
	scene.call("_handle_web_message", {"type": "governance:render", "target": "grommet", "action": "toggle"})
	_expect(scene.get("moon_ring_style") == "grommet", "TOGGLE from the ring gives the grommet")
	scene.call("_handle_web_message", {"type": "governance:render", "target": "grommet", "action": "bogus"})
	_expect(scene.get("moon_ring_style") == "grommet", "an unknown action leaves the grommet alone")
	scene.call("_handle_web_message", {"type": "governance:render", "target": "grommet", "action": "off"})
	_expect(rings.all(func(r): return r.mesh is TorusMesh), "OFF restores the TorusMesh")
	scene.queue_free()
	await process_frame
