extends SceneTree
const PA = preload("res://scenery/parked_aircraft.gd")
func _initialize() -> void:
    var total_stored := 0
    var total_decoded := 0
    var total_unique := 0
    var total_refs := 0
    for aircraft in PA.AIRCRAFT:
        var configs: Array[String] = ["assembled"]
        if aircraft == "jensen-das-ugly-stik-60": configs.append("service")
        for cfg in configs:
            var key = str(PA.AIRCRAFT[aircraft]) + "_" + cfg
            var mesh: ArrayMesh = PA.mesh(aircraft, cfg)
            var unique := {}
            var occurrences := 0
            var unique_bytes := 0
            var decoded_bytes := 0
            var repeated_bytes := 0
            var details: Array[String] = []
            for s in mesh.get_surface_count():
                var mat = mesh.surface_get_material(s)
                for prop in mat.get_property_list():
                    if int(prop.type) != TYPE_OBJECT: continue
                    var tex = mat.get(str(prop.name))
                    if not tex is Texture2D: continue
                    occurrences += 1
                    var img: Image = tex.get_image()
                    var context := HashingContext.new()
                    context.start(HashingContext.HASH_SHA256)
                    context.update((str(img.get_width(), "x", img.get_height(), "|", img.get_format(), "|")).to_utf8_buffer())
                    context.update(img.get_data())
                    var hash = context.finish().hex_encode()
                    var bytes = img.get_data().size()
                    if not unique.has(hash):
                        unique[hash] = true
                        unique_bytes += bytes
                        var decoded: Image = img.duplicate()
                        if decoded.is_compressed():
                            assert(decoded.decompress() == OK)
                        decoded_bytes += decoded.get_data().size()
                    else:
                        repeated_bytes += bytes
                    details.append("s%d:%s=%s %dx%d %s bytes=%d hash=%s" % [s, str(prop.name), tex.get_class(), img.get_width(), img.get_height(), str(img.get_format()), bytes, hash.substr(0,12)])
            total_stored += unique_bytes
            total_decoded += decoded_bytes
            total_unique += unique.size()
            total_refs += occurrences
            print("RESOURCE %s surfaces=%d tex_refs=%d unique_textures=%d unique_stored_bytes=%d decoded_bytes=%d repeat_stored_bytes=%d" % [key, mesh.get_surface_count(), occurrences, unique.size(), unique_bytes, decoded_bytes, repeated_bytes])
            for d in details: print("  " + d)
    print("TOTAL per-resource unique textures=%d references=%d stored_bytes=%d decoded_bytes=%d reduction_percent=%.2f" % [total_unique, total_refs, total_stored, total_decoded, 100.0 * (1.0 - float(total_stored) / total_decoded)])
    quit()
