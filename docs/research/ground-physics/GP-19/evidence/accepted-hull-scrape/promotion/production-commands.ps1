python tools/godot/run_checked.py --warnings-as-errors --require-text 'Hull scrape metrics: 367 checks, 0 failed' --timeout 90 --out tmp/gp19-hull-scrape/checks/production-hull_friction_observation -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_hull_friction_observation.gd

python tools/godot/run_checked.py --warnings-as-errors --require-text 'Hull scrape audio: 46 checks, 0 failed' --timeout 90 --out tmp/gp19-hull-scrape/checks/production-hull_scrape_audio -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_hull_scrape_audio.gd

python tools/godot/run_checked.py --warnings-as-errors --require-text 'Hull scrape Session: 44 checks, 0 failed' --timeout 150 --out tmp/gp19-hull-scrape/checks/production-hull_scrape_session -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_hull_scrape_session.gd

python tools/godot/run_checked.py --warnings-as-errors --require-text '12 checks, 0 failed' --timeout 90 --out tmp/gp19-hull-scrape/checks/production-crash_audio -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_crash_audio.gd

python tools/godot/run_checked.py --warnings-as-errors --require-text '36 checks, 0 failed' --timeout 150 --out tmp/gp19-hull-scrape/checks/production-soft_contacts -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_soft_contacts.gd

python tools/godot/run_checked.py --warnings-as-errors --require-text 'checks, 0 failed' --timeout 150 --out tmp/gp19-hull-scrape/checks/production-soft_contact_feedback -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_soft_contact_feedback.gd

python tools/godot/run_checked.py --warnings-as-errors --require-text 'checks, 0 failed' --timeout 150 --out tmp/gp19-hull-scrape/checks/production-water_director -- .tools/Godot_v4.8-beta1_win64_console.exe --headless --audio-driver Dummy --path app --script res://tests/test_water_director.gd
