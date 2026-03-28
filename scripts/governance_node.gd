## GovernanceNode — Fractal VSM cell
## Each node is a mini Viable System Model with S1-S5 layers.
## Emits algedonic signals upward, absorbs pain locally first.
class_name GovernanceNode
extends Node3D

## Hexavalent belief state
enum BeliefState { TRUE, PROBABLE, UNKNOWN, DOUBTFUL, FALSE, CONTRADICTORY }

## VSM role of this node
enum VSMRole { S1_OPERATIONS, S2_COORDINATION, S3_CONTROL, S4_INTELLIGENCE, S5_IDENTITY }

## Algedonic signal
signal algedonic_pain(source: GovernanceNode, severity: float, description: String)
signal algedonic_pleasure(source: GovernanceNode, magnitude: float, description: String)
signal belief_changed(node: GovernanceNode, old_state: BeliefState, new_state: BeliefState)
signal node_clicked(node: GovernanceNode)

@export var node_name: String = "unnamed"
@export var node_type: String = "policy"  # constitution, policy, persona, schema, test, department, course
@export var repo: String = "demerzel"     # demerzel, ix, tars, ga
@export var vsm_role: VSMRole = VSMRole.S1_OPERATIONS

## Governance state
var belief_state: BeliefState = BeliefState.UNKNOWN
var confidence: float = 0.5
var immune_memory: float = 0.0  # -1 (inflamed) to +1 (stable)
var tide_level: float = 0.0     # governance tide
var dark_matter_score: float = 0.0  # implicit governance density
var health_charge: float = 0.0  # -1 (repels) to +1 (attracts)

## Visual
var mesh_instance: MeshInstance3D
var glow_material: ShaderMaterial
var label_3d: Label3D
var pin_marker: MeshInstance3D     # 3D pin/popup indicator
var popup_label: Label3D           # popup text (pipeline status, IXQL data)
var base_color: Color = Color(0.2, 0.6, 1.0)
var orbit_radius: float = 0.0
var orbit_speed: float = 0.0
var orbit_angle: float = 0.0
var pin_visible: bool = false      # whether pin/popup is active

## Constitutional mass — determines gravitational pull
var constitutional_mass: float = 1.0:
	get: return constitutional_mass
	set(value): constitutional_mass = value

## Children governance nodes (fractal structure)
var child_nodes: Array[GovernanceNode] = []
var parent_gov_node: GovernanceNode = null


func _ready() -> void:
	_setup_visual()
	_compute_mass()
	_compute_dark_matter()


func _process(delta: float) -> void:
	# Orbit around parent
	if orbit_radius > 0:
		orbit_angle += orbit_speed * delta
		position.x = cos(orbit_angle) * orbit_radius
		position.z = sin(orbit_angle) * orbit_radius

	# Update health charge based on belief state
	match belief_state:
		BeliefState.TRUE:
			health_charge = lerp(health_charge, 1.0, delta * 2.0)
		BeliefState.PROBABLE:
			health_charge = lerp(health_charge, 0.5, delta * 2.0)
		BeliefState.UNKNOWN:
			health_charge = lerp(health_charge, 0.0, delta * 2.0)
		BeliefState.DOUBTFUL:
			health_charge = lerp(health_charge, -0.3, delta * 2.0)
		BeliefState.FALSE:
			health_charge = lerp(health_charge, -0.7, delta * 2.0)
		BeliefState.CONTRADICTORY:
			# Oscillate — contradictions are unstable
			health_charge = sin(Time.get_ticks_msec() * 0.005) * 0.8

	# Tide decay (half-life ~7 days, but accelerated for visualization)
	tide_level = lerp(tide_level, 0.0, delta * 0.01)

	# Update visual
	_update_visual(delta)


func set_belief(new_state: BeliefState, new_confidence: float = -1.0) -> void:
	var old = belief_state
	belief_state = new_state
	if new_confidence >= 0:
		confidence = new_confidence
	belief_changed.emit(self, old, new_state)

	# Contradictory state is always algedonic
	if new_state == BeliefState.CONTRADICTORY:
		emit_pain(0.8, "Belief entered contradictory state")


func emit_pain(severity: float, description: String) -> void:
	# Try local absorption first (S3/S4)
	var effective_severity = severity * (1.0 - immune_memory * 0.3)

	# Update tide — pain inflames
	tide_level = clamp(tide_level - severity * 0.2, -1.0, 1.0)
	immune_memory = clamp(immune_memory - severity * 0.1, -1.0, 1.0)

	# Constitutional threshold check — bypass to S5 if critical
	if effective_severity >= 0.7 or belief_state == BeliefState.CONTRADICTORY:
		# Algedonic bypass — emit directly to parent S5
		algedonic_pain.emit(self, effective_severity, description)
	elif parent_gov_node:
		# Normal routing — let parent S3 handle
		parent_gov_node._receive_child_pain(self, effective_severity, description)


func emit_pleasure(magnitude: float, description: String) -> void:
	# Pleasure stabilizes
	tide_level = clamp(tide_level + magnitude * 0.15, -1.0, 1.0)
	immune_memory = clamp(immune_memory + magnitude * 0.05, -1.0, 1.0)
	algedonic_pleasure.emit(self, magnitude, description)


func _receive_child_pain(source: GovernanceNode, severity: float, description: String) -> void:
	# S3 control — try to absorb locally
	if severity < 0.5 and vsm_role >= VSMRole.S3_CONTROL:
		# Absorbed locally — log but don't escalate
		print("[%s] Absorbed pain from %s: %s (severity: %.2f)" % [node_name, source.node_name, description, severity])
		return

	# Can't absorb — escalate
	emit_pain(severity * 0.9, "Escalated from %s: %s" % [source.node_name, description])


func add_child_governance(child: GovernanceNode) -> void:
	child_nodes.append(child)
	child.parent_gov_node = self
	child.algedonic_pain.connect(_on_child_pain)
	child.algedonic_pleasure.connect(_on_child_pleasure)
	add_child(child)


func _on_child_pain(source: GovernanceNode, severity: float, description: String) -> void:
	_receive_child_pain(source, severity, description)


func _on_child_pleasure(source: GovernanceNode, magnitude: float, description: String) -> void:
	# Pleasure propagates upward attenuated
	emit_pleasure(magnitude * 0.7, "From %s: %s" % [source.node_name, description])


func _compute_mass() -> void:
	match node_type:
		"constitution": constitutional_mass = 30.0
		"department": constitutional_mass = 18.0
		"policy": constitutional_mass = 8.0
		"persona": constitutional_mass = 6.0
		"schema": constitutional_mass = 5.0
		"course": constitutional_mass = 4.0
		"test": constitutional_mass = 3.0
		_: constitutional_mass = 5.0


func _compute_dark_matter() -> void:
	# Implicit governance = constraints that COULD fire but haven't
	# More policies = more dark matter = more stability
	dark_matter_score = constitutional_mass * 0.2


func _setup_visual() -> void:
	# Sphere mesh sized by constitutional mass
	mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = sqrt(constitutional_mass) * 0.05
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh_instance.mesh = sphere

	# Shader material for hexavalent state rendering
	var mat = StandardMaterial3D.new()
	mat.albedo_color = _get_belief_color()
	mat.emission_enabled = true
	mat.emission = _get_belief_color() * 0.4
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	# Label
	label_3d = Label3D.new()
	label_3d.text = node_name.to_upper()
	label_3d.font_size = 48
	label_3d.modulate = Color(0.85, 0.92, 1.0, 0.9)
	label_3d.position.y = sqrt(constitutional_mass) * 0.3
	label_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_3d.no_depth_test = true
	label_3d.visible = false  # shown on proximity
	add_child(label_3d)

	# 3D Pin marker — small cone pointing down at the node
	_setup_pin()


func _update_visual(delta: float) -> void:
	if not mesh_instance or not mesh_instance.material_override:
		return

	var mat = mesh_instance.material_override as StandardMaterial3D
	var target_color = _get_belief_color()

	# Smooth color transition
	mat.albedo_color = mat.albedo_color.lerp(target_color, delta * 3.0)
	mat.emission = target_color * (0.3 + abs(health_charge) * 0.4)

	# Contradictory state: flicker
	if belief_state == BeliefState.CONTRADICTORY:
		var flicker = sin(Time.get_ticks_msec() * 0.01) * 0.5 + 0.5
		mat.emission_energy_multiplier = 1.0 + flicker * 3.0

	# Tide visualization — scale pulsing
	var tide_pulse = 1.0 + tide_level * 0.1
	mesh_instance.scale = Vector3.ONE * tide_pulse


func _get_belief_color() -> Color:
	match belief_state:
		BeliefState.TRUE:
			return Color(0.2, 0.9, 0.3)          # solid green
		BeliefState.PROBABLE:
			return Color(0.4, 0.85, 0.5)          # bright green, slight pulse
		BeliefState.UNKNOWN:
			return Color(0.9, 0.7, 0.2)           # amber
		BeliefState.DOUBTFUL:
			return Color(0.9, 0.4, 0.2)           # orange-red
		BeliefState.FALSE:
			return Color(0.9, 0.15, 0.15)         # solid red
		BeliefState.CONTRADICTORY:
			return Color(0.8, 0.2, 0.9)           # purple (interference)
	return Color.WHITE


# ---------------------------------------------------------------------------
# 3D Pins & Popups — IXQL pipeline status markers
# ---------------------------------------------------------------------------

func _setup_pin() -> void:
	# Pin: small inverted cone (like a map pin)
	pin_marker = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08
	cone.height = 0.25
	cone.radial_segments = 6
	pin_marker.mesh = cone
	pin_marker.position.y = sqrt(constitutional_mass) * 0.15 + 0.3
	pin_marker.rotation.x = PI  # point downward

	var pin_mat = StandardMaterial3D.new()
	pin_mat.albedo_color = Color(1, 0.3, 0.3)
	pin_mat.emission_enabled = true
	pin_mat.emission = Color(1, 0.3, 0.3)
	pin_mat.emission_energy_multiplier = 2.0
	pin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pin_marker.material_override = pin_mat
	pin_marker.visible = false
	add_child(pin_marker)

	# Popup label — billboard text above the pin
	popup_label = Label3D.new()
	popup_label.text = ""
	popup_label.font_size = 36
	popup_label.modulate = Color(1, 1, 1, 0.95)
	popup_label.outline_modulate = Color(0, 0, 0, 0.8)
	popup_label.outline_size = 4
	popup_label.position.y = sqrt(constitutional_mass) * 0.15 + 0.6
	popup_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	popup_label.no_depth_test = true
	popup_label.pixel_size = 0.003
	popup_label.visible = false
	add_child(popup_label)


## Show a 3D popup pin with text (triggered by IXQL pipeline events)
func show_pin(text: String, color: Color = Color(1, 0.3, 0.3)) -> void:
	pin_visible = true
	pin_marker.visible = true
	popup_label.visible = true
	popup_label.text = text

	var pin_mat = pin_marker.material_override as StandardMaterial3D
	if pin_mat:
		pin_mat.albedo_color = color
		pin_mat.emission = color

	# Auto-hide after 8 seconds
	var tween = create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(popup_label, "modulate:a", 0.0, 2.0)
	tween.parallel().tween_property(pin_marker, "scale", Vector3.ZERO, 2.0)
	tween.tween_callback(hide_pin)


## Hide the popup pin
func hide_pin() -> void:
	pin_visible = false
	pin_marker.visible = false
	popup_label.visible = false
	popup_label.modulat