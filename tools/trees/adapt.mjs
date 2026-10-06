#!/usr/bin/env node
// Offline authoring assets only. Runtime trees use the atlas, not these meshes.
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {NodeIO, Primitive} from '@gltf-transform/core';
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

async function main() {
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
main().catch(error=>{console.error(error);process.exitCode=1;});
