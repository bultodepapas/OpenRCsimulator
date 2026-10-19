# Small RC helicopter flight dynamics and rotor evidence

Research expansion of the [RC validation library](../README.md), checked 2026-10-19. This collection targets small radio-controlled single-rotor helicopters and model-scale rotor tests. It prioritizes measured flight response, system identification, rotor performance and flow measurements, and documented hardware over controller-only simulations. It does not establish physical validation of this simulator.

The older [HELI-01 research record](../../../helicopter/HELI-01/README.md) provides an engineering synthesis of several key X-Cell, Raptor, R-50 and flybarless-model studies. No original files were present in `references/helicopter/` at intake; this topic collection retains public originals under `references/rc-validation-library-2026-10-18/helicopters/`. The [manifest](sources.json) is authoritative for the bibliographic data, original URL, local path, hash, access status, rights statement, study limits, and inspection depth.

## Evidence boundaries

Keep model size and evidence type explicit. The MIT X-Cell .60/.90, Align T-Rex family, Thunder Tiger Raptor 50, Trex-250, and other hobby airframes are small RC helicopters. The Yamaha R-50/RMAX and related agricultural UAVs have several-metre rotors and substantially different mass, Reynolds number, hardware, and operating context; they are analogues for modeling or identification methods, not direct RC performance targets. Rotor-stand and wind-tunnel measurements support only their tested geometry, speed, pitch, ground clearance, and flow conditions. Identified closed-loop flight models should not be read as open-loop aerodynamic truth. Controller demonstrations are included only when they expose useful flight measurements or model-validation evidence.

## Source map

The collection includes flight-identified X-Cell, Raptor, Yamaha R-50, and smaller commercial-model dynamics; autonomous aerobatics and autorotation; hover rotor-flow PIV; and model-scale ground-effect measurements. Exact platform, rotor diameter, whether data were measured or computed, and study limitations appear in each record. Related papers from one platform or campaign are marked as companion records and are not independent experiments.

Representative queries included `"X-Cell 60" helicopter system identification flight test`, `"T-Rex 450" rotor PIV hover`, `"Raptor 50" flight dynamics identification`, `"Yamaha R-50" helicopter system identification Mettler`, `"miniature helicopter" system identification flight data`, `RC helicopter autorotation measured`, and `model scale helicopter rotor ground effect thrust torque thesis`. Searches covered institutional repositories, NASA NTRS, CMU and MIT publication servers, journal/publisher pages, conference proceedings, and theses. The search was not exhaustive.

## Local files and checks

Third-party originals are local-only and ignored by Git. Public availability does not establish permission to redistribute. No paywall or authentication bypass is used. The repository's [library checker](../../../../../../research/reference-library/catalog.py) validates topic manifests and retained files; run it from the repository root after this manifest is populated. It verifies PDF signatures/text and ZIP integrity without executing code or deserializing data.
