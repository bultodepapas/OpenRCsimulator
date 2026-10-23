# g1.13 — 2026-10-23

Fifth complete paint: Blue Angels-inspired cobalt blue and yellow, U.S. NAVY lettering, interpreted script, tail number 1, yellow cone and underside arrow. Eight exterior layers and four interior layers. Four previous complete liveries retained byte for byte. Mesh, all UV sets and 101 gear poses preserved. Export reimported, rendered and reproduced from an isolated packed source.

# g1.12 — 2026-10-23

Cuarta pintura Spectrum Wings: fondo blanco, plumas cromáticas curvas en ambas caras, compuertas con continuidad, cintas laterales, cola coordinada y bandas blancas en las palas. Siete capas exteriores y cuatro interiores. Tres variantes anteriores conservadas. Malla, todos los UV y 101 poses iguales a g1.11.

# g1.11 — 2026-10-23

Tercera pintura Splash: exterior amarillo/cobalto, salpicaduras asimétricas, vientre rojo y anillos blancos; cono amarillo e identificación interior SP. Ocho capas exteriores y cuatro interiores. Modelos naval y 57/SOHIO conservados. Malla, UV0 y 101 poses sin cambios.

# g1.10 — 2026-10-23

Pintura naval 308: cinco capas nuevas de detalle, variación de acabado, palas negras con puntas amarillas e identificación 308 en compuertas. Geometría, UV0 y 101 poses conservadas; carreras 57/SOHIO intacta.

# g1.9 — 2026-10-23

Interiores de seis compuertas principales: ocho asientos biselados, acabado del reborde y fijaciones perimetrales, marcas de inspección y desgaste leve. Atlas PBR de 2048 con cuatro capas editables. UV0 exterior y todas las poses conservadas. 99.729 triángulos / 57 superficies.

# g1.8 — 2026-10-23

Ruedas reconstruidas con neumáticos ranurados, rines claros abiertos, tapas, pernos y válvulas. Refuerzos interiores discretos en las seis compuertas principales y acabado de los pozos. Atlas PBR compartido de tren. Se conservan nombres, pivotes, 101 poses y la pintura exterior. 99.569 triángulos / 57 superficies.

# g1.7 — 2026-10-23

Pintura detallada del Super Corsair 57/SOHIO, incluyendo la parte inferior. Máscara ventral corregida, tapón superior reubicado, registros inferiores, interiores de compuerta satinados, fijaciones, detalles de palas y pequeños rótulos. Once capas ORA de carreras. Geometría, UVMap y rig conservados.

# g1.6 — 2026-10-22

Decoración 57/SOHIO solicitada por el usuario, sustituye el 308 ficticio. Abanicos amplios, morro curvo, fin blanco, franja afinada, marcas y puntas de hélice. Entrega de carreras Blender y GLB independiente. Misma geometría, UV originales y rig; UV adicional únicamente para pintura de palas.

# g1.5 — 2026-10-22

Tres capas nuevas de detalles: fijaciones y registros, rótulos de servicio y abrasión localizada. Pinturas naval, tricolor y de carreras con distintas intensidades de desgaste; fuentes ORA de diez capas. Detalles interpretativos adaptados a la resolución del juego. Misma geometría, UV y 101 poses que g1.4 Revision 3. GLB predeterminado con tren recogido a escala 1:4.5.

# g1.4 — 2026-10-22

Nueva pintura naval con insignias separadas; racer rojo/marfil en abanico con número ficticio 308; tricolor refinado; rugosidad horneada, desgaste localizado y fuentes ORA de siete capas. Misma geometría, UV y 101 poses que g1.3 Revision 3. GLB predeterminado con tren recogido a escala 1:4.5.

# g1.3 — request Revision 3 — 2026-10-22

- Uniformly enlarged accepted g1.2 from 1:5 to 1:4.5 by applying 10/9 to data and translation keys; node scales remain one.
- Runtime GLB now exports GearRetract frame 100 with export_current_frame=True; editing source opens frame 0.
- Updated dimensional metadata, separated exported/up and editing/down node transforms, and recorded actual mesh contact vertices alongside nominal tyre contacts.
- Re-ran source/GLB verification, roundtrip, motion and clearance witnesses, negative checks, independent re-export, and all previews.
- Preserved g1.2 topology, UVs, names, hierarchy, materials, and every livery file.
- This is the delivery for the supplied Revision 3 letter, separate from the earlier paint-only g1.3.

# g1.2 — 2026-10-22

- Recovered six upper wing-fold hinge covers from R59.
- Closed the visible top-wing cutouts and restored paint continuity.
- Kept section tagging, neutral pose and 54 surfaces; 90,861 triangles.
- Rechecked GLB import and sampled control clearances.

# g1.1 — 2026-10-22

- Rounded door edges at 0.35 mm.
- Relieved right forward tailwheel door/fuselage contact throughout 21 sampled positions.
- Added interior door coating through the existing atlas, preserving 54 surfaces and 11 materials.
- Reduced paint gloss and redesigned Scarlet wing bands; softened three-tone transitions.
- Updated 2048² layered liveries, exports and previews.
- 88,761 triangles, still below the 100,000 target.

# g1 — 2026-10-22

- Derived a separate 1:5 game scene from byte-preserved R59.
- Selected three-blade propeller; documented retained hub and length differences.
- Consolidated 8,725 source object decisions in export-map.json; omitted studio, reference images, stores, superseded parts and internal mechanism detail.
- Reduced to 83,587 triangles, 54 surfaces and 11 materials.
- Added game pivots, section extras and rigid sampled GearRetract action.
- Corrected wheel rolling and tail steering axis directions.
- Relieved neutral flap contacts by 0.5–2 mm aft and up to 1.1 mm down in hinge-local space, without changing pivots or limiting throws.
- Retained control stick and stowed hook; added a simple original gunsight proxy.
- Created shared UVs and three original layered 2048² liveries.
- Verified clean re-export, GLB reimport, metadata transforms and negative verifier cases.
- Included orthographic, livery, articulation, gear and exploded previews, sampled-clearance and surface-deviation reports.
