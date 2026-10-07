extends SceneTree
## Moon ring vs rope grommet in the Prime Radiant, natively. The scene is seeded, run a few frames,
## then paused and every orbit reset to its starting angle, so all captures in one run share one
## frozen layout. For two views (the scene's own orbit camera at t = 0, and a close view of the
## demerzel planet), each anti-aliasing setting renders three styles: rings hidden ("none"), the
## thin ring and the grommet. Each row has the GPU render time of the viewport and the frame time
## (mean, 95th percentile), primitives drawn, and a screenshot; analyze.py turns the screenshots into
## footprints and errors. With --dlss on NVIDIA's fork, DLAA, DLSS Quality and Performance are added,
## with the Streamline evaluation counter before and after each, which proves DLSS ran.
##   godot --path . --rendering-method forward_plus --resolution 1920x1080 \
##     --script res://probes/moonring/moonring_probe.gd -- --out=<dir> [--dlss] [--no-glow]
## Prints MOONRING {...} and writes it to <dir>/moonring.json.

const SEED := 7
const SETTLE := 1.0   # s per setting before measuring (DLSS's history fills)
const MEASURE := 2.0  # s measured per style
const DLSS_MODE := 6  # Viewport.SCALING_3D_MODE_DLSS in the fork

var _out := ""


func _initialize() -> void:
	var dlss := false
	var glow := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--dlss":
			dlss = true
		elif arg == "--no-glow":
			glow = false
	if _out == "":
		printerr("moonring_probe: --out=<dir> is required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(SEED)
	# Paused before the first frame: _ready builds the graph, but no _process ever moves an orbit,
	# pulses a tide or swings the camera. Orbits are placed here from their seeded start angles.
	paused = true
	var scene: Node = load("res://scenes/prime_radiant.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	# Glow's blur radius is counted in internal pixels, so it widens at DLSS's lower internal
	# resolution and narrows in the supersampled reference. --no-glow isolates the geometry.
	var world_env := scene.find_children("*", "WorldEnvironment", false, false)
	if not glow and not world_env.is_empty():
		(world_env[0] as WorldEnvironment).environment.glow_enabled = false
	var nodes: Array = scene.get("all_nodes")
	for n in nodes:
		if n.orbit_radius > 0:
			n.position = Vector3(cos(n.orbit_angle) * n.orbit_radius, n.position.y, sin(n.orbit_angle) * n.orbit_radius)
	var cam: Camera3D = scene.get("camera")
	var planet: Node3D = nodes.filter(func(n): return n.node_name == "demerzel")[0]
	var views := {
		"overview": [Vector3(40.0, 18.0, 0.0), Vector3.ZERO],
		"close": [planet.global_position + Vector3(1.2, 0.8, 3.6), planet.global_position],
	}
	var vp := root.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var sl: Object = Engine.get_singleton("Streamline") if Engine.has_singleton("Streamline") else null
	var has_dlss := sl != null and bool(sl.call("get_capability", 0))
	var rings: Array = scene.get("moon_rings")
	var grommet_tris := 0
	scene.call("set_moon_ring_style", "grommet")
	grommet_tris = (rings[0].mesh as ArrayMesh).surface_get_array_index_len(0) / 3
	scene.call("set_moon_ring_style", "ring")
	var out := {"godot": Engine.get_version_info().string, "seed": SEED,
		"renderer": RenderingServer.get_current_rendering_method(),
		"size": [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y],
		"adapter": RenderingServer.get_video_adapter_name(), "streamline": sl != null, "dlss": has_dlss,
		"rings": rings.size(), "grommet_triangles_per_ring": grommet_tris, "glow": glow, "views": {}}
	var settings := [
		{"name": "msaa2x", "msaa": Viewport.MSAA_2X, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0},
		{"name": "noaa", "msaa": Viewport.MSAA_DISABLED, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0},
		{"name": "ssaa2x_ref", "msaa": Viewport.MSAA_4X, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 2.0},
	]
	if dlss and has_dlss:
		settings.append({"name": "dlaa", "msaa": Viewport.MSAA_DISABLED, "mode": DLSS_MODE, "scale": 1.0})
		settings.append({"name": "dlss_quality", "msaa": Viewport.MSAA_DISABLED, "mode": DLSS_MODE, "scale": 0.667})
		settings.append({"name": "dlss_performance", "msaa": Viewport.MSAA_DISABLED, "mode": DLSS_MODE, "scale": 0.5})
	elif dlss:
		out.dlss_skipped = "no Streamline singleton or no DLSS capability in this build"
	for view: String in views:
		cam.look_at_from_position(views[view][0], views[view][1], Vector3.UP)
		# The scene's own label rule (prime_radiant.gd _process), which the pause stops.
		for n in nodes:
			if n.label_3d:
				var dist: float = cam.global_position.distance_to(n.global_position)
				n.label_3d.visible = dist < 25.0
				n.label_3d.pixel_size = 0.005 * clampf(dist * 0.1, 0.3, 1.5)
		var rows := {}
		for s: Dictionary in settings:
			vp.use_taa = false
			vp.msaa_3d = s.msaa
			vp.scaling_3d_mode = s.mode
			vp.scaling_3d_scale = s.scale
			var row := {"mode_kept": int(vp.scaling_3d_mode) == int(s.mode)}
			var evals_before := _evals(sl)
			for style in ["none", "ring", "grommet"]:
				scene.call("set_moon_ring_style", "ring" if style == "none" else style)
				for r in rings:
					r.visible = style != "none"
				await _wait(SETTLE)
				row[style] = await _measure(vp)
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png(_out.path_join("%s-%s-%s.png" % [view, s.name, style]))
			if sl != null:
				row.dlss_evaluations = _evals(sl) - evals_before
			rows[s.name] = row
		out.views[view] = rows
	for r in rings:
		r.visible = true
	var json := JSON.stringify(out)
	var f := FileAccess.open(_out.path_join("moonring.json"), FileAccess.WRITE)
	f.store_string(json)
	f.close()
	print("MOONRING ", json)
	quit(0)


func _evals(sl: Object) -> int:
	if sl == null:
		return 0
	var st: Dictionary = sl.call("get_status")
	return int(st.get("dlss_evaluations", 0))


## Mean and 95th percentile of the frame time and of the GPU's render time of the viewport (ms),
## and the primitives drawn in the last frame.
func _measure(vp: Viewport) -> Dictionary:
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < int(MEASURE * 1e6):
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	return {"frames": frames.size(), "frame_ms": _stats(frames), "gpu_ms": _stats(gpu), "primitives": prims}


func _stats(a: Array[float]) -> Array:
	if a.is_empty():
		return [0.0, 0.0]
	var s := a.duplicate()
	s.sort()
	var mean := 0.0
	for v in s:
		mean += v
	return [snappedf(mean / s.size(), 0.001), snappedf(s[int(0.95 * (s.size() - 1))], 0.001)]


func _wait(seconds: float) -> void:
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < int(seconds * 1e6):
		await process_frame
