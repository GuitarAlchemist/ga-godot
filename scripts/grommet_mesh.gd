## Rope grommet: a ring made by laying one strand around itself p times. The strand's
## centreline is the (p, q) torus knot: p laps around the ring while it winds q times around
## the ring's core. Built as a tube along that curve so each strand pass is real geometry.
## The mesh lies in the XZ plane, like TorusMesh, so it drops into the moon ring's transform.
extends RefCounted


## Empty when the grommet can be laid, otherwise why not. Two craft rules:
## - gcd(p, q) == 1, or the curve closes as several separate strands (a link), not one strand;
## - neighbouring passes must not cut through each other. They sit 2a·sin(π/p) apart around
##   the core, tilted by the lay angle; 2a·sin(π/p)·cos(lay) slightly underestimates the gap
##   between centrelines, so the rule is conservative. It must exceed the strand diameter 2s.
static func check(core_radius: float, lay_radius: float, strand_radius: float, p: int, q: int) -> String:
	if p < 2 or q < 2:
		return "grommet: p and q must be at least 2 (got %d, %d)" % [p, q]
	if _gcd(p, q) != 1:
		return "grommet: gcd(%d, %d) = %d, the strand would close as %d separate loops" % [p, q, _gcd(p, q), _gcd(p, q)]
	if core_radius <= lay_radius or lay_radius <= 0.0 or strand_radius <= 0.0:
		return "grommet: need core radius > lay radius > 0 and strand radius > 0"
	var lay := atan(lay_radius * q / (core_radius * p))
	var gap := 2.0 * lay_radius * sin(PI / p) * cos(lay)
	if gap <= 2.0 * strand_radius:
		return "grommet: strands overlap (centreline gap %.4f <= strand diameter %.4f)" % [gap, 2.0 * strand_radius]
	return ""


## R: radius of the ring's core circle; a: distance of the strand's centre from that core;
## s: strand radius; samples along the strand and sides around it. Returns null when check() fails.
static func build(core_radius: float, lay_radius: float, strand_radius: float, p: int = 3, q: int = 41,
		samples: int = 656, sides: int = 8) -> ArrayMesh:
	var error := check(core_radius, lay_radius, strand_radius, p, q)
	if not error.is_empty():
		push_error(error)
		return null
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(samples * sides)
	normals.resize(samples * sides)
	for i in samples:
		var t := TAU * i / samples
		var cp := cos(p * t)
		var sp := sin(p * t)
		var cq := cos(q * t)
		var sq := sin(q * t)
		var r := core_radius + lay_radius * cq
		var centre := Vector3(r * cp, lay_radius * sq, r * sp)
		var tangent := Vector3(-lay_radius * q * sq * cp - r * p * sp, lay_radius * q * cq,
			-lay_radius * q * sq * sp + r * p * cp).normalized()
		# The offset from the core circle is always perpendicular to the strand's tangent.
		var n := Vector3(cq * cp, sq, cq * sp)
		var b := tangent.cross(n).normalized()
		for j in sides:
			var phi := TAU * j / sides
			var out := n * cos(phi) + b * sin(phi)
			verts[i * sides + j] = centre + out * strand_radius
			normals[i * sides + j] = out
	var indices := PackedInt32Array()
	indices.resize(samples * sides * 6)
	var k := 0
	for i in samples:
		var i1 := (i + 1) % samples
		for j in sides:
			var j1 := (j + 1) % sides
			var a := i * sides + j
			var bb := i1 * sides + j
			var c := i1 * sides + j1
			var d := i * sides + j1
			# Clockwise seen from outside the strand: Godot's front faces.
			indices[k] = a
			indices[k + 1] = bb
			indices[k + 2] = c
			indices[k + 3] = a
			indices[k + 4] = c
			indices[k + 5] = d
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _gcd(x: int, y: int) -> int:
	while y != 0:
		var m := x % y
		x = y
		y = m
	return x
