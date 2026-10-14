"""Add CR-22c-R1 timers to a disposable snapshot; never use on the shared app/."""
from pathlib import Path
import argparse


def instrument(project):
    # Validate every patch before writing any file. Refuse double instrumentation.
    patches = {}
    path = project / "main.gd"
    source = path.read_text(encoding="utf-8")
    assert "var profile_clock" not in source
    start = "func _process(delta: float) -> void:"
    end = "\n\nfunc _update_cg_model()"
    assert start in source and end in source
    source = source.replace(start, start + "\n\tvar profile_clock := Time.get_ticks_usec()")
    patches[path] = source.replace(end,
        '\n\tset_meta("process_us", Time.get_ticks_usec() - profile_clock)\n' + end)

    path = project / "render/crash/director.gd"
    source = path.read_text(encoding="utf-8")
    assert "var clock_wreck" not in source
    for name, call in [
        ("wreck", "wreck.start(root_pose,velocity,angular,report)"),
        ("effects", "effects.start(_impact_point,velocity,report,_fuel_kg,hot,flight._render_wind(flight.session.sim.time()))"),
        ("energy", "effects.apply_energy(report.energy)"),
        ("audio", "audio.impact(_impact_point,report,turbine)"),
    ]:
        indent = "\t\t" if name == "audio" else "\t"
        assert indent + call in source
        source = source.replace(indent + call,
            indent + f"var clock_{name} := Time.get_ticks_usec()\n" + indent + call + "\n" +
            indent + f'set_meta("profile", get_meta("profile", {{}}).merged({{"{name}": Time.get_ticks_usec() - clock_{name}}}, true))')
    patches[path] = source

    path = project / "render/crash/airframe_scuffs.gd"
    source = path.read_text(encoding="utf-8")
    signature = "func add(root: Node3D, point: Vector3, velocity: Vector3, strength: float, surface: String) -> MeshInstance3D:"
    assert signature in source and '"scuff_samples"' not in source
    wrapper = '''
	var began := Time.get_ticks_usec()
	var result := _add(root, point, velocity, strength, surface)
	var samples: Array = root.get_meta("scuff_samples", [])
	samples.append(Time.get_ticks_usec() - began)
	root.set_meta("scuff_samples", samples)
	return result


'''
    patches[path] = source.replace(signature, signature + wrapper + signature.replace("func add(", "func _add("))
    for path, source in patches.items():
        path.write_text(source, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    instrument(parser.parse_args().project.resolve())
