# CR-28 — Parts prices, crash assessment and Stik loss examples

**Research date:** 2026-10-15, America/Bogota. **Status:** planning evidence and initial data only. Serves the [CR-28…38 implementation plan](../../../plans/crash-damage-economics.md). No new crash physics, repair calculator or on-screen cost is implemented by this research.

## Artifacts and evidence scope

| Artifact | Role |
| --- | --- |
| [catalog.json](../../../../research/crash-economics/catalog.json) | Generated reusable USD catalog: 32 product identities and 34 observations, including two independently collected duplicate product offers. Do not sum offers. |
| [Component sources](../../../../research/crash-economics/price-research-components.json), [fleet sources](../../../../research/crash-economics/price-research-fleet.json) | Authored price observations with exact URL/SKU, package notes, stock and source-quality caveats. |
| [aircraft-costing.json](../../../../research/crash-economics/aircraft-costing.json) | Authored baseline BOM, explicit allowances, physical inventory coverage, fleet status and unpriced requirements. |
| [worked-examples.json](../../../../research/crash-economics/worked-examples.json) | Generated cent-exact example calculations and source identities. Not outcomes from simulated crash tests. |
| [build_catalog.py](../../../../research/crash-economics/build_catalog.py) | Standard-library-only normalizer, coverage validator and example generator. No downloads or purchases. |

Prices are listings retrieved during this review, excluding modeled tax/shipping; pages may be cached, out of stock, discounted or inconsistent. Observation date is not a guarantee that the seller refreshed its content that day. Current availability and any complete-build quotation remain separate questions. Cached/unconfirmed entries are retained as such, not promoted to available offers. Exact products, price proxies and unsourced planning allowances are distinct.

## 1. Price seed in USD

Amounts below are per sold unit or explicitly named package. Read the linked source and JSON caveats before interpreting compatibility. Commercial listing prices are evidence of market cost, never of failure strength or a salvage probability.

| Item | USD | Observation and applicability |
| --- | ---: | --- |
| [APC 12×6 Sport, LP12060](https://www.apcprop.com/product/12x6/) | 5.39 | Manufacturer listing, add-to-cart control; exact baseline physical propeller. |
| [APC 11×7 Sport, LP11070](https://www.apcprop.com/product/11x7/) | 4.44 | Comparison size, not baseline hardware. |
| [SAVOX SC-0252MG+, SAVSC0252MGP](https://www.adrenalinercracing.com/products/savox-sc-0252mg-standard-digital-metal-gear-servo) | 33.99 | Sale, comparison $43.99; only two units shown. Catalog application includes CAR; no qualified Stik installation. |
| [SAVOX SC-0254MG+, SC0254MGP](https://nitrohobbies.com/sc0254mgp/) | 34.99 | Retail listing, out of stock. |
| [SAVOX SA-1258TG+, SA1258TGP](https://nitrohobbies.com/sa1258tgp/) | 98.99 | Retail listing, out of stock; one existing D6-SAV airplane candidate. |
| [SAVOX SA-1230SG+, SA1230SGP](https://www.servocity.com/sa1230sg-coreless-digital-servo/) | 103.39 | Retail listing, stock not explicit; another D6-SAV candidate. |
| [SAVOX SH-0255MG+, SAVSH0255MGP](https://www.rcsuperstore.com/savox-sh-0255-micro-digital-mg-servo-w-soft-start-13-54-6v/) | 40.99 | Micro servo; stock unclear, retrieved listing had a two-week crawl age. |
| [SAVOX SB-2270SG+, SB2270SGP](https://nitrohobbies.com/categories/radio-accessories/servos-accessories/servos/standard/) | 134.19 | Category quote; 6.0–8.4 V candidate, not a baseline 4.8 V replacement or jet certification. |
| [SAVOX SC0254 gear set, SGSC0254MG](https://www.savoxusa.com/collections/replacement-parts/servos-gear-set?page=5) | 12.99 | Cached manufacturer listing; Plus-version fit and stock unverified. |
| [SAVOX SA1258 gear set, SGSA1258TG](https://www.savoxusa.com/collections/all/servos-gear-set) | 32.99 | Cached manufacturer listing; same revision/availability caveat. |
| [Hitec HS-311, HRC31311S](https://www.towerhobbies.com/product/hs-311-standard-analog-sport-servo/HRC31311S.html) | 16.99 | In-stock standard analog reference. Source quantity four is an example installation, not a four-pack price. |
| [O.S. MAX-55AX + muffler, OSMG0557](https://www.horizonhobby.com/product/55ax-abl-.55-airplane-glow-engine-with-muffler/OSMG0557.html) | 249.99 | November backorder. Exact 55AX product; only a cost proxy for the baseline MAX-61FX. |
| [O.S. MAX-65AX + muffler, OSMG0558](https://www.horizonhobby.com/product/65ax-abl-.65-airplane-glow-engine-with-muffler/OSMG0558.html) | 294.99 provisional | Category quote conflicts with older $259.99/backorder detail snapshot. Refresh before use; no silent preferred-price selection. |
| [O.S. FS-64V + F-4051 silencer, OSMG901](https://www.horizonhobby.com/product/os-engines-o.s.-fs-64v-61t2-with-f-4051-silencer/OSMG901.html) | 549.99 | Listed in stock; matches engine family of the four-stroke Stik variant. |
| [O.S. FS-95V, OSMG0900](https://www.horizonhobby.com/product/fs-95v-ringed-4-stroke-.95-airplane-glow-engine/OSMG0900.html) | 484.99 | November backorder; separate .95-class reference, not interchangeable with .64. |
| [Spektrum AR8360T+, SPM-1033](https://www.horizonhobby.com/product/ar8360t-dsmx-8-channel-as3x-and-safe-telemetry-receiver/SPM-1033.html) | 99.99 | In-stock DSMX-family receiver; transmitter/installation compatibility still required. |
| [Futaba R7208SB](https://futabausa.com/product/r7208sb/) | 214.99 | In-stock FASSTest/S.Bus2 reference. |
| [FrSky Archer Plus R10+](https://frskyna.com/collections/receivers/products/frsky-access-archer-plus-r10-receiver) | 44.99 | Sold out; ACCESS/ACCST D16 family. |
| [RadioMaster ER8 ELRS](https://radiomasterrc.com/products/er8-2-4ghz-elrs-pwm-receiver) | 34.99 | Add-to-cart listing; ExpressLRS hardware required. |
| [MonoKote black roll, TOPQ-0208](https://brodak.com/finishing-products/silkspan-silk-covering/monokote-covering-orange-2.html) | 24.99 provisional | Indexed retailer quote, direct retrieval blocked; roll dimensions unverified. URL name and listing color differ; SKU/color need recheck. |
| [Trim MonoKote red sheet, TOPQ4101](https://www.horizonhobby.com/product/trim-monokote-missile-red/TOPQ4101.html) | 4.99 historical | 5×36 in adhesive-backed trim sheet; stale five-month snapshot, out of stock. Different material from heat-shrink roll. |
| [Hangar 9 Ultra Stick 10cc ARF, HAN2345](https://www.horizonhobby.com/product/ultra-stick-10cc-arf-60/HAN2345.html) | 279.99 | Backorder; modern 60 in airframe reference. Requires electronics/powerplant and a different servo topology. Not a complete Jensen. |
| [JetCat P100-RX-BL package](https://www.chiefrc.com/products/p100-rx-bl-turbine-engine-with-brushless-pump-22-5-lbs-thrust-from-jetcat) | 2,649.00 | Backorder; 100 N class, pump/starter/ECU included, battery separate. Cost analogue for older P100-RX. |
| [JP Hobby ER-150 Avanti retract/brake set](https://www.tmhobby.com/jp-hobby-er-150-control-box-v1-v2-electric-retract-landing-gear-set-for-sebart-2-0m-avanti-s-2-1m-avanti-s-fc-airplane.html) | 780.00 | Listed set: mains, nose gear, brake wheels and controller; exact A200 installation fit unverified. |
| [Turbo Timber Evolution PNP, EFL105275B](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-pnp-includes-floats/EFL105275B.html) | 299.99 | Airframe, motor/ESC and six servos; receiver/flight battery separate. Reference for the fictional Timber. |
| [Turbo Timber Evolution BNF, EFL105250B](https://www.hubhobby.com/e-flite-efl105250b-turbo-timber-evolution-15m-bnf.html) | 349.99 | Alternative package including receiver; battery/charger/transmitter separate. |
| [Timber wing, EFL105252](https://www.horizonhobby.com/product/wing-turbo-timber-evolution-1.5m/EFL105252.html) | 59.99 | Servos excluded. |
| [Timber updated gear, EFL-1249](https://www.horizonhobby.com/product/e-flite-complete-updated-landing-gear-set-with-heavy-duty-springs-turbo-timber-evolution-1.5m/EFL-1249.html) | 16.99 | Fixed gear replacement; not a retract set. |
| [Spektrum 4S 3200 mAh pack, SPMX324S50](https://www.horizonhobby.com/product/spektrum-accessories-14.8v-3200mah-4s-50c-smart-g2-lipo-battery-ic3/SPMX324S50.html) | 69.99 | Separate battery reference; connector, mass and installation still matter. |
| [CARF P-51 1:4.3 ARF, 422000](https://carf-models.com/en/products/p-51-mustang/id/130/region/2) | 2,410.00 | Scale-class comparison, not the simulated 2.82 m airframe; listed 50–85 cc range does not establish DA-120 fit. |
| [Desert Aircraft DA-120](https://www.desertaircraft.com/products/da-120) | 1,249.00 | Same engine model as simulated P-51; sold out, uncertain dated restock text. |
| [Flex Extra 300 60E Pro](https://flexinnovations.com/product/extra-300-60e-pro/) | from 449.99 | Variant price ambiguous and expected restock; electric comparison only, not a GP Extra .60 glow quote. |

SAVOX manufacturer storefront snippets were often several months old or inaccessible. The JSON preserves those alternate prices and retrieval limits; the primary servo amounts above use identified retailer offers when available. The [existing partnership record](../../servos/D6-SAV-00/README.md) supports product representation and proposed collaboration. It does not establish supplied measurements or manufacturer validation. No partnership is asserted for the other brands.

## 2. What does a complete Ugly Stik cost?

No verified current fully assembled offer for the exact historical Jensen/61FX/four-servo configuration was found. The $279.99 Ultra Stick is an **ARF reference**, not a ready-to-fly price. The historical Jensen, modern Hangar 9 airframe, electric PNP Sticks and used private-sale models are not interchangeable valuations.

Use this **reconstructed replacement-value scenario** until the exact build has a quote. It is not a shopping list: the engine is backordered, the quoted SAVOX seller had only two units, and installation compatibility remains unqualified.

| Valued group | USD | Basis |
| --- | ---: | --- |
| Covered built airframe, fixed gear, tank, mount, spinner and hardware | 350.00 | Estimated inclusive allowance: $279.99 ARF reference + $70.01 for construction/installation differences. Never add the ARF again. |
| Engine and muffler | 249.99 | O.S. 55AX package price proxy for MAX-61FX/E-4010. No actual hardware swap. |
| Four physical servos | 135.96 | 4×$33.99 SAVOX unit price proxy; three fuselage units and one central aileron unit. Not a qualified or in-stock set. |
| Receiver | 99.99 | Spektrum product price proxy for generic installed receiver. |
| APC 12×6 | 5.39 | Exact physical product. |
| 4.8 V 600 mAh NiMH receiver pack | 25.00 | Unsourced allowance, $20–35 planning range. |
| Fuel currently onboard | 3.00 | Assumed 150 ml at $20/litre, not a measured retail quote. |
| Final equipment assembly/commissioning | 125.00 | Assumed 5 h at $25/h; excludes airframe construction already covered above. |
| **Complete assembled-build value** | **994.33** | **Estimated, before tax/shipping; roughly $830–1,330 under the recorded planning ranges.** |
| DIY cash basis | **869.33** | Omits the $125 labor allowance; time is still required. |

The exact generated range is $827.34–$1,331.34, obtained by summing the authored low/high allowances. It is a sensitivity envelope, not a statistical confidence interval or observed price distribution. Do not display those cents as a claim of market accuracy. All 20 baseline inventory entries are covered once: 19 purchasable groups/items and the explicitly nonpurchasable virtual balancing mass. The latter stays in the physical energy calculation.

## 3. Worked accident calculations

### Direct trunk impact at 150 km/h

From the current [physical inventory](../../../../app/data/aircraft/jensen_ugly_stik_60.json), including its virtual balancing mass:

```text
m = 2.8850582910437526 kg
v = 150 / 3.6 = 41.6666667 m/s
K_translation = 0.5*m*v² = 2504.3909 J ≈ 2.50 kJ
```

This is incident translational energy, not energy absorbed by the wood or an experimentally proven failure load. Define the acceptance scenario as a near-normal nose/CG strike against a substantial trunk, followed by the actual secondary impact; exclude glancing foliage from that scenario. With provisional modeling, near-total structural loss is the intended benchmark. Rotation, contact arm, trunk compliance, crush distance, mount failures and residual motion still determine damage allocation. For illustration only, a complete stop over 0.10 m corresponds to roughly 25 kN average resisting force; the distance is assumed, so this is not a peak-force prediction.

The current whole-mass central-impact estimate using its 0.8 tree transfer would be about 694 J/kg, above the uncalibrated 150 J/kg C4 cut. That is a consistency comparison, **not** validation of C4 strength or a substitute for the planned component model.

### Salvage reduces replacement loss

On the same hypothetical $994.33 valuation basis, assuming the structure is beyond repair and no other equipment is recovered:

| Conditional assessment | Reuse credit | Net replacement loss |
| --- | ---: | ---: |
| No serviceable recovered servos | $0.00 | **$994.33** |
| Two servos pass the simulated inspection | $67.98 | **$926.35** |
| Four servos pass the simulated inspection | $135.96 | **$858.37** |

These are arithmetic fixtures using the same proxy unit value on both sides of the ledger, not predictions that the real/generic servos survive a 150 km/h impact, and not proof that SAVOX units are installed. Inspection/refit is assumed inside the example's commissioning allowance; additional real service fees are unresolved. Until inspection and thermal aftermath resolve, show the credit as pending. If a complete new BNF package is bought instead of rebuilding around recovered servos, use residual resale value rather than this avoided-purchase credit.

### Small incidents and expensive systems

- **Stik prop-only strike:** $5.39 parts value; full repair total remains unknown until shaft/mount condition, inspection and labor are assessed. A broken prop does not automatically destroy a $250–550 engine.
- **Covering-only hole:** example 1×1 in tear, 0.5 in overlap each side and 25% waste consumes 5 in² of a 180 in² trim sheet. At the historical $4.99 sheet price, consumption rounds to $0.14. Assumed 15 min at $25/h adds $6.25: **$6.39 consumed-material basis**, or **$11.24 cash outlay** if an entire sheet must be bought. This is an illustrative unqualified recipe using a stale/out-of-stock item, not a currently purchasable or structurally certified repair.
- **Timber fixed gear versus jet retracts:** reference parts are $16.99 versus $780 for the complete jet retract/brake package. A damaged jet leg should use a sourced single-leg/repair-kit option when available; $780 is not automatically the charge for every hard landing.
- **Electric total replacement reference:** the listed BNF Timber plus the listed 4S pack totals **$419.98**, before tax/shipping/assembly. This is a commercial comparison, not a complete valuation of the fictional simulated configuration; do not add its included motor, ESC, servos or receiver again.
- **Turbine fire:** a $2,649 turbine package and $780 retract package already represent substantial separate exposures. Neither alone is a complete jet price. Fire damages only components receiving sufficient modeled exposure; remote recovered electronics remain candidates, pending inspection. No full jet total is asserted while its airframe/electronics BOM is incomplete.

## 4. Physics and manufacturer evidence

| Source | Supported conclusion | Limit |
| --- | --- | --- |
| [O.S. GF30 manufacturer manual](https://www.os-engines.co.jp/english/line_up/engine/air/single/img/manual/3A010.pdf) | Propellers with visible damage or a strong impact should not be reused. Supports replace/inspect treatment instead of a cosmetic repaired-prop option. | Another engine's operating manual; no MAX-61FX impact-strength, bearing-load or survival curve. |
| [APC safety engineering discussion](https://www.apcprop.com/technical-information/safety-concerns/) | Propeller loads include rotation, aerodynamics, torsional acceleration and vibration, with important unknowns. | Catalog geometry/price cannot establish crash strength. |
| [Horizon/E-flite LiPo guidance](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/EFL-LiPoSafetyWarnings.pdf) | Damaged packs/leads should not be returned to use; ignition can be delayed after damage/shorting. | Historical guidance, not a current handling procedure or a calibrated ignition-time distribution. No universal 5–30 s model follows from it. |
| [US Coast Guard alternative-fuels guide](https://www.dco.uscg.mil/Portals/9/DCO%20Documents/5p/LGCNCOE/docs/RDC%20Operational%20Guide%20for%20Response%20to%20Alternative%20Fuels%20Incidents%20QRC%202025-0409a.pdf?ver=Q_VkA32lddf5HarRF-32UA%3D%3D) | Indexed official guide identifies methanol's low-visibility flame and ignition hazard. | Direct PDF retrieval failed in this review; indexed evidence and the prior CR-22b review support the narrow conclusion, not RC blend burn rates. |
| [NASA battery workshop source library](https://www.nasa.gov/nasa-aerospace-battery-workshop/) | Primary work covers mechanical/thermal abuse, state of charge, geometry and propagation. | Research agenda for later calibration; no cell-specific result transferred to the Timber pack here. |
| [Existing CR-22b source audit](../CR-22b/research.md) | Identifies energy-source presentation and gaps, including AMA turbine guidance. | Current visual timing/fire classes are estimates. A faint glow-fuel flame does not justify zero thermal damage. |

The effective-mass, kinetic-energy, friction-work and heat-balance equations in the plan are reduced-model mechanics/energy balances. Material/joint capacities, absorption fractions, salvage pass rates and thermal thresholds remain unmeasured for this fleet. No reviewed source establishes that every full-speed crash destroys every servo, that a slow crash is safe for a LiPo, or that an expensive part is more impact-resistant.

## 5. Verification and next evidence

From repository root:

```powershell
python research/crash-economics/build_catalog.py
python research/crash-economics/build_catalog.py --check
git diff --check
```

The generator validates unique observation IDs, HTTPS sources, explicit date, integer cents, all baseline inventory bindings/exclusions exactly once, fleet coverage against the current catalog, offer references, example totals and generated freshness. It preserves source hashes and does not edit physical aircraft data. Source offers are authored evidence; regenerate the output rather than hand-editing it. The validator is for this seed, not the future CR-29 runtime schema.

Verification on 2026-10-15 passed: generation and `--check`, 32 products/34 observations, all 20 baseline inventory entries, all nine current catalog routes (eight airplanes and one helicopter), Python syntax, local file links in the plan/evidence/contract/navigation, and `git diff --check`. The exact-product and compatibility limitations above remain open despite these software checks.

The planning review checks package-versus-part duplication, four physical versus three logical Stik servos, assembled-versus-ARF meaning, normal versus tangential energy, coupled/secondary contact budgeting and proxy-versus-actual salvage. JSON/Markdown checks do not establish physical crash validity. No Godot flight suite is needed for this documentation/research-only change; runtime implementation must pass the plan's owning-track gates.

Next evidence: exact Jensen/61FX build valuation; compatible identified SAVOX installation through D6-SAV; NiMH/fuel/labor quotes; balsa/ply joints and retract mount limits; servo and engine inspection/repair quotes; complete matched P-51/Avanti/Extra BOMs; and component-specific LiPo/thermal data. Missing fleet totals are deliberately `null`, not fabricated zero-cost aircraft. The helicopter keeps its physical X-Cell identity separate from HX-700 visuals.
