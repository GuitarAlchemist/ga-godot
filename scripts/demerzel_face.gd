## DemerzelFace — Rigged 3D face with blend-shape expression system.
## Drives facial expressions via shape keys, matching the 5-emotion model
## from the Three.js holographic face. Works with any .glb face mesh that
## has the expected blend shape names.
##
## Until a real .glb model is imported, creates a procedural placeholder
## (gold icosphere with simulated expressions via scale/color).
extends Node3D

signal emotion_changed(emotion_name: String)

# ---------------------------------------------------------------------------
# Emotion enum — mirrors DemerzelFace.ts
# ---------------------------------------------------------------------------
enum Emotion { CALM, CONCERNED, THINKING, PLEASED, ALERT }

const EMOTION_NAMES: PackedStringArray = ["calm", "concerned", "thinking", "pleased", "alert"]

# ---------------------------------------------------------------------------
# Shape key expression presets (name → weight)
# Each float is 0.0–1.0
# ---------------------------------------------------------------------------
## Expression presets using ARKit blend shape names (52 standard shapes).
## The Three.js facecap model from three.js uses these exact names.
## See: browInnerUp, browDown_L/R, browOuterUp_L/R, eyeBlink_L/R,
##      eyeSquint_L/R, eyeWide_L/R, jawOpen, mouthSmile_L/R,
##      mouthFrown_L/R, cheekPuff, etc.
const EXPRESSIONS: Dictionary = {
	Emotion.CALM: {
		"mouthSmile_L": 0.05, "mouthSmile_R": 0.05,
	},
	Emotion.CONCERNED: {
		"browInnerUp": 0.4,
		"browDown_L": 0.3, "browDown_R": 0.3,
		"mouthFrown_L": 0.2, "mouthFrown_R": 0.2,
		"jawOpen": 0.1,
		"eyeWide_L": 0.2, "eyeWide_R": 0.2,
	},
	Emotion.THINKING: {
		"browInnerUp": 0.2,
		"browDown_L": 0.15,
		"eyeSquint_L": 0.2, "eyeSquint_R": 0.2,
		"eyeLookUp_L": 0.15, "eyeLookUp_R": 0.15,
		"mouthPucker": 0.1,
	},
	Emotion.PLEASED: {
		"browOuterUp_L": 0.15, "browOuterUp_R": 0.15,
		"mouthSmile_L": 0.5, "mouthSmile_R": 0.5,
		"cheekSquint_L": 0.3, "cheekSquint_R": 0.3,
		"jawOpen": 0.1,
	},
	Emotion.ALERT: {
		"browOuterUp_L": 0.5, "browOuterUp_R": 0.5,
		"browInnerUp": 0.5,
		"mouthFrown_L": 0.1, "mouthFrown_R": 0.1,
		"jawOpen": 0.2,
		"eyeWide_L": 0.4, "eyeWide_R": 0.4,
	},
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _face_mesh: MeshInstance3D = null
var _shape_indices: Dictionary = {}     # shape_name → int index
var _current_weights: Dictionary = {}   # shape_name → current float
var _target_weights: Dictionary = {}    # shape_name → target float
var _has_blend_shapes: bool = false

var _current_emotion: Emotion = Emotion.CALM
var _blend_speed: float = 3.0           # lerp speed (weights/sec)

# Blink
var _blink_timer: float = 0.0
var _next_blink: float = 4.0
var _blink_phase: float = -1.0         # -1 = not blinking

# Auto-cycle emotions
var _emotion_timer: float = 0.0
var _next_emotion_change: float = 10.0
var _auto_cycle: bool = true

# Speaking
var _is_speaking: bool = false
var _speak_phase: float = 0.0

# Holographic shader reference
var _holo_material: ShaderMaterial = null

# Placeholder mode (no .glb loaded)
var _placeholder_mode: bool = false
var _placeholder_mesh: MeshInstance3D = null
var _placeholder_mat: StandardMaterial3D = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
## Path to the .glb face model (imported by Godot as a scene)
@export var face_model_path: String = "res://assets/models/demerzel_face.glb"

func _ready() -> void:
	_try_find_face_mesh()
	if _face_mesh == null:
		_try_load_glb()
	if _face_mesh == null:
		_create_placeholder()
	_next_blink = randf_range(2.5, 6.5)
	_next_emotion_change = randf_range(8.0, 14.0)
	set_emotion(Emotion.CALM)


func _process(delta: float) -> void:
	if _has_blend_shapes:
		_update_blend_weights(delta)
	_update_blink(delta)
	_update_speaking(delta)
	if _auto_cycle:
		_update_auto_emotion(delta)
	if _placeholder_mode:
		_update_placeholder(delta)

# ---------------------------------------------------------------------------
# Load .glb face model at runtime
# ---------------------------------------------------------------------------
func _try_load_glb() -> void:
	if not ResourceLoader.exists(face_model_path):
		print("[DemerzelFace] No .glb found at %s — using placeholder" % face_model_path)
		return
	var scene := load(face_model_path) as PackedScene
	if scene == null:
		push_warning("[DemerzelFace] Failed to load %s" % face_model_path)
		return
	var instance := scene.instantiate()
	instance.name = "FaceModel"
	add_child(instance)
	# Now search for blend shapes in the imported scene tree
	_try_find_face_mesh()
	if _face_mesh:
		print("[DemerzelFace] Loaded .glb model with %d blend shapes" % _shape_indices.size())
	else:
		# Model loaded but no blend shapes found — remove it
		instance.queue_free()
		push_warning("[DemerzelFace] .glb loaded but no blend shapes found")

# ---------------------------------------------------------------------------
# Face mesh discovery — look for MeshInstance3D child with blend shapes
# ---------------------------------------------------------------------------
func _try_find_face_mesh() -> void:
	# Recursively search all descendants for a MeshInstance3D with blend shapes
	# (imported .glb files can nest meshes several levels deep)
	var found := _find_blend_shape_mesh(self)
	if found:
		_face_mesh = found
		_cache_shape_indices()
		_has_blend_shapes = true


func _find_blend_shape_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst := child as MeshInstance3D
			if mesh_inst.mesh and mesh_inst.mesh.get_blend_shape_count() > 0:
				return mesh_inst
		var deep := _find_blend_shape_mesh(child)
		if deep:
			return deep
	return null


func _cache_shape_indices() -> void:
	if _face_mesh == null or _face_mesh.mesh == null:
		return
	var mesh := _face_mesh.mesh
	for i in range(mesh.get_blend_shape_count()):
		var shape_name := mesh.get_blend_shape_name(i)
		_shape_indices[shape_name] = i
		_current_weights[shape_name] = 0.0
	print("[DemerzelFace] Cached %d blend shapes: %s" % [
		_shape_indices.size(),
		", ".join(PackedStringArray(_shape_indices.keys()))
	])

# ---------------------------------------------------------------------------
# Placeholder face — procedural gold icosphere with emotion via color/scale
# ---------------------------------------------------------------------------
func _create_placeholder() -> void:
	_placeholder_mode = true

	_placeholder_mesh = MeshInstance3D.new()
	var ico := SphereMesh.new()
	ico.radius = 1.2
	ico.height = 2.6
	ico.radial_segments = 24
	ico.rings = 12
	_placeholder_mesh.mesh = ico

	# Try to load holographic shader
	var shader_path := "res://shaders/demerzel_holo.gdshader"
	if ResourceLoader.exists(shader_path):
		var shader := load(shader_path) as Shader
		_holo_material = ShaderMaterial.new()
		_holo_material.shader = shader
		_placeholder_mesh.material_override = _holo_material
	else:
		# Fallback: gold emissive unshaded material
		_placeholder_mat = StandardMaterial3D.new()
		_placeholder_mat.albedo_color = Color(1.0, 0.84, 0.0, 0.7)
		_placeholder_mat.emission_enabled = true
		_placeholder_mat.emission = Color(1.0, 0.84, 0.0)
		_placeholder_mat.emission_energy_multiplier = 2.0
		_placeholder_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_placeholder_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_placeholder_mesh.material_override = _placeholder_mat

	add_child(_placeholder_mesh)

	# Eyes — two small bright spheres
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.18
		eye_mesh.height = 0.36
		eye.mesh = eye_mesh
		var eye_mat := StandardMaterial3D.new()
		eye_mat.albedo_color = Color(1.0, 0.95, 0.7)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(1.0, 0.95, 0.7)
		eye_mat.emission_energy_multiplier = 6.0
		eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.4, 0.3, 1.0)
		_placeholder_mesh.add_child(eye)

	# Mouth — thin stretched sphere
	var mouth := MeshInstance3D.new()
	var mouth_mesh := SphereMesh.new()
	mouth_mesh.radius = 0.06
	mouth_mesh.height = 0.12
	mouth.mesh = mouth_mesh
	mouth.scale = Vector3(3.0, 1.0, 0.5)
	mouth.position = Vector3(0, -0.35, 1.05)
	var mouth_mat := StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(1.0, 0.84, 0.0, 0.6)
	mouth_mat.emission_enabled = true
	mouth_mat.emission = Color(1.0, 0.84, 0.0)
	mouth_mat.emission_energy_multiplier = 3.0
	mouth_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mouth_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mouth.material_override = mouth_mat
	mouth.name = "Mouth"
	_placeholder_mesh.add_child(mouth)

	print("[DemerzelFace] Placeholder mode — no .glb blend shapes found")


func _update_placeholder(delta: float) -> void:
	if _placeholder_mesh == null:
		return

	# Breathing oscillation
	var breath := 1.0 + sin(Time.get_ticks_msec() * 0.001 * 0.8) * 0.02
	_placeholder_mesh.scale = Vector3(breath, breath * 1.02, breath * 0.98)

	# Head sway
	_placeholder_mesh.rotation.y = sin(Time.get_ticks_msec() * 0.001 * 0.3) * 0.08
	_placeholder_mesh.rotation.x = sin(Time.get_ticks_msec() * 0.001 * 0.2) * 0.04

	# Mouth animation when speaking
	var mouth_node := _placeholder_mesh.get_node_or_null("Mouth")
	if mouth_node and _is_speaking:
		var jaw := abs(sin(_speak_phase)) * 0.4
		mouth_node.scale.y = 1.0 + jaw * 3.0
		mouth_node.position.y = -0.35 - jaw * 0.1

	# Update shader speaking_pulse if available
	if _holo_material:
		_holo_material.set_shader_parameter("speaking_pulse", 1.0 if _is_speaking else 0.0)

# ---------------------------------------------------------------------------
# Blend shape interpolation
# ---------------------------------------------------------------------------
func _update_blend_weights(delta: float) -> void:
	for shape_name in _shape_indices:
		var target: float = _target_weights.get(shape_name, 0.0)
		var current: float = _current_weights.get(shape_name, 0.0)
		if absf(current - target) > 0.001:
			current = lerp(current, target, delta * _blend_speed)
			_current_weights[shape_name] = current
			_face_mesh.set_blend_shape_value(_shape_indices[shape_name], current)

# ---------------------------------------------------------------------------
# Blink
# ---------------------------------------------------------------------------
func _update_blink(delta: float) -> void:
	if _blink_phase >= 0.0:
		# Currently blinking — advance phase
		_blink_phase += delta * 13.0  # ~150ms full blink
		var blink_val: float
		if _blink_phase < 1.0:
			blink_val = _blink_phase  # closing
		elif _blink_phase < 2.0:
			blink_val = 2.0 - _blink_phase  # opening
		else:
			blink_val = 0.0
			_blink_phase = -1.0  # done

		if _has_blend_shapes:
			for side in ["eyeBlink_L", "eyeBlink_R"]:
				if side in _shape_indices:
					_face_mesh.set_blend_shape_value(_shape_indices[side], blink_val)
		# Placeholder blink: scale eyes
		elif _placeholder_mode and _placeholder_mesh:
			for child in _placeholder_mesh.get_children():
				if child is MeshInstance3D and child.name != "Mouth":
					child.scale.y = max(0.05, 1.0 - blink_val * 0.95)
		return

	_blink_timer += delta
	if _blink_timer >= _next_blink:
		_blink_timer = 0.0
		_next_blink = randf_range(2.5, 6.5)
		_blink_phase = 0.0

# ---------------------------------------------------------------------------
# Speaking
# ---------------------------------------------------------------------------
func _update_speaking(delta: float) -> void:
	if not _is_speaking:
		return
	_speak_phase += delta * 12.0
	var jaw_val := abs(sin(_speak_phase)) * 0.4
	if _has_blend_shapes and "JawOpen" in _shape_indices:
		_face_mesh.set_blend_shape_value(_shape_indices["JawOpen"], jaw_val)

# ---------------------------------------------------------------------------
# Auto-cycle emotions
# ---------------------------------------------------------------------------
func _update_auto_emotion(delta: float) -> void:
	_emotion_timer += delta
	if _emotion_timer >= _next_emotion_change:
		_emotion_timer = 0.0
		_next_emotion_change = randf_range(8.0, 14.0)
		var idx := randi() % Emotion.size()
		set_emotion(idx as Emotion)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set emotion by enum value
func set_emotion(emotion: Emotion) -> void:
	_current_emotion = emotion
	# Reset all targets to 0
	_target_weights = {}
	for name in _shape_indices:
		_target_weights[name] = 0.0
	# Apply preset overrides
	var preset: Dictionary = EXPRESSIONS.get(emotion, {})
	for name in preset:
		_target_weights[name] = preset[name]
	var ename := EMOTION_NAMES[emotion] if emotion < EMOTION_NAMES.size() else "calm"
	emit_signal("emotion_changed", ename)

## Set emotion by string name (for web bridge)
func set_emotion_by_name(name: String) -> void:
	var lower := name.to_lower()
	for i in range(EMOTION_NAMES.size()):
		if EMOTION_NAMES[i] == lower:
			set_emotion(i as Emotion)
			return
	push_warning("[DemerzelFace] Unknown emotion: %s" % name)

## Get current emotion name
func get_emotion_name() -> String:
	return EMOTION_NAMES[_current_emotion] if _current_emotion < EMOTION_NAMES.size() else "calm"

## Set speaking state
func set_speaking(speaking: bool) -> void:
	_is_speaking = speaking
	_speak_phase = 0.0
	if not speaking:
		# Reset jaw
		if _has_blend_shapes and "JawOpen" in _shape_indices:
			_face_mesh.set_blend_shape_value(_shape_indices["JawOpen"], 0.0)
		if _placeholder_mode:
			var mouth_node := _placeholder_mesh.get_node_or_null("Mouth") if _placeholder_mesh else null
			if mouth_node:
				mouth_node.scale.y = 1.0
				mouth_node.position.y = -0.35

## Enable/disable auto-cycling of emotions
func set_auto_cycle(enabled: bool) -> void:
	_auto_cycle = enabled

## Get list of available blend shapes (for debugging)
func get_available_shapes() -> PackedStringArray:
	return PackedStringArray(_shape_indices.keys())

## Check if a real face model is loaded (vs placeholder)
func has_face_model() -> bool:
	return _has_blend_shapes
