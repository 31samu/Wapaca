import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
const resources='output/Timetable Wallpaper.app/Contents/Resources/';
async function setup(){
 const messages=[];
 const dom=new JSDOM(await readFile(resources+'editor.html','utf8'),{runScripts:'dangerously',beforeParse(w){w.webkit={messageHandlers:{timetable:{postMessage:m=>messages.push(m)}}};}});
 const seed=JSON.parse(await readFile(resources+'seed.json','utf8'));
 dom.window.nativeLoad(seed);
 return {dom,seed,messages};
}
test('native editor restores saved settings and exclusions, and preserves them across feed refresh',async()=>{
  const {dom,seed,messages}=await setup();const {document,Event}=dom.window;
  assert.equal(messages[0].type,'ready');
  assert.equal(document.querySelector('header'),null);
  assert.equal(document.getElementById('show-title').checked,false);
  assert.equal(document.querySelector('.export-actions').hidden,false);
  assert.equal(document.getElementById('export-svg'),null);
  assert.equal(document.getElementById('export-heic').textContent,'Export HEIC');
  assert.doesNotMatch(document.getElementById('wallpaper').innerHTML,/>Intersectionality &amp; norms<\/text>/);
 const checkbox=[...document.querySelectorAll('#event-list input')].find(el=>el.getAttribute('aria-label').includes('Final presentations'));
 checkbox.checked=false;checkbox.dispatchEvent(new Event('change'));
 const editor=messages.filter(m=>m.type==='settings').at(-1).editor;
 editor.name='Saved module';editor.showTitle=true;editor.rooms=false;editor.theme='dark';
 dom.window.nativeLoad({...seed,editor});
 assert.equal(document.getElementById('module-name').value,'Saved module');
 assert.equal(document.getElementById('show-title').checked,true);
 assert.match(document.getElementById('wallpaper').innerHTML,/>Saved module<\/text>/);
 assert.equal(document.getElementById('rooms').checked,false);
 assert.equal(document.getElementById('theme').value,'dark');
 dom.window.nativeFeed(seed.ics,'2026-09-07T12:00:00Z');
 assert.doesNotMatch(document.getElementById('wallpaper').innerHTML,/Final presentations/);
 const before=document.getElementById('wallpaper').innerHTML;
 assert.throws(()=>dom.window.nativeFeed('invalid ICS','2026-09-08T12:00:00Z'));
 assert.equal(document.getElementById('wallpaper').innerHTML,before);
 assert.ok(messages.filter(m=>m.type==='settings').at(-1).editor.excludedEventIds.includes(checkbox.dataset.eventId));
 dom.window.close();
});
test('native pair renders both appearances and routes PNG and HEIC exports through the local bridge',async()=>{
 const {dom,messages}=await setup();const frames=[];
 dom.window.pngBlob=async svg=>{frames.push(svg);return new dom.window.Blob(['PNG']);};
 const pair=await dom.window.nativePair();
 assert.equal(pair.version,1);assert.equal(frames.length,2);
 assert.match(frames[0],/#f0efe9/);assert.match(frames[1],/#18231f/);
 await dom.window.download(new dom.window.Blob(['PNG']),'png');
 const exported=messages.at(-1);assert.equal(exported.type,'export');assert.equal(exported.extension,'png');assert.equal(Buffer.from(exported.base64,'base64').toString(),'PNG');
 dom.window.document.getElementById('export-heic').click();
 await new Promise((resolve,reject)=>{const deadline=Date.now()+1000;const check=()=>{if(messages.some(message=>message.type==='exportHeic'))resolve();else if(Date.now()>deadline)reject(new Error('HEIC export was not sent'));else setTimeout(check,5);};check();});
 const heic=messages.find(message=>message.type==='exportHeic');assert.equal(heic.pair.version,1);assert.ok(heic.pair.light);assert.ok(heic.pair.dark);
 dom.window.close();
});

test('long event titles wrap inside their cards',async()=>{
 const {dom}=await setup();
 const title=dom.window.document.querySelector('.event h3');
 assert.equal(dom.window.getComputedStyle(title).overflowWrap,'anywhere');
 dom.window.close();
});
