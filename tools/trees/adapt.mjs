#!/usr/bin/env node
// Offline authoring assets only. Runtime trees use the atlas, not these meshes.
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {NodeIO, Primitive} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
const validator = createRequire(import.meta.url)('gltf-validator');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const source = path.join(root, 'assets/landscape/trees/source');
const ids = ['CommonTree_1', 'CommonTree_3', 'Pine_1'];
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const requireThat = (ok, why) => { if (!ok) throw new Error(why); };
function compact(report) {
  const counts={};
  for (const message of report.issues.messages) counts[message.code]=(counts[message.code]??0)+1;
  return {validatorVersion:report.validatorVersion, issues:{...report.issues,messages:report.issues.messages.slice(0,5),counts_by_code:counts}};
}
const identity = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];

async function mainLegacy() {
  const args = process.argv.slice(2);
  requireThat(args.length === 2 && args[0] === '--out', 'Usage: node adapt.mjs --out NEW_DIRECTORY');
  const out = path.resolve(args[1]);
  await fs.mkdir(out, {recursive:true});
  requireThat((await fs.readdir(out)).length === 0, 'Output must be empty');
  const manifest = JSON.parse(await fs.readFile(path.join(source,'upstream-provenance.json'), 'utf8'));
  for (const file of manifest.files) {
    requireThat(path.basename(file.path) === file.path, 'Source must be a basename');
    requireThat(sha(await fs.readFile(path.join(source,file.path))) === file.sha256, `Source drift: ${file.path}`);
  }
  const io = new NodeIO();
  const trees = [];
  for (const id of ids) {
    const file = path.join(source, id+'.gltf');
    const sourceReport = await validator.validateString(await fs.readFile(file,'utf8'), {
      uri:id+'.gltf', maxIssues:100000, externalResourceFunction: async uri => {
        requireThat(manifest.files.some(f=>f.path===uri), `Undeclared dependency ${uri}`);
        return new Uint8Array(await fs.readFile(path.join(source,uri)));
      }
    });
    await fs.writeFile(path.join(out,id+'-source-validation.json'),JSON.stringify(compact(sourceReport),null,2)+'\n');
    requireThat(sourceReport.issues.messages.every(m=>m.severity!==0 || (m.code==='ACCESSOR_NON_CLAMPED' && m.pointer.endsWith('/attributes/COLOR_0'))), `Unreviewed source error ${id}`);
    const doc = await io.read(file);
    // Pack the untouched source for a like-for-like Godot decoder comparison, with embedded images.
    await fs.writeFile(path.join(out,id+'-reference.glb'),await io.writeBinary(doc));
    const scene = doc.getRoot().listScenes();
    const nodes = doc.getRoot().listNodes();
    requireThat(scene.length===1 && nodes.length===1 && nodes[0].getMesh(), `Expected one static mesh: ${id}`);
    requireThat(nodes[0].getMatrix().every((v,i)=>Math.abs(v-identity[i])<1e-9), 'Unexpected source transform');
    requireThat(doc.getRoot().listAnimations().length===0 && doc.getRoot().listSkins().length===0, 'Static sources only');
    const primitives = nodes[0].getMesh().listPrimitives();
    let triangles=0;
    const low=[Infinity,Infinity,Infinity], high=[-Infinity,-Infinity,-Infinity];
    const positions = new Set();
    let colorsClamped=0;
    for (const prim of primitives) {
      requireThat(prim.getMode() === Primitive.Mode.TRIANGLES && prim.getIndices(), 'Indexed triangles required');
      triangles += prim.getIndices().getCount()/3;
      positions.add(prim.getAttribute('POSITION'));
      const color=prim.getAttribute('COLOR_0');
      if(color) {
        const values=new Float32Array(color.getArray());
        for(let i=0;i<values.length;i++) {
          requireThat(Number.isFinite(values[i]) && values[i]>=0 && values[i]<=1.0002, 'Unexpected color range');
          if(values[i]>1) { values[i]=1;colorsClamped++; }
        }
        color.setArray(values);
      }
    }
    requireThat(triangles <= 10000, 'Offline source exceeds reviewed 10k budget; not a runtime LOD');
    for (const accessor of positions) {
      requireThat(accessor && accessor.getElementSize()===3, 'Expected xyz positions');
      const values=accessor.getArray();
      for(let i=0;i<values.length;i++) { requireThat(Number.isFinite(values[i]), 'Nonfinite position'); const c=i%3;low[c]=Math.min(low[c],values[i]);high[c]=Math.max(high[c],values[i]); }
    }
    const height=high[1]-low[1], bottom=[(low[0]+high[0])/2,low[1],(low[2]+high[2])/2];
    requireThat(height>0, 'Zero-height source');
    for(const accessor of positions) {
      const values=new Float32Array(accessor.getArray());
      for(let i=0;i<values.length;i++) values[i]=(values[i]-bottom[i%3])/height;
      accessor.setArray(values);
    }
    // Preserve original UVs, normals, tangents, textures, alpha cutoff and colors.
    for(const material of doc.getRoot().listMaterials()) requireThat(material.getMetallicFactor()===0,'Tree material must be dielectric');
    const bytes=await io.writeBinary(doc);
    const resultReport=await validator.validateBytes(bytes,{uri:id+'.glb'});
    requireThat(resultReport.issues.numErrors===0, `Invalid derived GLB ${id}`);
    await fs.writeFile(path.join(out,id+'.glb'),bytes);
    trees.push({id,triangles,surfaces:primitives.length,sha256:sha(bytes),
      normalization:{source_bounds:{min:low,max:high},bottom_center:bottom,scale:1/height,height_m:1},
      color_components_clamped:colorsClamped,source_validation:compact(sourceReport),derived_validation:compact(resultReport)});
  }
  await fs.copyFile(path.join(source,'License_Standard.txt'),path.join(out,'LICENSE.txt'));
  await fs.writeFile(path.join(out,'validation.json'),JSON.stringify({
    format:'openrc-tree-adaptation v1',source_archive_sha256:manifest.sha256,
    tools:{gltf_transform:'4.5.0',khronos_validator:'2.0.0-dev.3.10'},
    scope:'High-detail offline bake sources. Not exported; L8 close mesh LODs need their own budget/review.',trees
  },null,2)+'\n');
  console.log(JSON.stringify(trees.map(t=>({id:t.id,triangles:t.triangles,errors:t.derived_validation.issues.numErrors,warnings:t.derived_validation.issues.numWarnings}))));
}

function readGlbJson(bytes, label) {
  requireThat(bytes.length >= 20 && bytes.readUInt32LE(0) === 0x46546c67, `${label}: invalid GLB header`);
  requireThat(bytes.readUInt32LE(4) === 2 && bytes.readUInt32LE(8) === bytes.length,
    `${label}: expected a complete glTF 2.0 GLB`);
  let offset = 12;
  while (offset + 8 <= bytes.length) {
    const length = bytes.readUInt32LE(offset);
    const type = bytes.readUInt32LE(offset + 4);
    offset += 8;
    requireThat(offset + length <= bytes.length, `${label}: truncated GLB chunk`);
    if (type === 0x4e4f534a) return JSON.parse(bytes.subarray(offset, offset + length).toString('utf8').trim());
    offset += length;
  }
  throw new Error(`${label}: GLB has no JSON chunk`);
}

function externalUris(document) {
  const uris = [];
  for (const resource of [...(document.buffers ?? []), ...(document.images ?? [])]) {
    const uri = resource.uri;
    if (!uri || uri.startsWith('data:')) continue;
    requireThat(!/^[a-z][a-z0-9+.-]*:/i.test(uri), `Remote/protocol dependency is not supported: ${uri}`);
    requireThat(!uri.includes('\\') && !uri.includes('?') && !uri.includes('#'), `Unsupported dependency URI: ${uri}`);
    try { decodeURIComponent(uri); } catch { throw new Error(`Invalid escaped dependency URI: ${uri}`); }
    uris.push(uri);
  }
  return [...new Set(uris)].sort();
}

function transformPoint(matrix, x, y, z) {
  return [
    matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
    matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13],
    matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
  ];
}

function collectNodes(scene) {
  const found = [];
  const visit = node => {
    found.push(node);
    for (const child of node.listChildren()) visit(child);
  };
  for (const node of scene.listChildren()) visit(node);
  return found;
}

function boundsForNodes(nodes, id) {
  const low = [Infinity, Infinity, Infinity];
  const high = [-Infinity, -Infinity, -Infinity];
  let triangles = 0;
  const usedMaterials = new Set();
  for (const node of nodes) {
    const mesh = node.getMesh();
    if (!mesh) continue;
    const matrix = node.getWorldMatrix();
    for (const primitive of mesh.listPrimitives()) {
      requireThat(primitive.getMode() === Primitive.Mode.TRIANGLES && primitive.getIndices(),
        `${id}: indexed triangles required`);
      const indexCount = primitive.getIndices().getCount();
      requireThat(indexCount > 0 && indexCount % 3 === 0, `${id}: triangle index count must be divisible by three`);
      triangles += indexCount / 3;
      const material = primitive.getMaterial();
      requireThat(material && material.getName(), `${id}: every tree surface requires a named source material`);
      usedMaterials.add(material.getName());
      const positions = primitive.getAttribute('POSITION');
      requireThat(positions && positions.getElementSize() === 3, `${id}: expected xyz positions`);
      const values = positions.getArray();
      for (let i = 0; i < values.length; i += 3) {
        const point = transformPoint(matrix, values[i], values[i + 1], values[i + 2]);
        for (let axis = 0; axis < 3; axis++) {
          requireThat(Number.isFinite(point[axis]), `${id}: nonfinite transformed position`);
          low[axis] = Math.min(low[axis], point[axis]);
          high[axis] = Math.max(high[axis], point[axis]);
        }
      }
    }
  }
  requireThat(triangles > 0 && low.every(Number.isFinite), `${id}: no static triangle geometry in default scene`);
  requireThat(triangles <= 10000, `${id}: offline source exceeds reviewed 10k budget; not a runtime LOD`);
  return {low, high, triangles, usedMaterials: [...usedMaterials].sort()};
}

function compactMaterials(document) {
  return document.getRoot().listMaterials().map(material => ({
    name: material.getName(), alpha_mode: material.getAlphaMode(),
    alpha_cutoff: material.getAlphaCutoff(), double_sided: material.getDoubleSided(),
    metallic_factor: material.getMetallicFactor(),
  }));
}

async function verifyPinnedFile(file, expectedHash, label) {
  requireThat(/^[a-f0-9]{64}$/i.test(expectedHash ?? ''), `${label}: expected a pinned SHA-256`);
  const bytes = await fs.readFile(file);
  requireThat(sha(bytes) === expectedHash.toLowerCase(), `${label}: source hash drift: ${file}`);
  return bytes;
}

function safeDisplayPath(file) {
  const relative = path.relative(root, file);
  return relative && !relative.startsWith(`..${path.sep}`) && relative !== '..'
    ? relative.split(path.sep).join('/') : file.split(path.sep).join('/');
}

async function mainRecipe(recipePathValue, outValue) {
  const recipePath = path.resolve(recipePathValue);
  const out = path.resolve(outValue);
  await fs.mkdir(out, {recursive: true});
  requireThat((await fs.readdir(out)).length === 0, 'Output must be empty');
  const recipe = JSON.parse(await fs.readFile(recipePath, 'utf8'));
  requireThat(recipe?.format === 'openrc-tree-source-recipe v1', 'Unsupported source recipe format');
  requireThat(typeof recipe.recipe_id === 'string' && recipe.recipe_id.length > 0, 'Recipe must have a recipe_id');
  requireThat(Array.isArray(recipe.species) && recipe.species.length === ids.length
    && recipe.species.map(item => item.id).join(',') === ids.join(','),
  `Recipe species must retain slots in this order: ${ids.join(', ')}`);

  const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
  const trees = [];
  const bakeSpecies = [];
  const copiedLicenses = new Set();
  for (const spec of recipe.species) {
    const id = spec.id;
    requireThat(typeof spec.source_asset_id === 'string' && spec.source_asset_id.length > 0,
      `${id}: source_asset_id is required`);
    requireThat(typeof spec.bark_material_name === 'string' && spec.bark_material_name.length > 0
      && typeof spec.foliage_material_name === 'string' && spec.foliage_material_name.length > 0
      && spec.bark_material_name !== spec.foliage_material_name,
    `${id}: distinct exact bark and foliage material names are required`);
    const provenance = spec.provenance;
    requireThat(provenance && ['creator', 'license', 'source_url', 'source_revision']
      .every(key => typeof provenance[key] === 'string' && provenance[key].length > 0),
    `${id}: creator, license, source_url and source_revision provenance are required`);
    requireThat(typeof spec.source_path === 'string' && spec.source_path.length > 0,
      `${id}: source_path is required`);
    const sourcePath = path.resolve(path.dirname(recipePath), spec.source_path);
    const sourceBytes = await verifyPinnedFile(sourcePath, spec.source_sha256, id);
    const sourceIsGlb = path.extname(sourcePath).toLowerCase() === '.glb';
    requireThat(sourceIsGlb || path.extname(sourcePath).toLowerCase() === '.gltf',
      `${id}: source must be a .gltf or .glb`);
    const sourceJson = sourceIsGlb ? readGlbJson(sourceBytes, id) : JSON.parse(sourceBytes.toString('utf8'));
    const uris = externalUris(sourceJson);
    const dependencies = spec.dependencies ?? [];
    requireThat(Array.isArray(dependencies), `${id}: dependencies must be an array`);
    const dependencyMap = new Map();
    for (const dependency of dependencies) {
      requireThat(typeof dependency.uri === 'string' && !dependencyMap.has(dependency.uri),
        `${id}: dependency URIs must be unique strings`);
      const dependencyPath = path.resolve(path.dirname(sourcePath), decodeURIComponent(dependency.uri));
      const bytes = await verifyPinnedFile(dependencyPath, dependency.sha256, `${id} dependency ${dependency.uri}`);
      dependencyMap.set(dependency.uri, {path: dependencyPath, bytes});
    }
    requireThat(JSON.stringify([...dependencyMap.keys()].sort()) === JSON.stringify(uris),
      `${id}: recipe dependencies must exactly match every external glTF resource (found ${uris.join(', ')})`);
    const pinnedFiles = spec.pinned_files ?? [];
    requireThat(Array.isArray(pinnedFiles), `${id}: pinned_files must be an array`);
    const verifiedPins = [];
    for (const pin of pinnedFiles) {
      requireThat(typeof pin.path === 'string' && typeof pin.role === 'string', `${id}: pinned files need path and role`);
      const pinnedPath = path.resolve(path.dirname(recipePath), pin.path);
      const bytes = await verifyPinnedFile(pinnedPath, pin.sha256, `${id} ${pin.role}`);
      verifiedPins.push({role: pin.role, path: safeDisplayPath(pinnedPath), sha256: sha(bytes), bytes: bytes.length});
      if (pin.role === 'license') {
        const licenseName = `${id}.txt`;
        const outputLicense = `licenses/${licenseName}`;
        if (!copiedLicenses.has(outputLicense)) {
          await fs.mkdir(path.join(out, 'licenses'), {recursive: true});
          await fs.copyFile(pinnedPath, path.join(out, outputLicense));
          copiedLicenses.add(outputLicense);
        }
        provenance.license_file = outputLicense;
      }
    }

    let sourceReport;
    if (sourceIsGlb) {
      sourceReport = await validator.validateBytes(new Uint8Array(sourceBytes), {uri:path.basename(sourcePath), maxIssues:100000});
    } else {
      sourceReport = await validator.validateString(sourceBytes.toString('utf8'), {
        uri:path.basename(sourcePath), maxIssues:100000,
        externalResourceFunction: async uri => {
          const dependency = dependencyMap.get(uri);
          requireThat(dependency, `${id}: undeclared dependency requested by validator: ${uri}`);
          return new Uint8Array(dependency.bytes);
        },
      });
    }
    await fs.writeFile(path.join(out, `${id}-source-validation.json`), JSON.stringify(compact(sourceReport), null, 2) + '\n');
    requireThat(sourceReport.issues.messages.every(message => message.severity !== 0
      || (message.code === 'ACCESSOR_NON_CLAMPED' && message.pointer.endsWith('/attributes/COLOR_0'))),
    `${id}: unreviewed source validation error`);

    const doc = await io.read(sourcePath);
    requireThat(doc.getRoot().listScenes().length === 1, `${id}: exactly one scene is required`);
    requireThat(doc.getRoot().listAnimations().length === 0 && doc.getRoot().listSkins().length === 0,
      `${id}: static sources only; animation and skin data are unsupported`);
    const scene = doc.getRoot().listScenes()[0];
    const nodes = collectNodes(scene);
    requireThat(nodes.length > 0 && nodes.length === doc.getRoot().listNodes().length,
      `${id}: every source node must belong to the single scene`);
    for (const node of nodes) requireThat(!node.getCamera(), `${id}: cameras are not tree geometry`);
    const geometry = boundsForNodes(nodes, id);
    const materials = compactMaterials(doc);
    const sourceMaterialNames = materials.map(material => material.name).sort();
    const expectedMaterialNames = [spec.bark_material_name, spec.foliage_material_name].sort();
    requireThat(JSON.stringify(sourceMaterialNames) === JSON.stringify(expectedMaterialNames),
      `${id}: exact source materials must be ${expectedMaterialNames.join(' and ')}, found ${sourceMaterialNames.join(', ')}`);
    requireThat(JSON.stringify(geometry.usedMaterials) === JSON.stringify(expectedMaterialNames),
      `${id}: every source bark and foliage material must be used`);
    const bark = materials.find(material => material.name === spec.bark_material_name);
    const foliage = materials.find(material => material.name === spec.foliage_material_name);
    requireThat(bark.alpha_mode === 'OPAQUE' && foliage.alpha_mode === 'MASK',
      `${id}: source tree requires OPAQUE bark and MASK foliage`);
    const referenceBytes = sourceIsGlb ? sourceBytes : await io.writeBinary(doc);

    // Preserve the original node tree and all material/texture data. Only a wrapper is added.
    const height = geometry.high[1] - geometry.low[1];
    requireThat(Number.isFinite(height) && height > 0, `${id}: zero-height source`);
    const bottomCenter = [(geometry.low[0] + geometry.high[0]) / 2, geometry.low[1],
      (geometry.low[2] + geometry.high[2]) / 2];
    const roots = scene.listChildren();
    const wrapper = doc.createNode('OpenRC_Normalization');
    const scale = 1 / height;
    wrapper.setScale([scale, scale, scale]);
    wrapper.setTranslation(bottomCenter.map(value => -value * scale));
    for (const node of roots) {
      scene.removeChild(node);
      wrapper.addChild(node);
    }
    scene.addChild(wrapper);

    await fs.writeFile(path.join(out, `${id}-reference.glb`), referenceBytes);
    const derivedBytes = await io.writeBinary(doc);
    const resultReport = await validator.validateBytes(derivedBytes, {uri:`${id}.glb`});
    requireThat(resultReport.issues.numErrors === 0, `${id}: invalid derived GLB`);
    const derivedHash = sha(derivedBytes);
    await fs.writeFile(path.join(out, `${id}.glb`), derivedBytes);
    const tree = {
      id, source_asset_id: spec.source_asset_id, source_path: safeDisplayPath(sourcePath),
      source_sha256: sha(sourceBytes), derived_sha256: derivedHash,
      source_bytes: sourceBytes.length, derived_bytes: derivedBytes.length,
      triangles: geometry.triangles, surfaces: geometry.usedMaterials.length,
      source_material_names: expectedMaterialNames,
      materials, pinned_files: verifiedPins,
      provenance: {...provenance},
      normalization: {
        method: 'scene root wrapper; original geometry, node TRS/matrices and material identities retained',
        source_bounds_world_y_up: {min: geometry.low, max: geometry.high},
        bottom_center_world_y_up: bottomCenter, scale, source_height_m: height, height_m: 1,
      },
      source_validation: compact(sourceReport), derived_validation: compact(resultReport),
    };
    trees.push(tree);
    bakeSpecies.push({
      id, source_asset_id: spec.source_asset_id, source_sha256: tree.source_sha256,
      derived_sha256: derivedHash, bark_material_name: spec.bark_material_name,
      foliage_material_name: spec.foliage_material_name, source_material_names: expectedMaterialNames,
      provenance: {...provenance}, normalization: tree.normalization,
    });
  }

  await fs.writeFile(path.join(out, 'bake-recipe.json'), JSON.stringify({
    format: 'openrc-tree-bake-recipe v1', recipe_id: recipe.recipe_id, species: bakeSpecies,
  }, null, 2) + '\n');
  await fs.writeFile(path.join(out, 'validation.json'), JSON.stringify({
    format: 'openrc-tree-adaptation v2', recipe_id: recipe.recipe_id,
    tools: {gltf_transform:'4.5.0', khronos_validator:'2.0.0-dev.3.10'},
    scope: 'High-detail offline bake sources. Not exported; close mesh LODs need their own budget/review.',
    species: trees,
  }, null, 2) + '\n');
  console.log(JSON.stringify(trees.map(tree => ({id:tree.id,source_asset_id:tree.source_asset_id,
    triangles:tree.triangles,source_sha256:tree.source_sha256,derived_sha256:tree.derived_sha256,
    errors:tree.derived_validation.issues.numErrors,warnings:tree.derived_validation.issues.numWarnings}))));
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === '--source-recipe') {
    requireThat(args.length === 4 && args[2] === '--out',
      'Usage: node adapt.mjs --source-recipe RECIPE.json --out NEW_DIRECTORY');
    await mainRecipe(args[1], args[3]);
    return;
  }
  await mainLegacy();
}

main().catch(error=>{console.error(error);process.exitCode=1;});
