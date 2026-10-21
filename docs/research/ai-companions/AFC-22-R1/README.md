# AFC-22-R1 offline fixed-roster continuation proof

The retained native checkpoint JSON, continuation report, runner report, and engine log are copied byte-for-byte from the completed Godot 4.7.2 proof. `receipt.json` binds their SHA-256 digests to the report's full source-hash manifest and selected simulation/controller inputs. The frozen run passed 53 checks with zero failures at tick 137 and compared 240 continuation ticks.

Limits: research-only offline proof; it does not establish a live `Main` restore path or a product checkpoint feature. It covers one fixed two-agent Club/Stik roster and one profile/build/world identity. The world is clean and shared state does not include scenery damage, inter-aircraft contact, incidents, runway/activity reservations, hot admission/retirement, generation/config/weather changes, or world transitions. Timeout is not used to infer physical recovery. The report is the authoritative limit list.

[Pilot 3842 checkpoint supplement (2026-10-21)](pilot3842-20261021/README.md)
