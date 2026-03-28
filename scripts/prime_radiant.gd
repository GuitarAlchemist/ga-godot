## PrimeRadiant — Fractal Governance Engine
## The solar system IS the governance hierarchy.
## Planets = repos, moons = services, rings = coordination layers.
extends Node3D

## Repo definitions — each becomes a planet
const REPOS = [
	{ "name": "demerzel", "color": Color(1.0, 0.84, 0.0), "radius": 3.0, "distance": 5.0,
	  "type": "constitution", "belief": GovernanceNode.BeliefState.TRUE,
	  "children": [
		{ "name": "asimov-constitution", "type": "constitution", "belief": GovernanceNode.BeliefState.TRUE },
		{ "name": "alignment-policy", "type": "policy", "belief": GovernanceNode.BeliefState.TRUE },
		{ "name": "algedonic-channel", "type": "policy", "belief": GovernanceNode.BeliefState.TRUE },
		{ "name": "streeling-university", "type": "department", "belief": GovernanceNode.BeliefState.PROBABLE,
		  "children": [
			{ "name": "music-dept", "type": "department", "belief": GovernanceNode.BeliefState.PROBABLE },
			{ "name": "math-dept", "type": "department", "belief": GovernanceNode.BeliefState.UNKNOWN },
			{ "name": "cs-dept", "type": "department", "belief": GovernanceNode.BeliefState.TRUE },
		  ]},
		{ "name": "demerzel-persona", "type": "persona", "belief": GovernanceNode.BeliefState.TRUE },
		{ "name": "seldon-persona", "type": "persona", "belief": GovernanceNode.BeliefState.PROBABLE },
	  ]},
	{ "name": "ix", "color": Color(0.45, 0.82, 0.24), "radius": 2.0, "distance": 10.0,
	  "type": "policy", "belief": GovernanceNode.BeliefState.TRUE,
	  "children": [
		{ "name": "ixql-grammar", "type": "schema", "belief": GovernanceNode.BeliefState.TRUE },
		{ "name": "ml-pipeline", "type": "policy", "belief": GovernanceNode.BeliefState.PROBABLE },
		{ "name": "skill-loader", "type": "schema", "belief": GovernanceNode.BeliefState.CONTRADICTORY },
	  ]},
	{ "name": "tars", "color": Color(0.31, 0.76, 0.97), "radius": 1.8, "distance": 16.0,
	  "type": "policy", "belief": GovernanceNode.BeliefState.PROBABLE,
	  "children": [
		{ "name": "reasoning-engine", "type": "policy", "belief": GovernanceNode.BeliefState.PROBABLE },
		{ "name": "belief-state", "type": "schema", "belief": GovernanceNode.BeliefState.UNKNOWN },
		{ "name": "conscience-module", "type": "policy", "belief": GovernanceNode.BeliefState.DOUBTFUL },
	  ]},
	{ "name": "ga", "color": Color(1.0, 0.7, 0.25), "radius": 2.2, "distance": 22.0,
	  "type": "policy", "belief": GovernanceNode.BeliefState.TRUE,
	  "children": [
		{ "name": "chatbot", "type": "policy", "belief": GovernanceNode.BeliefState.TRUE },
		{ "name": "prime-radiant-ui", "type": "schema", "belief": GovernanceNode.BeliefState.PROBABLE },
		{ "name": "music-theory", "type": "department", "belief": GovernanceNode.BeliefState.TRUE,
		  "children": [
			{ "name": "chord-analysis", "type": "course", "belief": GovernanceNode.BeliefState.TRUE },
			{ "name": "scale-explorer", "type": "course", "belief": GovernanceNode.BeliefState.PROBABLE },
			{ "name": "fretboard-viz", "type": "course", "belief": GovernanceNode.BeliefState.UNKNOWN },
		  ]},
	  ]},
]

var camera: Camera3D
var sun_light: OmniLight3D
var all_nodes: Array[GovernanceNode] = []
var time: float = 0.0
var cloud_layers: Array[MeshInstance3D] = []
var cloud_time: float = 0.0


func _ready() -> void:
	_setup_environment()
	_setup_camera()
	_setup_sun()
	_build_governance_graph()
	_add_cloud_layers()
	_start_demo_signals()
	_setup_web_bridge()


func _process(delta: float) -> void:
	time += delta
	_poll_web_messages()
	_update_cloud_layers(delta)

	# Rotate camera slowly around the system
	if camera:
		var cam_dist = 40.0
		var cam_height = 18.0
		var cam_speed = 0.05
		camera.position = Vector3(
			cos(time * cam_speed) * cam_dist,
			cam_height + sin(time * cam_speed * 0.3) * 3.0,
			sin(time * cam_speed) * cam_dist
		)
		camera.look_at(Vector3.ZERO)

	# Update LOD — show labels when camera is close
	if camera:
		for node in all_nodes:
			var dist = camera.global_position.distance_to(node.global_position)
			if node.label_3d:
				node.label_3d.visible = dist < 25.0
				# Scale label by distance for readability
				var label_scale = clamp(dist * 0.1, 0.3, 1.5)
				node.label_3d.pixel_size = 0.005 * label_scale


func _setup_environment() -> void:
	# World environment — space
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.01, 0.03)
	environment.ambient_light_color = Color(0.05, 0.05, 0.1)
	environment.ambient_light_energy = 0.3
	# Tonemap set via project settings instead
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.3
	environment.glow_strength = 1.0
	environment.glow_hdr_threshold = 1.2
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.ssr_enabled = false
	environment.fog_enabled = false
	env.environment = environment
	add_child(env)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0, 15, 30)
	camera.look_at(Vector3.ZERO)
	camera.fov = 60
	camera.far = 500
	add_child(camera)


func _setup_sun() -> void:
	# Central sun — represents the Asimov constitution (source of all governance light)
	sun_light = OmniLight3D.new()
	sun_light.light_color = Color(1.0, 0.95, 0.8)
	sun_light.light_energy = 5.0
	sun_light.omni_range = 100.0
	sun_light.shadow_enabled = false  # shadows expensive on web/WASM
	add_child(sun_light)

	# Sun visual — glowing sphere
	var sun_mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.5
	sphere.height = 3.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sun_mesh.mesh = sphere
	var sun_mat = StandardMaterial3D.new()
	sun_mat.albedo_color = Color(1.0, 0.9, 0.5)
	sun_mat.emission_enabled = true
	sun_mat.emission = Color(1.0, 0.85, 0.4)
	sun_mat.emission_energy_multiplier = 8.0
	sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sun_mesh.material_override = sun_mat
	add_child(sun_mesh)


func _build_governance_graph() -> void:
	for repo_def in REPOS:
		var planet = _create_governance_node(repo_def, null)
		planet.orbit_radius = repo_def.get("distance", 0.0)
		planet.orbit_speed = 0.3 / max(planet.orbit_radius, 1.0)  # Kepler-ish
		planet.orbit_angle = randf() * TAU
		add_child(planet)

		# Create orbit trail
		if planet.orbit_radius > 0:
			_create_orbit_trail(planet.orbit_radius, repo_def.get("color", Color.WHITE))


func _create_governance_node(def: Dictionary, parent: GovernanceNode) -> GovernanceNode:
	var node = GovernanceNode.new()
	node.node_name = def.get("name", "unnamed")
	node.node_type = def.get("type", "policy")
	node.repo = def.get("name", "unknown") if parent == null else parent.repo
	node.base_color = def.get("color", Color(0.5, 0.5, 0.8))
	node.set_belief(def.get("belief", GovernanceNode.BeliefState.UNKNOWN))

	# Set VSM role based on type
	match node.node_type:
		"constitution": node.vsm_role = GovernanceNode.VSMRole.S5_IDENTITY
		"department": node.vsm_role = GovernanceNode.VSMRole.S4_INTELLIGENCE
		"policy": node.vsm_role = GovernanceNode.VSMRole.S3_CONTROL
		"persona": node.vsm_role = GovernanceNode.VSMRole.S2_COORDINATION
		_: node.vsm_role = GovernanceNode.VSMRole.S1_OPERATIONS

	all_nodes.append(node)

	# Connect algedonic signals for monitoring
	node.algedonic_pain.connect(_on_algedonic_pain)
	node.algedonic_pleasure.connect(_on_algedonic_pleasure)
	node.belief_changed.connect(_on_belief_changed)
	node.node_clicked.connect(_on_node_clicked)

	# Build children recursively — fractal structure (children = moons)
	if def.has("children"):
		var child_index = 0
		for child_def in def["children"]:
			var child = _create_governance_node(child_def, node)
			# Position children in orbit around parent (moon orbit)
			child.orbit_radius = 2.5 + child_index * 1.2
			child.orbit_speed = 0.5 + randf() * 0.3
			child.orbit_angle = child_index * TAU / def["children"].size()
			node.add_child_governance(child)
			child_index += 1
		# Add visual moon ring indicator
		_add_moon_ring(node, child_index)

	return node


func _create_orbit_trail(radius: float, color: Color) -> void:
	var points = PackedVector3Array()
	var segments = 64
	for i in range(segments + 1):
		var angle = float(i) / segments * TAU
		points.append(Vector3(cos(angle) * radius, 0, sin(angle) * radius))

	var mesh = MeshInstance3D.new()
	var imm = ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		imm.surface_set_color(Color(color, 0.15))
		imm.surface_add_vertex(p)
	imm.surface_end()
	mesh.mesh = imm

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mesh.material_override = mat
	add_child(mesh)


# ---------------------------------------------------------------------------
# Moon layers — services/policies orbit their parent planet as small moons
# Already handled by child governance nodes in fractal structure.
# This adds a visual ring indicator for planets with many children.
# ---------------------------------------------------------------------------

func _add_moon_ring(parent: GovernanceNode, child_count: int) -> void:
	if child_count < 2:
		return
	# Faint ring around planets that have moons (children)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = parent.orbit_radius * 0.08 if parent.orbit_radius > 0 else 1.5
	torus.outer_radius = torus.inner_radius + 0.03
	torus.rings = 12
	torus.ring_segments = 32
	ring.mesh = torus
	ring.rotation.x = PI * 0.5  # flat horizontal ring

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(parent.base_color, 0.2)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	ring.material_override = mat
	parent.add_child(ring)


# ---------------------------------------------------------------------------
# Cloud layers — animated translucent shells around the governance system
# Inspired by NASA GIBS live satellite clouds from the React version.
# Two layers at different altitudes for depth parallax.
# ---------------------------------------------------------------------------

func _add_cloud_layers() -> void:
	# Layer 1: Low-altitude governance "weather" — faster rotation
	var cloud1 = _create_cloud_shell(35.0, 0.06, Color(0.4, 0.5, 0.9, 0.08), 0.02)
	cloud_layers.append(cloud1)
	add_child(cloud1)

	# Layer 2: High-altitude thin haze — slower, opposite rotation
	var cloud2 = _create_cloud_shell(38.0, 0.04, Color(0.6, 0.7, 1.0, 0.05), -0.01)
	cloud_layers.append(cloud2)
	add_child(cloud2)


func _create_cloud_shell(radius: float, thickness: float, color: Color, _rot_speed: float) -> MeshInstance3D:
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.is_hemisphere = false
	mesh_inst.mesh = sphere

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_FRONT  # render inside face for enveloping effect
	mat.no_depth_test = true
	# Noise-like variation via vertex color modulation
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b) * 0.3
	mat.emission_energy_multiplier = 0.5
	mesh_inst.material_override = mat

	# Store rotation speed in metadata
	mesh_inst.set_meta("rot_speed", _rot_speed)
	mesh_inst.set_meta("base_alpha", color.a)
	return mesh_inst


func _update_cloud_layers(delta: float) -> void:
	cloud_time += delta
	for cloud in cloud_layers:
		var speed: float = cloud.get_meta("rot_speed", 0.01)
		cloud.rotation.y += speed * delta
		# Gentle breathing — alpha oscillation
		var base_alpha: float = cloud.get_meta("base_alpha", 0.05)
		var mat = cloud.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = base_alpha + sin(cloud_time * 0.3 + cloud.rotation.y) * base_alpha * 0.4


func _on_algedonic_pain(source: GovernanceNode, severity: float, description: String) -> void:
	print("[ALGEDONIC PAIN] %s (%.2f): %s" % [source.node_name, severity, description])
	# Visual: create ripple effect
	_create_ripple(source.global_position, Color(1, 0.2, 0.2), severity)


func _on_algedonic_pleasure(source: GovernanceNode, magnitude: float, description: String) -> void:
	print("[ALGEDONIC PLEASURE] %s (%.2f): %s" % [source.node_name, magnitude, description])
	_create_ripple(source.global_position, Color(0.2, 1, 0.3), magnitude)


func _on_belief_changed(node: GovernanceNode, old_state: GovernanceNode.BeliefState, new_state: GovernanceNode.BeliefState) -> void:
	var state_names = ["TRUE", "PROBABLE", "UNKNOWN", "DOUBTFUL", "FALSE", "CONTRADICTORY"]
	print("[BELIEF] %s: %s → %s" % [node.node_name, state_names[old_state], state_names[new_state]])


func _on_node_clicked(node: GovernanceNode) -> void:
	print("[CLICK] Node clicked: %s" % node.node_name)
	_post_to_react({
		"type": "godot:node-clicked",
		"nodeId": node.node_name,
		"nodeType": node.node_type,
		"repo": node.repo,
	})


func _create_ripple(pos: Vector3, color: Color, intensity: float) -> void:
	# Expanding ring ripple
	var ripple = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.01
	torus.outer_radius = 0.1
	torus.rings = 16
	torus.ring_segments = 24
	ripple.mesh = torus
	ripple.position = pos

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0 * intensity
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	ripple.material_override = mat
	add_child(ripple)

	# Animate expansion then fade
	var tween = create_tween()
	tween.tween_property(ripple, "scale", Vector3.ONE * 20.0 * intensity, 2.0).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 2.0)
	tween.tween_callback(ripple.queue_free)


func _start_demo_signals() -> void:
	# Demo: fire some governance events after a delay
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = false
	timer.timeout.connect(_fire_demo_signal)
	add_child(timer)
	timer.start()


var _demo_step = 0
func _fire_demo_signal() -> void:
	if all_nodes.is_empty():
		return

	match _demo_step % 6:
		0:
			# Schema drift in ix
			var target = _find_node("skill-loader")
			if target:
				target.set_belief(GovernanceNode.BeliefState.CONTRADICTORY, 0.4)
		1:
			# Belief collapse in tars
			var target = _find_node("conscience-module")
			if target:
				target.emit_pain(0.6, "Belief confidence dropped below 0.3")
		2:
			# Knowledge harvest pleasure
			var target = _find_node("music-dept")
			if target:
				target.emit_pleasure(0.8, "14 new course modules harvested")
				target.set_belief(GovernanceNode.BeliefState.TRUE, 0.92)
		3:
			# Policy convergence
			var target = _find_node("alignment-policy")
			if target:
				target.emit_pleasure(0.9, "Cross-model validation achieved 95% consensus")
		4:
			# Schema drift resolution
			var target = _find_node("skill-loader")
			if target:
				target.set_belief(GovernanceNode.BeliefState.PROBABLE, 0.7)
				target.emit_pleasure(0.5, "Contradiction resolved via adapter pattern")
		5:
			# Belief crystallization
			var target = _find_node("belief-state")
			if target:
				target.set_belief(GovernanceNode.BeliefState.TRUE, 0.95)
				target.emit_pleasure(0.7, "Belief crystallized U→T at 0.95")

	_demo_step += 1


func _find_node(query: String) -> GovernanceNode:
	for n in all_nodes:
		if n.node_name == query:
			return n
	return null


# ---------------------------------------------------------------------------
# PostMessage bridge — React <-> Godot communication (HTML5 export only)
# ---------------------------------------------------------------------------

func _setup_web_bridge() -> void:
	if not OS.has_feature("web"):
		return
	# Notify React parent that Godot is ready
	JavaScriptBridge.eval("""
		window.parent.postMessage({ type: 'godot:ready' }, '*');
		window.addEventListener('message', function(ev) {
			if (ev.data && ev.data.type && ev.data.type.startsWith('governance:')) {
				// Store inbound messages for Godot to poll
				window.__godotInbound = window.__godotInbound || [];
				window.__godotInbound.push(ev.data);
			}
		});
	""")


func _poll_web_messages() -> void:
	if not OS.has_feature("web"):
		return
	var raw = JavaScriptBridge.eval("""
		(function() {
			var q = window.__godotInbound || [];
			window.__godotInbound = [];
			return JSON.stringify(q);
		})()
	""")
	if raw == null or raw == "[]":
		return
	var msgs = JSON.parse_string(raw)
	if msgs is Array:
		for msg in msgs:
			_handle_web_message(msg)


func _handle_web_message(msg: Dictionary) -> void:
	var msg_type = msg.get("type", "")
	match msg_type:
		"governance:select":
			var node_id = msg.get("nodeId", "")
			var target = _find_node(node_id)
			if target:
				# Fly camera to selected node
				camera.look_at(target.global_position)
		"governance:pin":
			# Show 3D popup pin on a node (IXQL pipeline events)
			var node_id = msg.get("nodeId", "")
			var text = msg.get("text", "")
			var color_arr = msg.get("color", [1, 0.3, 0.3])
			var target = _find_node(node_id)
			if target:
				var color = Color(color_arr[0], color_arr[1], color_arr[2]) if color_arr.size() >= 3 else Color(1, 0.3, 0.3)
				target.show_pin(text, color)
		"governance:belief":
			var node_id = msg.get("nodeId", "")
			var state_str = msg.get("state", "UNKNOWN")
			var conf = msg.get("confidence", 0.5)
			var target = _find_node(node_id)
			if target:
				var belief = GovernanceNode.BeliefState.UNKNOWN
				match state_str:
					"TRUE": belief = GovernanceNode.BeliefState.TRUE
					"FALSE": belief = GovernanceNode.BeliefState.FALSE
					"PROBABLE": belief = GovernanceNode.BeliefState.PROBABLE
					"DOUBTFUL": belief = GovernanceNode.BeliefState.DOUBTFUL
					"CONTRADICTORY": belief = GovernanceNode.BeliefState.CONTRADICTORY
				target.set_belief(belief, conf)
		"governance:algedonic":
			var signal_data = msg.get("signal", {})
			# Trigger algedonic effect on relevant node
			if signal_data.has("nodeId"):
				var target = _find_node(signal_data["nodeId"])
				if target:
					if signal_data.get("severity", 0.5) > 0.5:
						target.emit_pain(signal_data.get("severity", 0.7), signal_data.get("description", ""))
					else:
						target.emit_pleasure(signal_data.get("magnitude", 0.5), signal_data.get("description", ""))


func _post_to_react(msg: Dictionary) -> void:
	if not OS.has_feature("web"):
		return
	var json = JSON.stringify(msg)
	JavaScriptBridge.eval("window.parent.postMessage(%s, '*');" % json)
