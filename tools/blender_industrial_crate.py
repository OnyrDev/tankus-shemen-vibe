#!/usr/bin/env python3
"""
Blender Python Script (bpy) for the Heavy Industrial Crate (TANKUS).
Usage:
  1. Inside Blender: Scripting workspace -> Open -> Run Script
  2. Headless CLI:   blender -b -P tools/blender_industrial_crate.py -- --output assets/props/industrial_crate/industrial_crate.glb
"""

import os
import sys

# Ensure our procedural geometry module can be imported when run inside Blender
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from generate_industrial_crate import build_crate_mesh  # noqa: E402


def build_in_blender(export_glb_path: str = "") -> None:
    import bpy  # type: ignore

    # Clear existing mesh objects in scene
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    mb = build_crate_mesh()

    mesh = bpy.data.meshes.new("IndustrialCrateMesh")
    obj = bpy.data.objects.new("IndustrialCrate", mesh)
    bpy.context.collection.objects.link(obj)

    faces = [
        (mb.indices[i], mb.indices[i + 1], mb.indices[i + 2])
        for i in range(0, len(mb.indices), 3)
    ]
    mesh.from_pydata(mb.positions, [], faces)
    mesh.update()

    # Custom split normals from our procedural builder
    mesh.normals_split_custom_set_from_vertices(mb.normals)

    # UV Map
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            vert_idx = mesh.loops[loop_idx].vertex_index
            uv_layer.data[loop_idx].uv = mb.uvs[vert_idx]

    # Vertex Colors (COLOR_0)
    color_attr = mesh.color_attributes.new(
        name="Color", type="FLOAT_COLOR", domain="CORNER"
    )
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            vert_idx = mesh.loops[loop_idx].vertex_index
            color_attr.data[loop_idx].color = mb.colors[vert_idx]

    # Procedural PBR Material (Principled BSDF + Vertex Color + Procedural Scratches/Noise)
    mat = bpy.data.materials.new(name="IndustrialGunmetal")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out_node = nodes.new(type="ShaderNodeOutputMaterial")
    out_node.location = (400, 0)

    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    bsdf.inputs["Metallic"].default_value = 0.35
    bsdf.inputs["Roughness"].default_value = 0.48
    links.new(bsdf.outputs["BSDF"], out_node.inputs["Surface"])

    vcol_node = nodes.new(type="ShaderNodeVertexColor")
    vcol_node.layer_name = "Color"
    vcol_node.location = (-400, 120)

    noise_node = nodes.new(type="ShaderNodeTexNoise")
    noise_node.location = (-400, -120)
    noise_node.inputs["Scale"].default_value = 18.0
    noise_node.inputs["Detail"].default_value = 8.0
    noise_node.inputs["Roughness"].default_value = 0.65

    mix_node = nodes.new(type="ShaderNodeMixRGB")
    mix_node.blend_type = "MULTIPLY"
    mix_node.inputs["Fac"].default_value = 0.12
    mix_node.location = (-150, 80)
    links.new(vcol_node.outputs["Color"], mix_node.inputs["Color1"])
    links.new(noise_node.outputs["Fac"], mix_node.inputs["Color2"])
    links.new(mix_node.outputs["Color"], bsdf.inputs["Base Color"])

    bump_node = nodes.new(type="ShaderNodeBump")
    bump_node.location = (-150, -160)
    bump_node.inputs["Strength"].default_value = 0.04
    links.new(noise_node.outputs["Fac"], bump_node.inputs["Height"])
    links.new(bump_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)

    if export_glb_path:
        os.makedirs(os.path.dirname(os.path.abspath(export_glb_path)), exist_ok=True)
        bpy.ops.export_scene.gltf(
            filepath=export_glb_path,
            export_format="GLB",
            use_selection=False,
            export_apply=True,
        )
        print(f"Blender exported GLB to: {export_glb_path}")


if __name__ == "__main__":
    out_glb = ""
    if "--" in sys.argv:
        args = sys.argv[sys.argv.index("--") + 1 :]
        if "--output" in args:
            idx = args.index("--output")
            if idx + 1 < len(args):
                out_glb = args[idx + 1]
    build_in_blender(out_glb)
