# Brand assets

Original SVG/PNG files under `assets/brands/` are unchanged copies from official brand downloads. Savox WebP display derivatives are described below. All marks remain the property of their respective owners and are not covered by the simulator's MIT code license.

## OpenAI

The OpenAI wordmark and Blossom SVGs came from the official [OpenAI logo package](https://cdn.openai.com/brand/openai-logos.zip), linked by the [OpenAI Design Guidelines](https://openai.com/brand/). The files are provided in black and white so a panel can use the original variant with suitable contrast.

| File | Mark |
| --- | --- |
| `assets/brands/openai/OAI_OpenAI_Wordmark_Black.svg` | OpenAI wordmark, black |
| `assets/brands/openai/OAI_OpenAI_Wordmark_White.svg` | OpenAI wordmark, white |
| `assets/brands/openai/OAI_OpenAI-Blossom_Black.svg` | OpenAI Blossom, black |
| `assets/brands/openai/OAI_OpenAI-Blossom_White.svg` | OpenAI Blossom, white |

The current project [README](../README.md) says OpenAI provides a ChatGPT Pro subscription in support of the maintainer's open-source projects, including OpenRC Simulator, and identifies Codex by OpenAI as an AI development contributor. Keep that attribution within this scope. OpenAI owns its name, logos, product names and other marks. Use the files as supplied, preserve clear space, and do not combine the primary wordmark with the Blossom. OpenAI's guidelines also say co-branded materials require approval from both brands and prohibit implying endorsement or confusing users about sponsorship.

No separate ChatGPT or Codex product icon was included in the official OpenAI logo package, so none is bundled here.

The website uses the official OpenAI Blossom beside the ChatGPT product name. Codex is credited by name, without inventing a product mark. Product names link to their official pages. The main sponsor credit describes the subscription support rather than manufacturer certification of this simulator.

## Savox

The Savox PNGs came from the official [Savox Logos Package](https://www.teamsavox.com/TeamSavox-Logos-Package.zip), linked on the [Team Savox Download Page](https://www.teamsavox.com/download/). The color variant was downloaded again on 2026-10-24.

| File | Mark |
| --- | --- |
| `assets/brands/savox/TeamSavox-Logo-Mono-Black.png` | SAVOX wordmark, black |
| `assets/brands/savox/TeamSavox-Logo-Mono-White.png` | SAVOX wordmark, white |
| `assets/brands/savox/TeamSavox-Logo-LightBG.png` | SAVOX wordmark, orange and black for light backgrounds |

The README and website use `TeamSavox-Logo-LightBG.webp` on white tiles. `python site/prepare_assets.py --brands-only` crops excess transparent canvas while retaining 5% horizontal and 18% vertical clear space around the visible mark, then resizes to 768×171 with Pillow 12.3.0 and lossless WebP encoding. The official PNGs remain unchanged. This makes Savox visually comparable in scale with the neighboring logos on desktop and mobile.

The project [README](../README.md#partners) records Savox's authorization to include representations of its products in OpenRC Simulator. The permission record in [D6-SAV-00](../docs/research/servos/D6-SAV-00/README.md) quotes the manufacturer's scope: “You have our permission to use Savox product representations in your project.” Keep the partner acknowledgment within that scope; do not imply manufacturer certification of simulator behavior. SAVOX marks remain Savox's property.


## SonicModell

Reviewed 2026-10-17. Danny Liew's reply to “SonicModell in OpenRC Simulator — Free Open-Source RC Collaboration” permits appearance, product names and branding of the models described in the request, including Skyhunter models, for the proposed simulator use. It excludes additional costs, financial obligations or liabilities for the manufacturer and does not extend automatically to its entire catalogue. The reply says the referenced models are no longer in production and offers no further support commitment. Original correspondence remains private in the maintainer's mailbox.

`assets/brands/sonicmodell/sonicmodell-logo.png` is an unchanged 350×59 official header logo downloaded on 2026-10-17 from [the manufacturer's website](https://www.sonicmodell.com/): [original PNG](https://www.sonicmodell.com/u_file/weblogo/fbb0fc46c2.png). No mark was recreated or recolored.

## Hitec RCD

Reviewed 2026-10-17. Shawn Spiker's 2026-10-16 reply to “Hitec RCD Transmitters + OpenRC Simulator — Open-Source Integration Collaboration” permits featuring servos published on Hitec websites, with links to its website and products. This follows the request for product names, public specifications and independently made simplified servo representations. Official CAD availability is a reference, not an express redistribution license. Social-media sharing requires separate coordination with Marketing. Original correspondence remains private in the maintainer's mailbox.

`assets/brands/hitec/hitec-radio-logo-footer.png` is the unchanged official footer logo downloaded on 2026-10-17 from [Hitec RCD](https://www.hitecrcd.com/): [original PNG](https://cdn11.bigcommerce.com/s-gatcxyxclp/images/stencil/original/image-manager/hitec-radio-logo-footer.png). No mark was recreated or recolored. The maintainer requested its use for manufacturer identification in the README and website. The servo permission does not explicitly grant a separate logo license; do not describe it as such or reuse it as the simulator's identity.

## Public acknowledgment scope

Reviewed 2026-10-24. The README and website also name these participants from the maintainer's private correspondence and tracking sheet:

| Brand | Written scope and presentation limit |
| --- | --- |
| FLYWING | Its 2026-10-18 confirmation permits product names, simplified exterior 3D models and real color schemes in the free project. The logo may appear in the README and website for attribution, but is not bundled here. Original 3D files stay outside the public repository and MIT license; forks gain no automatic asset rights. The aircraft introduction requires source attribution, an official product link and the prescribed simulation disclaimer. Authorization is revocable on 30 days' written notice. No FLYWING aircraft is integrated. |
| GEMFAN | Its 2026-10-19 reply permits names and simplified 3D representations of current and future propeller ranges in the free simulator, with brand credit and product links. It does not separately license a logo or CAD files. Integration is pending. |
| KONTRONIK | Its 2026-10-20 reply permits independently recreated product models and use of its name. No logo, CAD or confidential data was granted. Integration is pending. |
| Leomotion Drives | Its 2026-10-18 reply permits selected product representations under official names. Any model using its name or branding needs screenshot or render approval before publication. A credit and link are welcome; no logo license, financial sponsorship or equipment was offered. No product model is published. |
| REVOC Custom | Its 2026-10-20 reply welcomes a community-supporter credit, logo and website link in the simulator and on GitHub. A preview was requested. This page uses a text link while that presentation is prepared. A product or giveaway was offered for discussion only; none is promised. |
| Aloft Hobbies | Wayne Flower's 2026-10-23 reply says he posted the project link in the Aloft forum and offers knowledge and feedback. No brand, model or logo permission or financial support was granted. |

These acknowledgments do not claim completed integrations, financial sponsorship, delivered hardware, verified radio compatibility or manufacturer validation. Public acknowledgment uses no private contact details or mailbox links. Existing marks remain their owners' property, outside the MIT code license.
