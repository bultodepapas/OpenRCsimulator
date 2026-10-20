# D6-SAV-00 — Savox permission and catalog research

Date: 2026-10-14. Scope: correspondence verification and public source review for the [servo plan](../../../plans/savox-servos.md). No runtime implementation, bench test or physical validation was performed.

## Permission record

The maintainer's Gmail thread **“SAVOX Servo Dynamics × OpenRC Simulator — Technical Collaboration”** contains the original request of 2026-10-13 and Ian Ko's reply from Tricore/Savox dated 2026-10-14. The reply explicitly states:

> You have our permission to use Savox product representations in your project.

It also offers an engineering collaboration contact and an announcement on Savox's official social channels once the servos are added. The original correspondence remains in the maintainer's mailbox; this public record omits addresses, phone numbers, mail headers and unrelated correspondence.

The README acknowledgment is **partner**, reflecting this permission and support. The reply does not report a payment, hardware donation, delivered engineering dataset or manufacturer certification of simulator behavior. Product-representation permission is recorded separately from the project's MIT code license; retain attribution and applicable terms for any third-party files actually incorporated.

## Catalog candidates

Manufacturer pages inspected on 2026-10-14. These are candidate products, not confirmed aircraft installations. Keep the exact Plus revision: `SA-1258TG+` and retail `SA1258TGP`, for example, must not silently inherit specifications from an older non-Plus servo.

| Product / manufacturer source | Comparison point | Published speed | Published torque¹ | Mass | Case dimensions, mm | Candidate role |
| --- | --- | --- | --- | --- | --- | --- |
| [SH-0255MG+](https://www.teamsavox.com/product/sh-0255mgp/) | 6.0 V | 0.13 s/60° | 3.9 kgf·cm | 15.8 g | 22.8 × 12 × 29.4 | Micro/light installation; fit and load qualification required |
| [SA-1258TG+](https://www.teamsavox.com/product/sa-1258tgp/) | 6.0 V | 0.08 s/60° | 12.0 kgf·cm | 64 g | 40.3 × 20.2 × 37.4 | Fast standard airplane candidate |
| [SA-1230SG+](https://www.teamsavox.com/product/sa-1230sgp/) | 6.0 V | 0.16 s/60° | 36.0 kgf·cm | 79 g | 40.3 × 20.2 × 44.9 | Higher torque, heavier and taller airplane candidate |
| [SB-2270SG+](https://www.teamsavox.com/product/sb-2270sgp/) | 7.4 V / 8.4 V | 0.12 / 0.11 s/60° | 40.0 / 45.0 kgf·cm | 74 g | 40.3 × 20.2 × 38.7 | Brushless HV candidate; separate supply qualification |

¹ The manufacturer labels the torque field `kg/cm`; the table interprets this conventional servo rating as kgf·cm, not mass divided by length. Preserve that original label in import provenance and confirm the interpretation during catalog intake. Conversion: 1 kgf·cm = 0.0980665 N·m. Published speed/torque points do not establish continuous torque, loaded transient response or a complete motor curve.

At 6.0 V, SA-1258TG+ has half the quoted transit time of SA-1230SG+, while SA-1230SG+ adds 15 g and 7.5 mm case height. These are catalog-derived comparisons at equal voltage, not measured improvements to an aircraft. The micro product's lower weight does not establish adequate torque or mounting compatibility.

## Price evidence and limitations

Price belongs to a seller, market, currency and observation date, not the physics model. A live [Servos.net micro-airplane listing](https://servos.net/collections/micro-airplane) inspected on this date displayed SH0255MGP at **USD 34.99**, marked sold out.

Search-index copies of regional Savox USA listings exposed the following older advertised prices. Direct retrieval of the corresponding pages failed or changed, so these are **historical planning references, not verified current quotes**:

| Product | Indexed advertised USD price | Source |
| --- | --- | --- |
| SA1258TGP | 98.99 | [Standard airplane listing](https://www.savoxusa.com/collections/standard-airplane) |
| SA1230SGP | 103.39 | [Product listing](https://www.savoxusa.com/products/savsa1230sgp-coreless-digital-servo-0-16sec) |
| SB2270SGP | 134.19 | [Product listing](https://www.savoxusa.com/products/savsb2270sgp-high-voltage-brushless-digital) |

Refresh prices from a reachable seller before publishing selectable catalog prices. These observations do not establish current stock, MSRP, a Colombian retail price, shipping or tax. Never merge an older regional price into a manufacturer specification or substitute zero for an unknown price.

## Intake issues and available assets

- SB-2270SG+ has conflicting 6.0 V torque values: Team Savox shows 30.0, while the indexed regional product listing shows 25.0 kgf·cm. Retain both sources and leave that voltage/torque datum unresolved until confirmed; do not average them or silently choose one.
- The manufacturer SH-0255MG+ page shows 15.8 g, while some regional Plus sheets round to 16 g. Preserve source/revision and confirm the mass convention, including cable/horn inclusion, before claiming a measured installed mass.
- The manufacturer product pages expose PDF and **3D Data** links. Inspect and reuse suitable available files before creating custom geometry. The SA-1258TG+ 3D link could not be retrieved through the browsing tool in this review; no model was downloaded or redistributed.
- Requestable engineering evidence includes shaft-angle/time traces at stated voltage/load, current, centering/deadband, backlash, signal configuration and mounting dimensions. The offered engineering contact makes this a follow-up opportunity; those data have not yet been received.

The repository already has shared rate-limit arithmetic and a Workshop variant pipeline. Its [aircraft contract](../../../AIRCRAFT_CONTRACT.md) explicitly distinguishes three logical servo states from independent hardware. The [active plan](../../../plans/savox-servos.md) owns the implementation sequence and acceptance gates.
