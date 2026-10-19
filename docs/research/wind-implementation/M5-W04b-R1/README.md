# Windsock construction and behavior: primary-source notes

**2026-10-19 · M5-W04b-R1 · Targeted source review**

This note records airport windsock construction and behavior from FAA and ICAO sources. It informs visual implementation; it is not a wind-tunnel study or validation of the simulator's windsock dynamics.

## Source-backed facts

- The FAA lists [AC 150/5345-27F](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1040591) as active, issued 2021-12-15. The [AC PDF](https://www.faa.gov/documentLibrary/media/Advisory_Circular/150-5345-27F-Wind-Cone.pdf) describes airport/heliport fabric wind-cone assemblies. The AC is advisory; its applicability section says it is generally voluntary, with specified federal grant and Passenger Facility Charge project exceptions.
- The sock is a fabric truncated cone. The FAA's two nominal sizes are 2.5 m long with a 0.45 m throat, and 3.75 m long with a 0.9 m throat. The throat framework holds the opening round in calm air and supports the first 3/8 of the sock length rigidly. The sock and its frame act together as a wind vane and rotate around a vertical shaft; the bearing/bushing must permit free movement.
- The FAA spec says to taper the cone so it becomes fully extended at 15 kt (about 7.72 m/s). At 3 kt (about 1.54 m/s) or above, the assembly should rotate freely and indicate true wind direction within ±5°. The 3 kt value is a movement/direction criterion, not a stated inflation threshold.
- The FAA's [AIM guidance on airport visual indicators](https://www.faa.gov/air_traffic/publications/atpubs/AIM/aim0403.html) says the large end points into the wind. Its [TAF wind convention](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap7_section_1.html) states, for example, that `18010KT` means wind blowing from 180°. Therefore a sock's throat faces the meteorological “from” direction and its tapered body trails toward the “to” direction.
- ICAO's [Annex 14, Volume I catalogue](https://store.icao.int/en/annex-14-aerodromes) lists the 9th edition (July 2022) with Amendment 18. An official [ICAO AP-ADO/TF/7 working paper](https://www.icao.int/sites/default/files/APAC/Meetings/2026/2026%20AP-ADO-TF-7/03-Working%20Papers/WP16-AI5-Development-of-Guidance-Material-on-the-Use-of-As-Far-As-Practicable-AFAP-Rev.1-A.pdf) reproduces Annex 14, 5.1.1.3: an aerodrome indicator should be a fabric truncated cone, at least 3.6 m long and 0.9 m across the large end, visible from 300 m, and provide a clear surface-wind direction plus a general speed indication. It prefers a single white or orange color where practical. If two colors are needed for changing backgrounds, it recommends orange/white, red/white, or black/white in five alternating bands, with darker end bands. That paper is a regional guidance proposal which reproduces the clause, not an Annex amendment.
- FAA fabric colors are natural white, yellow, or orange; its AC prohibits lettering and logos. ICAO's visibility guidance is background-dependent, rather than requiring stripes on every sock.

## Implementation implications and evidence boundary

Use the incoming horizontal air-flow direction for azimuth: the large throat faces upstream and the cloth trails downstream. Preserve the rigid circular throat and supported first 3/8 while allowing the remaining fabric to droop or extend. The 3 kt and 15 kt points are useful anchors if a visual estimate is needed between a limp sock and a fully extended one.

The cited documents do **not** give a calibrated partial-extension curve, throat/tail radius profile, material mass or stiffness, flutter amplitude, damping, or response time. Any interpolation between calm and 15 kt, body curvature, sag, gust lag, or fabric motion beyond those construction constraints is an implementation estimate. Do not describe those choices as measured or physically validated. The real-airport dimensions are reference sizes, not a compliance claim for this RC field.

## Primary sources

- FAA, [AC 150/5345-27F status page](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1040591) and [full PDF](https://www.faa.gov/documentLibrary/media/Advisory_Circular/150-5345-27F-Wind-Cone.pdf), especially §§1.1–1.2, 3.2–3.5, and 4.2.4–4.2.6.
- FAA, [AIM §4-3-4, Visual Indicators at Airports Without an Operating Control Tower](https://www.faa.gov/air_traffic/publications/atpubs/AIM/aim0403.html).
- FAA, [AIM Chapter 7 §1, TAF wind encoding](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap7_section_1.html).
- ICAO, [Annex 14, Volume I current catalogue entry](https://store.icao.int/en/annex-14-aerodromes); [AP-ADO/TF/7 WP/16, Attachment D](https://www.icao.int/sites/default/files/APAC/Meetings/2026/2026%20AP-ADO-TF-7/03-Working%20Papers/WP16-AI5-Development-of-Guidance-Material-on-the-Use-of-As-Far-As-Practicable-AFAP-Rev.1-A.pdf), reproduced clause 5.1.1.3.
