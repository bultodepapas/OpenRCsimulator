# CR-36c electric pricing evidence

Observed 2026-10-15 in USD from direct Horizon Hobby US product listings. This dossier values the fictional turbo-lumber-evolution model using current commercial products as price proxies; it does not establish that the fictional build contains those exact products.

The physical source is app/data/aircraft/turbo_lumber_evolution.json, SHA-256 61b0e5329732a8cabaf2deef11e9c297d8e745bb724370348609909b03c8e1ee. The hash is pinned in the independent fleet intake. The source has 12 physical inventory rows and one virtual balancing reference. ballast_reference is not hardware and is not costed.

## Observed offers

| Offer | Price | Availability on 2026-10-15 | Coverage decision |
|---|---:|---|---|
| [PNP EFL105275B](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-pnp-includes-floats/EFL105275B.html) | $299.99 | In stock | Complete-aircraft alternative; includes airframe, six servos, motor, 70 A ESC, slats and floats; no receiver, battery, transmitter or charger. |
| [BNF Basic EFL105250B](https://www.horizonhobby.com/product/e-flite-turbo-timber-evolution-1.5m-bnf-basic-includes-floats/EFL105250B.html) | $349.99 | In stock | Alternative package; includes the PNP equipment plus one AR637TA receiver; no transmitter, battery or charger. |
| [Replacement wing EFL105252](https://www.horizonhobby.com/product/wing-turbo-timber-evolution-1.5m/EFL105252.html) | $59.99 | In stock | Partial candidate only; servos explicitly excluded, and modeled wing row also includes flaps and ailerons. |
| [Updated landing gear EFL-1249](https://www.horizonhobby.com/product/e-flite-complete-updated-landing-gear-set-with-heavy-duty-springs-turbo-timber-evolution-1.5m/EFL-1249.html) | $16.99 | In stock | Compatibility is listed; contents do not verify the whole main-gear-and-wheels group or tailwheel assembly. |
| [4S 3200mAh battery SPMX324S50](https://www.horizonhobby.com/product/14.8v-3200mah-4s-50c-smart-g2-lipo-battery-ic3/SPMX324S50.html) | $69.99 | Backorder, estimated October 2026 | Capacity-class price proxy for battery_main; the newer Smart G2/50C identity is not established in the fictional build. |
| [800Kv motor SPM-1012](https://www.horizonhobby.com/product/spektrum-avian-2815-800kv-brushless-outrunner-motor/SPM-1012.html) | $74.99 | In stock | Proxy for motor_main; exact installed motor is unknown. |
| [70 A ESC SPMXAE70E](https://www.horizonhobby.com/product/spektrum-avian-70-amp-smart-lite-brushless-esc-3s-6s-ic3-ver.-e/SPMXAE70E.html) | $74.99 | In stock | Proxy for esc_main; exact installed SKU and connector revision are unknown. |
| [9g servo SPMSA370](https://www.horizonhobby.com/product/a370-digital-9g-metal-gear-aircraft-servo/SPMSA370.html) | $13.99 each | Backorder, estimated October 2026 | Proxy for two tail_servos; does not price wing servos. |
| [AR637T+ receiver SPM-1032](https://www.horizonhobby.com/product/ar637t-dsmx-6-channel-as3x-and-safe-telemetry-receiver/SPM-1032.html) | $84.99 | In stock | Generic receiver price proxy; PNP has none, and BNF includes the older AR637TA. |
| [3-blade propeller EFL5962](https://www.horizonhobby.com/product/3-blade-propeller-11-x-7.3/EFL5962.html) | $7.99 | In stock | One propeller only; no price assigned to the combined propeller-and-spinner row. |
| [Spinner EFL17553](https://www.horizonhobby.com/product/spinner-turbo-timber/EFL17553.html) | $8.99 | In stock | One spinner only; no price assigned to the combined propeller-and-spinner row. |
| [Fuselage EFL105251](https://www.horizonhobby.com/product/fuselage-turbo-timber-evolution-1.5m/EFL105251.html) | $54.99 | In stock | Canopy and fittings coverage not confirmed; no price attached to the complete fuselage_main row. |
| [Horizontal stabilizer EFL5259](https://www.horizonhobby.com/product/horizontal-stabilizer-with-tube-timber/EFL5259.html) | $19.99 | In stock | Does not include the vertical tail; no price attached to tail_surfaces. |
| [LED controller EFLA521](https://www.horizonhobby.com/product/led-controller-timber/EFLA521.html) | $13.99 | In stock | Controller alone does not price wiring and navigation LEDs. |

## Inventory valuation

Five rows have attached price_proxy offers: 800Kv motor ($74.99), 70 A ESC ($74.99), receiver ($84.99), two tail servos ($27.98), and 4S 3200mAh battery ($69.99). Their candidate subtotal is $332.94 (33,294 cents), before tax or shipping. This is not a complete aircraft or replacement total. replacement_total_minor remains null.

Seven physical rows remain unpriced:

| Physical inventory row | Why it remains null |
|---|---|
| wing_main | Wing assembly excludes servos and does not demonstrate coverage for all modeled wing parts. |
| fuselage_main | Fuselage listing does not verify canopy and fittings. |
| tail_surfaces | Horizontal stabilizer listing does not include the vertical tail. |
| gear_main | Gear set contents do not confirm main gear and wheels together. |
| gear_tail | No complete tailwheel-and-fork quote verified. |
| propeller_main | Physical row combines propeller and spinner; separate prices cannot value the whole group without an unsupported split. |
| wiring_lighting | LED controller does not include the modeled wiring and navigation LEDs. |

The source also has ballast_reference, a virtual balancing mass. It is excluded from physical-inventory coverage and has no price. No labor, foam repair recipe or whole-aircraft replacement valuation was substantiated.

## Package and binding rules

PNP and BNF are alternative purchase packages. Never add either aircraft-package price to the standalone parts, and never sum PNP and BNF. The PNP package includes motor, ESC and servos; BNF adds a receiver. The standalone line values above are separate price proxies for a component-built reconstruction, not an extra shopping list on top of either package. Battery, transmitter and charger are separately needed for both packages.

The modeled propeller_main inventory row contains both a three-blade propeller and spinner. The observed EFL5962 and EFL17553 products are separate one-part listings, so neither is assigned to that group. propeller_component_id and propeller_inspection_ids are empty: a propeller strike cannot be linked to a priced whole-group component until a combined coverage decision is supported. Contact mappings cover only obvious wing, tail and landing-gear inventory groups; propeller, spinner and coarse belly probes remain unmapped.

The intake uses new _horizon_20261015 observation IDs. Preserve the existing legacy observation IDs and records in price-research-fleet.json; integrate these as dated observations rather than overwriting their provenance. In particular, this capture uses Horizon's direct BNF page rather than the existing Hub Hobby source and records the battery as backorder, not in stock. Recheck the source hash before integration. Keep the seven null inventory rows and the null replacement total.
