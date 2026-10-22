class_name TankAppearance
extends Node3D

## Shared armor recoloring for the playable tank and lobby showroom.
## Preserve rubber, steel, optics and warning accents from the GLB.
static func apply_team_color(model: Node3D, color: Color) -> void:
	if not model:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.mesh or mesh.name == "ShieldMesh":
			continue
		mesh.material_override = null
		for surface in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if not original:
				continue
			var is_enamel := original.resource_name.contains("Cobalt enamel")
			var is_dark_armor := original.resource_name.contains("Deep blue armor")
			if not is_enamel and not is_dark_armor:
				continue
			var material := original.duplicate() as StandardMaterial3D
			material.albedo_color = color.darkened(0.45) if is_dark_armor else color
			mesh.set_surface_override_material(surface, material)
