'use strict';
// Nonbrowser study checks: executes the inline script against a small simulated
// DOM, localStorage, image preflight, and event API. This does not test a browser,
// visual layout, native pointer capture, network transport, or real image decoding.
const fs = require('fs'), vm = require('vm'), assert = require('assert'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, 'workshop-preview.html'), 'utf8');
const appScript = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map(m => m[1]).find(Boolean);
const catalogEnv = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(__dirname, 'catalog.js'), 'utf8'), catalogEnv);
const actualCatalog = catalogEnv.window.OPENRC_DECAL_CATALOG;
const key = 'openrc.sponsor-workshop-study.v1';
function scenario(savedRaw, { catalog = true, missing = null, defer = false } = {}) {
  let document, writes = 0, objectURLs = 0, downloads = 0, lastBlob = null, uuidSerial = 0;
  const store = new Map(savedRaw == null ? [] : [[key, savedRaw]]), elements = {}, pending = [];
  class E {
    constructor(tag = 'div') { this.tagName=tag.toUpperCase(); this.children=[]; this.dataset={}; this.style={}; this.attrs={}; this.listeners={}; this.classList={add(){}}; this.hidden=false; this.disabled=false; this.value=''; this.textContent=''; }
    append(...xs) { for (const x of xs) { this.children.push(x); x.parent=this; } }
    prepend(x) { this.children.unshift(x); x.parent=this; }
    appendChild(x) { this.append(x); return x; }
    replaceChildren(...xs) { this.children=[]; this.append(...xs); }
    setAttribute(k,v) { this.attrs[k]=String(v); }
    addEventListener(k,f) { (this.listeners[k]??=[]).push(f); }
    fire(k, extra={}) { const e={target:this, button:0, key:'', preventDefault(){this.prevented=true},stopPropagation(){},...extra}; for(const f of this.listeners[k]||[])f(e); }
    click() { if (!this.disabled) { if (this.tagName==='A') downloads++; this.fire('click'); } }
    contains(x) { return this===x || this.children.some(c=>c.contains && c.contains(x)); }
    querySelectorAll() { let out=[]; function visit(n){ for(const c of n.children||[]) { if(c.dataset?.focusKey)out.push(c); visit(c); } } visit(this); return out; }
    focus() { document.activeElement=this; }
    remove() {}
    get valueAsNumber() { return this.value==='' ? NaN : Number(this.value); }
    getScreenCTM() { return { inverse(){return {}} }; }
    createSVGPoint() { return { x:0,y:0,matrixTransform(){return {x:this.x,y:this.y}} }; }
    setPointerCapture() {}
  }
  for (const m of html.matchAll(/<([a-zA-Z][a-zA-Z0-9:-]*)\b([^>]*)>/g)) {
    const id = m[2].match(/\bid="([^"]+)"/); if (!id) continue;
    const el = new E(m[1]); if (/\shidden(?:\s|>|$)/.test(m[2])) el.hidden=true; elements[id[1]]=el;
  }
  const center = new E('section');
  document = {
    body:new E('body'), activeElement:null, listeners:{},
    getElementById(id) { if(elements[id])return elements[id]; return center.children.find(c=>c.id===id)||null; },
    querySelector(q) { return q==='.center' ? center : null; },
    createElement:tag=>new E(tag), createElementNS:(ns,tag)=>new E(tag),
    createTextNode(text) { const x=new E(); x.textContent=text; return x; },
    addEventListener(k,f){(this.listeners[k]??=[]).push(f);},
    fire(k,extra={}) { const e={target:this.body,key:'',preventDefault(){},stopPropagation(){},...extra}; for(const f of this.listeners[k]||[])f(e); }
  };
  class FakeImage { constructor() { this.naturalWidth=100; this.naturalHeight=50; } set src(path) { this._src=path; pending.push(this); } }
  const completeAll = () => { while (pending.length) { const image=pending.shift(); if(image._src===missing) image.onerror(); else image.onload(); } };
  class FakeBlob { constructor(parts,options) { this.contents=parts.join(''); this.type=options.type; } }
  const ctx = { document, window: catalog ? {OPENRC_DECAL_CATALOG:JSON.parse(JSON.stringify(actualCatalog))} : {},
    localStorage: { getItem:k=>store.has(k)?store.get(k):null, setItem(k,v){writes++;store.set(k,v);} },
    Image:FakeImage, crypto:{randomUUID:()=> 'test-'+(++uuidSerial)},
    Blob:FakeBlob, URL:{createObjectURL(blob){lastBlob=blob;objectURLs++;return 'blob:fake'},revokeObjectURL(){}},
    setTimeout(){return 1},clearTimeout(){},console };
  ctx.globalThis=ctx; vm.runInNewContext(appScript,ctx,{timeout:3000}); if(!defer) completeAll();
  return { elements, document, center, completeAll, get pending(){return pending.length}, get raw(){return store.get(key)}, get writes(){return writes}, get objectURLs(){return objectURLs}, get downloads(){return downloads}, get lastBlob(){return lastBlob} };
}
const goodItem = {instanceId:'d-1',assetId:'openrc',x:401,y:302,width:130,rotation:15,flipX:false,flipY:false,visible:true,locked:false};
const rawWithDecal = '{\n  "version": 1, "decals": ['+JSON.stringify(goodItem)+'],\n  "selectedId": "d-1"\n}\n';
let pass=0, fail=0;
function test(name, fn) { try { fn(); console.log('PASS '+name); pass++; } catch(e) { console.log('FAIL '+name+' :: '+e.message); fail++; } }
function intact(h,raw) { assert.strictEqual(h.raw,raw,'raw storage changed'); assert.strictEqual(h.writes,0,'storage writes occurred'); }
function blockedExport(h) { h.elements.exportButton.click(); assert.strictEqual(h.objectURLs,0,'export created an object URL'); assert.strictEqual(h.downloads,0,'export created a download'); assert.match(h.elements.notice.textContent,/recovery|restore|original/i); }
function blockedAdd(h) { const ready=h.elements.assetList.children.find(c=>!c.disabled); assert(ready,'expected a simulated ready asset'); const before=h.elements.layerCount.textContent; ready.click(); assert.strictEqual(h.elements.layerCount.textContent,before,'layer count changed'); }
const value = h => JSON.parse(h.raw);

test('missing catalog keeps the exact saved draft and blocks export',()=>{const h=scenario(rawWithDecal,{catalog:false});assert(h.document.getElementById('recoveryNote'));assert.match(h.elements.assetEmpty.textContent,/catalog unavailable/i);blockedExport(h);h.document.fire('keydown',{key:'Delete'});intact(h,rawWithDecal);});
test('missing referenced image keeps original bytes and blocks adding, editing, deleting and export',()=>{const h=scenario(rawWithDecal,{missing:'assets/openrc.svg'});assert(h.document.getElementById('recoveryNote'));assert.strictEqual(h.elements.layerCount.textContent,'1 / 64');assert.strictEqual(h.elements.assetList.children[0].disabled,true);blockedAdd(h);h.elements.flipXButton.click();h.elements.duplicateButton.click();h.elements.deleteButton.click();h.elements.xInput.value='777';h.elements.xInput.fire('change');h.document.fire('keydown',{key:'ArrowRight'});assert.strictEqual(h.elements.layerCount.textContent,'1 / 64');assert.strictEqual(Number(h.elements.xInput.value),401);blockedExport(h);intact(h,rawWithDecal);});
test('malformed draft, including an empty value, preserves raw storage and blocks edits/export',()=>{for(const raw of ['  {"version":1,"decals": [oops \n','']){const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));blockedAdd(h);blockedExport(h);intact(h,raw);}});
test('oversize draft keeps exact storage and blocks edits/export',()=>{const raw='{"version":1,"decals":[],"padding":"'+'x'.repeat(65536)+'"}';const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));blockedAdd(h);blockedExport(h);intact(h,raw);});
test('version mismatch keeps exact storage and blocks edits/export',()=>{const raw=' { "version": 2, "decals": [], "custom":"unchanged" }\n';const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));blockedAdd(h);blockedExport(h);intact(h,raw);});
test('clear confirmation gives truthful blocked-edit feedback',()=>{const h=scenario(rawWithDecal,{missing:'assets/openrc.svg'});h.elements.clearButton.click();h.elements.confirmClear.click();intact(h,rawWithDecal);assert.match(h.elements.notice.textContent,/preserved|paused|recovery/i);});
test('catalog displays four own/test assets and fourteen reference-only cards',()=>{const h=scenario(null);assert.strictEqual(h.elements.assetList.children.length,4);assert(h.elements.assetList.children.every(c=>!c.disabled));assert.strictEqual(h.elements.referenceList.children.length,14);assert.strictEqual(h.elements.availableCount.textContent,'4 AVAILABLE');assert.strictEqual(h.elements.referencesSection.hidden,false);});
test('pending asset checks defer editing, storage writes, and export until completed',()=>{const h=scenario(rawWithDecal,{defer:true});assert.strictEqual(h.pending,4);assert(h.elements.assetList.children.every(c=>c.disabled));h.elements.xInput.value='650';h.elements.xInput.fire('change');h.elements.exportButton.click();assert.match(h.elements.notice.textContent,/checking/i);assert.strictEqual(h.objectURLs,0);intact(h,rawWithDecal);h.completeAll();assert.strictEqual(h.pending,0);assert(h.elements.assetList.children.every(c=>!c.disabled));h.elements.xInput.value='650';h.elements.xInput.fire('change');assert.strictEqual(value(h).decals[0].x,650);});
test('repeated add and duplicate preserve distinct instance IDs',()=>{const h=scenario(null),first=h.elements.assetList.children[0];first.click();first.click();h.elements.duplicateButton.click();const d=value(h).decals;assert.strictEqual(d.length,3);assert(d.every(x=>x.assetId==='openrc'));assert.strictEqual(new Set(d.map(x=>x.instanceId)).size,3);});
test('numeric transforms, bounds, scale and both flips update saved state',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();e.xInput.value='-2';e.xInput.fire('change');e.yInput.value='900';e.yInput.fire('change');e.widthInput.value='9999';e.widthInput.fire('change');e.rotationInput.value='270';e.rotationInput.fire('change');e.flipXButton.click();e.flipYButton.click();let d=value(h).decals[0];assert.strictEqual(d.x,0);assert.strictEqual(d.y,700);assert.strictEqual(d.width,500);assert.strictEqual(d.rotation,-90);assert(d.flipX&&d.flipY);e.smallerButton.click();assert(value(h).decals[0].width<500);e.largerButton.click();assert(value(h).decals[0].width<=500);});
test('layer reorder, hide, lock, show and unlock operate on the intended instance',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();e.assetList.children[1].click();e.assetList.children[2].click();let original=value(h).decals.map(d=>d.instanceId),moved=original[2];e.layerList.children[0].children[1].children[1].click();assert.deepStrictEqual(value(h).decals.map(d=>d.instanceId),[original[0],original[2],original[1]]);e.layerList.children[0].children[0].click();const target=value(h).selectedId;e.layerList.children[0].children[1].children[2].click();assert.strictEqual(value(h).decals.find(d=>d.instanceId===target).visible,false);e.layerList.children[0].children[1].children[3].click();assert.strictEqual(value(h).decals.find(d=>d.instanceId===target).locked,true);assert.strictEqual(e.xInput.disabled,true);e.layerList.children[0].children[1].children[2].click();e.layerList.children[0].children[1].children[3].click();const d=value(h).decals.find(d=>d.instanceId===target);assert(d.visible&&!d.locked);assert.strictEqual(e.xInput.disabled,false);assert.notStrictEqual(target,moved);});
test('multi-move drag is one undo step; redo and Escape rollback preserve state',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();let g=e.decalLayer.children[0];g.fire('pointerdown',{pointerId:1,clientX:500,clientY:320});e.board.fire('pointermove',{pointerId:1,clientX:520,clientY:330});e.board.fire('pointermove',{pointerId:1,clientX:540,clientY:370});assert.strictEqual(value(h).decals[0].x,500);e.board.fire('pointerup',{pointerId:1});assert.strictEqual(value(h).decals[0].x,540);assert.strictEqual(value(h).decals[0].y,370);e.undoButton.click();assert.strictEqual(value(h).decals.length,1);assert.strictEqual(value(h).decals[0].x,500);e.redoButton.click();assert.strictEqual(value(h).decals[0].x,540);const raw=h.raw;g=e.decalLayer.children[0];g.fire('pointerdown',{pointerId:2,clientX:540,clientY:370});e.board.fire('pointermove',{pointerId:2,clientX:600,clientY:400});h.document.fire('keydown',{key:'Escape'});e.board.fire('pointerup',{pointerId:2});assert.strictEqual(h.raw,raw);assert.match(e.decalLayer.children[0].attrs.transform,/translate\(540 370\)/);});
test('pointercancel rolls back without writing an undoable drag',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();const raw=h.raw;e.decalLayer.children[0].fire('pointerdown',{pointerId:8,clientX:500,clientY:320});e.board.fire('pointermove',{pointerId:8,clientX:550,clientY:370});e.board.fire('pointercancel',{pointerId:8});assert.strictEqual(h.raw,raw);assert.match(e.decalLayer.children[0].attrs.transform,/translate\(500 320\)/);e.undoButton.click();assert.strictEqual(value(h).decals.length,0);});
test('arrow and delete shortcuts do not hijack input, but work outside inputs',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();let raw=h.raw;h.document.fire('keydown',{target:e.xInput,key:'ArrowRight'});h.document.fire('keydown',{target:e.xInput,key:'Delete'});assert.strictEqual(h.raw,raw);h.document.fire('keydown',{key:'ArrowRight'});assert.strictEqual(value(h).decals[0].x,501);h.document.fire('keydown',{key:'ArrowDown',shiftKey:true});assert.strictEqual(value(h).decals[0].y,330);h.document.fire('keydown',{key:'z',ctrlKey:true});assert.strictEqual(value(h).decals[0].y,320);h.document.fire('keydown',{key:'y',ctrlKey:true});assert.strictEqual(value(h).decals[0].y,330);h.document.fire('keydown',{key:'Delete'});assert.strictEqual(value(h).decals.length,0);});
test('export contains board metadata, IDs and transforms but no image data',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();e.flipXButton.click();e.exportButton.click();assert.strictEqual(h.downloads,1);assert.strictEqual(h.objectURLs,1);assert.strictEqual(h.lastBlob.type,'application/json');const data=JSON.parse(h.lastBlob.contents);assert.strictEqual(data.schema,'openrc.workshop.study.v1');assert.deepStrictEqual(data.board,{width:1000,height:700,units:'board units'});assert.strictEqual(data.decals[0].assetId,'openrc');assert(data.decals[0].instanceId);assert.strictEqual(data.decals[0].flipX,true);assert(!/assets\/|data:image|base64/i.test(h.lastBlob.contents));});
test('valid local draft reload restores transforms, layer order and visibility',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();e.assetList.children[1].click();e.flipYButton.click();e.layerList.children[0].children[1].children[2].click();const raw=h.raw,restored=scenario(raw),r=restored.elements;assert.strictEqual(restored.raw,raw);assert.strictEqual(restored.writes,0);assert.strictEqual(r.layerCount.textContent,'2 / 64');assert.strictEqual(r.decalLayer.children.length,1);assert.strictEqual(r.flipYButton.attrs['aria-pressed'],'true');assert.strictEqual(value(restored).decals[1].visible,false);});
test('sixty-four decal limit applies to add and duplicate',()=>{const h=scenario(null),e=h.elements,card=e.assetList.children[0];for(let i=0;i<64;i++)card.click();assert.strictEqual(value(h).decals.length,64);assert.strictEqual(e.layerCount.textContent,'64 / 64');assert.strictEqual(e.duplicateButton.disabled,true);const raw=h.raw;card.click();assert.strictEqual(h.raw,raw);assert.match(e.notice.textContent,/maximum/i);});
test('missing unreferenced image disables that asset while other assets and export work',()=>{const h=scenario(null,{missing:'assets/openrc.svg'}),e=h.elements;assert.strictEqual(e.assetList.children[0].disabled,true);assert.strictEqual(e.assetList.children[0].children[1].children[2].textContent,'Image unavailable');assert.strictEqual(e.availableCount.textContent,'3 AVAILABLE');assert(e.assetList.children.slice(1).every(c=>!c.disabled));e.assetList.children[1].click();assert.strictEqual(value(h).decals.length,1);e.exportButton.click();assert.strictEqual(h.downloads,1);});
test('unknown top-level draft fields are preserved and block edits/export',()=>{const raw=' {"version":1,"decals":['+JSON.stringify(goodItem)+'],"selectedId":"d-1","unrecognizedData":"MUST SURVIVE"} \n';const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));h.elements.flipXButton.click();blockedExport(h);intact(h,raw);});
test('unknown layer fields are preserved and block edits/export',()=>{const raw=JSON.stringify({version:1,decals:[{...goodItem,future:'retain'}],selectedId:'d-1'});const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));h.elements.flipXButton.click();blockedExport(h);intact(h,raw);});
test('valid draft key order does not trigger recovery',()=>{const reversedItem=Object.fromEntries(Object.entries(goodItem).reverse());const raw=JSON.stringify({selectedId:'d-1',decals:[reversedItem],version:1});const h=scenario(raw);assert(!h.document.getElementById('recoveryNote'));assert.strictEqual(h.raw,raw);h.elements.flipXButton.click();assert.strictEqual(value(h).decals[0].flipX,true);});
test('negative restored width is preserved and recovery is blocked before another edit',()=>{const item={...goodItem,width:-12};const raw=JSON.stringify({version:1,decals:[item],selectedId:item.instanceId});const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));h.elements.flipXButton.click();intact(h,raw);});
test('duplicate restored instance IDs are preserved and recovery is blocked before another edit',()=>{const first={...goodItem},second={...goodItem,x:510};const raw=JSON.stringify({version:1,decals:[first,second],selectedId:first.instanceId});const h=scenario(raw);assert(h.document.getElementById('recoveryNote'));h.elements.flipXButton.click();intact(h,raw);});
test('rotation rounding canonicalizes 179.999 degrees to -180 and reloads',()=>{const h=scenario(null),e=h.elements;e.assetList.children[0].click();e.rotationInput.value='179.999';e.rotationInput.fire('change');assert.strictEqual(value(h).decals[0].rotation,-180);const raw=h.raw,restored=scenario(raw);assert(!restored.document.getElementById('recoveryNote'));assert.strictEqual(value(restored).decals[0].rotation,-180);assert.strictEqual(restored.raw,raw);assert.strictEqual(restored.writes,0);});
console.log(`Nonbrowser results: ${pass} passed, ${fail} failed.`); if(fail)process.exitCode=1;
