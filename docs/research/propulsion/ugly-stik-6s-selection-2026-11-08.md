# Ugly Stik 6S powertrain selection

2026-11-08 · EL1e-STIK-00 · Research snapshot, not implemented or physically validated.

Execution and acceptance belong to the [two-variant plan](../../plans/ugly-stik-two-variants.md). Repository inspection: `41ce5af6f4a148b4ea101b08883fd4e03878bb07`, with unrelated working-tree changes present. No simulator or hardware measurements were performed for this note.

The plan's second review preserves the existing basic aircraft, ID and tests unchanged; it does not promote the separate finite-fuel 61FX configuration to default. This motor-selection evidence concerns only the added electrical installation.

## Selection

Use **Scorpion SII-4020-540KV + APC Thin Electric 13x8E + 6S 4000 mAh LiPo** as the first electric conversion candidate. The final planning pass selects the pack and ESC references below; actual fit, current and flight qualification remain pending.

Scorpion recommends this motor for 60–64-inch aerobatic aircraft on 6S, with 3500–4000 mAh packs. Its current product page gives 540 rpm/V, 288 g, 85 A maximum continuous current and 1850 W maximum continuous power. The page was available and marked in stock when checked; this is not a local availability or purchasing commitment. [Manufacturer product and specifications](https://www.scorpionsystem.com/catalog/aeroplane/motors_1/sii-40/SII_4020-540/).

### Useful manufacturer bench points

| Propeller | Voltage | Current | Electrical input | Speed | Static thrust |
| --- | --- | --- | --- | --- | --- |
| APC 13x6.5E | 22.2 V | 57.98 A | 1287.2 W | 10,065 rpm | 4.302 kgf |
| APC 13x8E | 22.2 V | 61.44 A | 1364.0 W | 9,953 rpm | 4.332 kgf |

These are manufacturer sample measurements, not OpenRC results. The chart reports testing at 512 ft altitude and warns that higher loaded voltage increases current. Its recommendation to stay within 80% of the motor current rating gives a 68 A screening ceiling; the selected nominal point is below it, but a fully charged 6S pack still needs separate assessment. [Scorpion propeller chart, page 1](https://www.scorpionsystem.com/files/i2,653_data_chart.pdf).

The product lists nominal resistance of 0.020 ohm and no-load current of 1.22 A at 10 V. The sample chart instead identifies measured Kv of 555 and resistance of 0.021 ohm, with voltage-dependent no-load current. Keep nominal specifications and sample-fit parameters separate; verify resistance conventions before importing either into the simulator's DC-equivalent model. [Product specifications](https://www.scorpionsystem.com/catalog/aeroplane/motors_1/sii-40/SII_4020-540/) and [sample chart](https://www.scorpionsystem.com/files/i2,653_data_chart.pdf).

Choosing 13x8E over the product page's larger aerobatic props is an engineering inference: the smaller diameter retains more ground clearance, and the exact combination has a published bench point. The 13x6.5E is a lower-load fallback within the same electric configuration, not a third aircraft. A fallback must pass the same fit/current gates.

## Alternatives considered

| Candidate | Primary evidence | Selection consequence |
| --- | --- | --- |
| E-flite Power 60, **EFLM4060B**, 470 Kv | The manufacturer describes a 6S, .60-class motor up to 1800 W; its manual proposes 17x7E for aerobatics or 16x10E for sport, with an 80 A ESC. [Product](https://www.horizonhobby.com/product/e-flite-power-60-brushless-outrunner-motor-470kv-4mm-bullet/EFLM4060B.html), [specific B-revision manual](https://www.horizonhobby.com/on/demandware.static/-/Sites-horizon-master/default/Manuals/EFLM4060B-Manual.pdf). | Credible alternative, but the published setups use larger propellers. Do not mix this revision with the older Power 60 manual or assume those props fit the Jensen gear. |
| SunnySky X4120-III, **550 Kv** | Manufacturer lists 6S, 293 g, 18.5 milliohm and 14–15-inch EOLO prop suggestions. The current entry labels its current limit with a 30-second duration. [Manufacturer specification and test tables](https://en.rcsunnysky.com/x-fixedwingseries/58.html). | Credible alternative. Preserve the duration and exact EOLO prop identity; neither the headline power nor a same-size APC prop is an interchangeable test result. |

The Scorpion candidate has the strongest convenient evidence here for a relatively small propeller and a motor of this aircraft class. This comparison does not claim that it is the best motor on the market.

## Fit and performance interpretation

The current [Jensen data](../../../app/data/aircraft/jensen_ugly_stik_60.json) specifies 1.524 m span and 0.464515 m² wing area. Its inventory sums to approximately 2.88 kg with prescribed fuel. That is the donor's modeled mass, not the electric conversion's mass or a measured airframe weight.

Use **3.0–3.4 kg ready to fly** as a preliminary conversion envelope, to be replaced by a complete inventory. At 3.4 kg, the selected published point corresponds to approximately **401 W/kg electrical input** and **1.27 static thrust/weight**. These derived screening figures support a strong sport/aerobatic candidate; they do not establish climb rate, unlimited vertical flight, shaft power or endurance.

A 13-inch propeller has a 0.1651 m radius; 16 and 17 inches require 0.2032 and 0.2159 m. The donor's wheel contact coordinates are about 0.25 m below its thrust datum, but stance, suspension compression, pitch, hub placement and terrain reduce usable clearance. Calculate clearance with the actual electric installation and ground model; nominal coordinates alone cannot approve a propeller.

The [APC LP13080E product](https://www.apcprop.com/product/13x8e/) identifies the actual thin-electric prop and dimensions. APC also provides downloadable geometry and performance resources. Its [performance-data guide](https://www.apcprop.com/technical-information/performance-data/) explicitly describes those performance files as computational predictions. Preserve file versions, hashes and provenance; do not label them as wind-tunnel measurements or use a single static thrust point as a complete in-flight `Ct/Cp` map.

## Pack and ESC reference selected during final planning review

Use **Gens ace G-tech GEA406S60X9GT**, 6S 4000 mAh, XT90, as the installation reference. The manufacturer lists approximately **606 g** and **162 × 45 × 37 mm**, with a 60C label. Preserve the approximate nature of those specifications; neither that label nor the advertised capacity supplies a measured resistance/discharge model. Use those dimensions for the bay study and source the physical inventory mass from this exact SKU. [Manufacturer product](https://gensace.de/products/gea406s60x9gt), checked 2026-11-08.

Use **Scorpion Tribunus III 06-80A ESC SBEC** as the hardware reference, not the older non-III unit. Published specifications include 80 A continuous, 11–26.1 V operation, approximately 70 g without connectors, a 32.0 × 52.2 × 20.3 mm body and adjustable 5.1–12.1 V BEC output. Add connectors/wiring mass separately and verify receiver/servo voltage before selecting a BEC setpoint. Its actual firmware behavior is not the simulator's ideal ESC law. [Manufacturer specification](https://www.scorpionsystem.com/catalog/speed_controllers/tribunus_esc/tribunus_III_esc/III_06_80/), checked 2026-11-08.

The existing BAT generator has 6S 2200/5000 mAh class packs, but no 4000 mAh record. Add one sourced installation record using the existing cell-template pipeline; keep its electrical parameters explicitly estimated until matched measurements exist. Override mass, box and their provenance from the selected SKU instead of inheriting Timber-scaled dimensions. Never rename an estimated cell curve into a measured Gens ace characterization. Keep existing cell fits and pack bytes unchanged.

## Inputs still needed

- Verify the selected pack's installation/lead routing, build revision and physical measurements when available. Use ordinary LiPo: 22.2 V nominal and 25.2 V fully charged; characterize sag separately from nameplate specifications.
- Match the selected III-series ESC's firmware/configuration and receiver/servo voltage. The older [Tribunus 06-80A guide](https://www.scorpionsystem.com/files/download/Tribunus06-80.pdf) is historical and must not supply unverified settings for the III-series reference.
- Mount, adapter, propeller/rotor inertia, wiring, cooling, battery restraint and service access; measured or explicitly estimated mass, CG and inertia.
- Matched current/RPM/thrust checks across voltage and throttle, with separate fit and held-out cases. The selected 13x8E point cannot serve both purposes. Source data can support an experimental model before a physical Jensen conversion exists; it cannot close independent physical validation.
- A pack discharge model with voltage sag, depletion and cutoff. Reuse the [BAT pipeline](../../../research/battery/README.md), identifying class estimates honestly until matched pack data exists.

The existing [electric power-stage contract](../../ELECTRIC-PROPULSION-PLAN.md) lacks motor/ESC thermal dynamics, current limiting and electric propwash. Those limits must remain visible in qualification; nameplate limits must not be represented as implemented protection.
