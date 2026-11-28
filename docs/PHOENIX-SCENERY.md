# Import Phoenix scenery

Scope: importing a local panorama, installing its preview and entering an admitted calibrated runway trial. Landscape developers use [Add a landscape](LANDSCAPES.md); implementation and remaining qualification live in the [Phoenix scenery contract](plans/phoenix-scenery-import.md).

Open **Home → Flight → Import scenery** beneath the landscape selector. Choose a Phoenix installation,
site folder, `.pxf` descriptor or ZIP, including ZIP64. Large ZIPs are indexed without extracting
their contents. Select a result to load its six faces. Drag to look
around if the seams match, or use the numbered buttons to inspect the individual faces. Choose
**Install preview** to keep the scenery in the local library. Installed previews reopen even if the
source folder is disconnected. Removal asks for confirmation. Preview conversion uses up to
1024 pixels per face and rejects source panels that exceed the decoder's size limits.

For the calibrated revisions of Airfield, Aircraft Carrier X98, Frönäs, Farmland and Aero Club
Dolores, install the preview and choose **Fly calibrated runway**. The importer verifies the site's
revision and six images. It starts the selected runway-capable airplane in the calibrated direction
using a fixed pilot eye and calm practice conditions. The calibration uses estimated geometry and
contact properties. It covers the launch strip and leaves source terrain, obstacles, water and
landing fidelity unqualified. Other revisions remain available to preview, including recognizable
InfinityScape titles. The built-in landscape selector still controls ordinary Home flights.
[Compatibility and remaining work](plans/phoenix-scenery-import.md)
