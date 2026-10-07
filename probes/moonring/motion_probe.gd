extends SceneTree
## The moon ring and the rope grommet under motion, natively. DLSS and TAA are temporal, so the
## static moonring_probe.gd cannot judge them. The scene keeps that probe's frozen layout (seeded,
## paused, orbits at their start angles); this probe moves the camera itself, one step per frame
## along an arc around the demerzel planet, so every setting sees the same pose at the same frame.
## For each setting and style it holds the first pose HOLD frames, flies to the last capture, saving
## the CAPTURES poses in flight, then holds each of those poses HOLD frames and saves it again.
## In flight against held shows what motion costs each setting; analyze_motion.py scores both
## against the supersampled reference. Non-temporal settings must give the same image both ways.
## FSR2 at native scale is the control: a temporal upscaler fed the same motion vectors as DLSS.
## The reference also holds the TRAIL poses before the first capture, so analyze_motion.py can
## tell how many frames an in-flight image trails the camera.
##   godot --path . --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 \
##     --script res://probes/moonring/motion_probe.gd -- --out=<dir> [--dlss] [--no-glow] [--step=<deg>]
## Prints MOONMOTION {...} and writes it to <dir>/motion.json.

const SEED := 7
const CAPTURES := [60, 75, 90]  # frames flown when each in-flight capture is taken
const HOLD := 30             # frames a pose is held before a still capture
const TRAIL := 10            # poses before the first capture that the reference also holds
const DLSS_MODE := 6         # Viewport.SCALING_3D_MODE_DLSS in the fork

var _scene: Node
var _cam: Camera3D
var _nodes: Array = []
var _planet: Node3D
var _arc_start := 0.0
var _arc_radius := 0.0
var _arc_height := 0.8
var _step_deg := 0.5         # camera step per frame around the planet: 30 degrees a second at 60 fps


func _initialize() -> void:
	var out_dir := ""
	var dlss := false
	var glow := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--step="):
			_step_deg = arg.trim_prefix("--step=").to_float()
		elif arg == "--dlss":
			dlss = true
		elif arg == "--no-glow":
			glow = false
	if out_dir == "":
		printerr("motion_probe: --out=<dir> is required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(SEED)
	paused = true
	_scene = load("res://scenes/prime_radiant.tscn").instantiate()
	root.add_child(_scene)
	for i in 3:
		await process_frame
	var world_env := _scene.find_children("*", "WorldEnvironment", false, false)
	if not glow and not world_env.is_empty():
		(world_env[0] as WorldEnvironment).environment.glow_enabled = false
	_nodes = _scene.get("all_nodes")
	for n in _nodes:
		if n.orbit_radius > 0:
			n.position = Vector3(cos(n.orbit_angle) * n.orbit_radius, n.position.y, sin(n.orbit_angle) * n.orbit_radius)
	_cam = _scene.get("camera")
	_planet = _nodes.filter(func(n): return n.node_name == "demerzel")[0]
	# The arc starts at the static probe's close view, planet + (1.2, 0.8, 3.6).
	_arc_start = atan2(3.6, 1.2)
	_arc_radius = Vector2(1.2, 3.6).length()
	var rings: Array = _scene.get("moon_rings")
	var own_ring: MeshInstance3D = rings.filter(func(r): return r.get_parent() == _planet)[0]
	var vp := root.get_viewport()
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var sl: Object = Engine.get_singleton("Streamline") if Engine.has_singleton("Streamline") else null
	var has_dlss := sl != null and bool(sl.call("get_capability", 0))
	var out := {"godot": Engine.get_version_info().string, "seed": SEED,
		"renderer": RenderingServer.get_current_rendering_method(),
		"size": [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y],
		"adapter": RenderingServer.get_video_adapter_name(), "streamline": sl != null, "dlss": has_dlss,
		"glow": glow, "step_deg": _step_deg, "captures": CAPTURES, "hold": HOLD, "trail": TRAIL, "crop_centres": {}, "settings": {}}
	# Where an arc of demerzel's own ring sits on screen at each captured pose, for the crop sheet.
	for k: int in CAPTURES:
		_pose(k)
		out.crop_centres[str(k)] = _ring_point(own_ring)
	var settings := [
		{"name": "msaa2x", "msaa": Viewport.MSAA_2X, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": false},
		{"name": "noaa", "msaa": Viewport.MSAA_DISABLED, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": false},
		{"name": "taa", "msaa": Viewport.MSAA_DISABLED, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": true},
		{"name": "fsr2", "msaa": Viewport.MSAA_DISABLED, "mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 1.0, "taa": false},
		{"name": "ssaa2x_ref", "msaa": Viewport.MSAA_4X, "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 2.0, "taa": false},
	]
	if dlss and has_dlss:
		settings.append({"name": "dlaa", "msaa": Viewport.MSAA_DISABLED, "mode": DLSS_MODE, "scale": 1.0, "taa": false})
		settings.append({"name": "dlss_quality", "msaa": Viewport.MSAA_DISABLED, "mode": DLSS_MODE, "scale": 0.667, "taa": false})
		settings.append({"name": "dlss_performance", "msaa": Viewport.MSAA_DISABLED, "mode": DLSS_MODE, "scale": 0.5, "taa": false})
	elif dlss:
		out.dlss_skipped = "no Streamline singleton or no DLSS capability in this build"
	for s: Dictionary in settings:
		vp.use_taa = s.taa
		vp.msaa_3d = s.msaa
		vp.scaling_3d_mode = s.mode
		vp.scaling_3d_scale = s.scale
		var row := {"mode_kept": int(vp.scaling_3d_mode) == int(s.mode)}
		var evals_before := _evals(sl)
		var styles: Array = ["none", "ring", "grommet"] if s.name == "ssaa2x_ref" else ["ring", "grommet"]
		for style: String in styles:
			_scene.call("set_moon_ring_style", "ring" if style == "none" else style)
			for r in rings:
				r.visible = style != "none"
			var gpu: Array[float] = []
			for h in HOLD:
				_pose(0)
				await RenderingServer.frame_post_draw
			for k in range(1, CAPTURES[-1] + 1):
				_pose(k)
				await RenderingServer.frame_post_draw
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
				if k in CAPTURES:
					vp.get_texture().get_image().save_png(out_dir.path_join("%s-%s-fly-%d.png" % [s.name, style, k]))
			for k: int in CAPTURES:
				for h in HOLD:
					_pose(k)
					await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png(out_dir.path_join("%s-%s-hold-%d.png" % [s.name, style, k]))
			if s.name == "ssaa2x_ref" and style == "grommet":
				for j in range(1, TRAIL + 1):
					var k: int = CAPTURES[0] - j
					for h in HOLD:
						_pose(k)
						await RenderingServer.frame_post_draw
					vp.get_texture().get_image().save_png(out_dir.path_join("%s-%s-hold-%d.png" % [s.name, style, k]))
			row[style] = {"flight_frames": gpu.size(), "gpu_ms": _mean(gpu)}
		if sl != null:
			row.dlss_evaluations = _evals(sl) - evals_before
		out.settings[s.name] = row
	for r in rings:
		r.visible = true
	var json := JSON.stringify(out)
	var f := FileAccess.open(out_dir.path_join("motion.json"), FileAccess.WRITE)
	f.store_string(json)
	f.close()
	print("MOONMOTION ", json)
	quit(0)


## Camera pose k frames along the arc, and the scene's label rule (prime_radiant.gd _process),
## which the pause stops.
func _pose(k: int) -> void:
	var angle := _arc_start + deg_to_rad(_step_deg * k)
	var target := _planet.global_position
	_cam.look_at_from_position(target + Vector3(cos(angle) * _arc_radius, _arc_height, sin(angle) * _arc_radius), target, Vector3.UP)
	for n in _nodes:
		if n.label_3d:
			var dist: float = _cam.global_position.distance_to(n.global_position)
			n.label_3d.visible = dist < 25.0
			n.label_3d.pixel_size = 0.005 * clampf(dist * 0.1, 0.3, 1.5)


## The screen point of the ring's core circle that lies furthest up and right.
func _ring_point(ring: MeshInstance3D) -> Array:
	var core: float = ring.get_meta("inner_radius") + 0.015
	var best := Vector2(-INF, INF)
	for i in 72:
		var a := TAU * i / 72.0
		var p := _cam.unproject_position(ring.global_transform * Vector3(cos(a) * core, 0.0, sin(a) * core))
		if p.x - p.y > best.x - best.y:
			best = p
	return [roundi(best.x), roundi(best.y)]


func _evals(sl: Object) -> int:
	if sl == null:
		return 0
	var st: Dictionary = sl.call("get_status")
	return int(st.get("dlss_evaluations", 0))


func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var total := 0.0
	for v in a:
		total += v
	return snappedf(total / a.size(), 0.001)
