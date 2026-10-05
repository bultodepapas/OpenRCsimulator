#!/usr/bin/env python3
"""Read-only inventory of one Rhino 3DM file, including cached Brep render meshes."""

from __future__ import annotations

import collections
import json
import os
import sys

import rhino3dm


def point_tuple(point):
    return [point.X, point.Y, point.Z]


def inspect(path: str) -> dict:
    model = rhino3dm.File3dm.Read(path)
    if model is None:
        raise RuntimeError(f"rhino3dm could not read {path!r}")

    object_types = collections.Counter()
    layer_objects = collections.Counter()
    layer_render = collections.defaultdict(collections.Counter)
    visible_objects = collections.Counter()
    direct_meshes = 0
    breps_with_render_cache = 0
    cached_render_face_meshes = 0
    mesh_triangles = 0
    mesh_quads = 0
    mesh_vertex_records = 0
    cached_analysis_face_meshes = 0
    cached_preview_face_meshes = 0

    for obj in model.Objects:
        geometry = obj.Geometry
        attributes = obj.Attributes
        geometry_type = type(geometry).__name__
        object_types[geometry_type] += 1
        visible_objects[str(attributes.Visible)] += 1
        layer_index = attributes.LayerIndex
        if 0 <= layer_index < len(model.Layers):
            layer = model.Layers[layer_index]
            layer_key = f"{layer_index}:{layer.Name}"
        else:
            layer_key = f"{layer_index}:<invalid>"
        layer_objects[layer_key] += 1

        if isinstance(geometry, rhino3dm.Mesh):
            direct_meshes += 1

        if not isinstance(geometry, rhino3dm.Brep):
            continue

        object_has_render_mesh = False
        for face in geometry.Faces:
            render_mesh = face.GetMesh(rhino3dm.MeshType.Render)
            if render_mesh is not None:
                object_has_render_mesh = True
                cached_render_face_meshes += 1
                mesh_vertex_records += len(render_mesh.Vertices)
                face_count = len(render_mesh.Faces)
                layer_render[layer_key]["face_meshes"] += 1
                layer_render[layer_key]["vertices"] += len(render_mesh.Vertices)
                layer_render[layer_key]["mesh_faces"] += face_count
                for mesh_face_index in range(face_count):
                    mesh_face = render_mesh.Faces[mesh_face_index]
                    if mesh_face[2] == mesh_face[3]:
                        mesh_triangles += 1
                    else:
                        mesh_quads += 1
            if face.GetMesh(rhino3dm.MeshType.Analysis) is not None:
                cached_analysis_face_meshes += 1
            if face.GetMesh(rhino3dm.MeshType.Preview) is not None:
                cached_preview_face_meshes += 1
        if object_has_render_mesh:
            breps_with_render_cache += 1

    bbox = model.Objects.GetBoundingBox()
    return {
        "file": os.path.abspath(path),
        "bytes": os.path.getsize(path),
        "rhino3dm_version": rhino3dm.__version__,
        "file_application": model.ApplicationName,
        "file_details": model.ApplicationDetails,
        "created_by": model.CreatedBy,
        "created": str(model.Created),
        "unit_system": str(model.Settings.ModelUnitSystem),
        "layer_count": len(model.Layers),
        "layers": [
            {
                "index": index,
                "name": layer.Name,
                "visible": layer.Visible,
                "object_count": layer_objects.get(f"{index}:{layer.Name}", 0),
            }
            for index, layer in enumerate(model.Layers)
        ],
        "material_count": len(model.Materials),
        "object_count": len(model.Objects),
        "object_types": dict(sorted(object_types.items())),
        "object_layers": dict(sorted(layer_objects.items())),
        "visible_objects": dict(visible_objects),
        "bounding_box_model_units": {
            "min": point_tuple(bbox.Min),
            "max": point_tuple(bbox.Max),
            "size": [bbox.Max.X - bbox.Min.X, bbox.Max.Y - bbox.Min.Y, bbox.Max.Z - bbox.Min.Z],
        },
        "explicit_mesh_objects": direct_meshes,
        "cached_brep_render_meshes": {
            "breps_with_at_least_one_face_mesh": breps_with_render_cache,
            "face_mesh_count": cached_render_face_meshes,
            "triangle_faces": mesh_triangles,
            "quad_faces": mesh_quads,
            "triangles_if_each_quad_is_split": mesh_triangles + 2 * mesh_quads,
            "face_local_vertex_records_not_welded": mesh_vertex_records,
            "per_layer": {key: dict(value) for key, value in sorted(layer_render.items())},
        },
        "cached_analysis_face_meshes": cached_analysis_face_meshes,
        "cached_preview_face_meshes": cached_preview_face_meshes,
    }


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.executable} {sys.argv[0]} path/to/file.3dm")
    print(json.dumps(inspect(sys.argv[1]), indent=2, ensure_ascii=False))
