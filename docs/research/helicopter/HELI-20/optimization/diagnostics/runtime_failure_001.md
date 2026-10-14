# Temporary experiment diagnostic: runtime failure before sampling

- Status: `complete: false`; no measured timing samples were collected.
- Command: `Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/heli-ground-contact-candidate-20261014/project --script res://research/helicopter/ground_start/contact_abba.gd`
- Failure: the harness tried to assign a conditional untyped `Array` to `Array[String]` at `contact_abba.gd:40`.
- Raw console output:

```text
Godot Engine v4.7.2.stable.official.ed1daf0bf

SCRIPT ERROR: Trying to assign an array of type "Array" to a variable of type "Array[String]".
   at: _run (res://research/helicopter/ground_start/contact_abba.gd:40)
GDScript backtrace (most recent call first):
       [0] _run (res://research/helicopter/ground_start/contact_abba.gd:40)
```

The temporary harness now uses `PackedStringArray` for AB/BA order. Production files were untouched.
