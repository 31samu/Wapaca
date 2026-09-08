import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {loadFixtureApp} from './helpers/fixture-app.mjs';
import {parseCalendar} from '../src/calendar.mjs';
import {renderWallpaper} from '../src/layout.mjs';

async function setup(){
 const {editor,seed}=await loadFixtureApp();
 const dom=new JSDOM(editor,{runScripts:'dangerously',url:'https://worker.invalid'});
 dom.window.nativeLoad(seed);
 const snapshot=()=>JSON.parse(JSON.stringify(dom.window.nativeSnapshot()));
 return {dom,w:dom.window,seed,snapshot};
}
const calendar=(...events)=>`BEGIN:VCALENDAR\r\nVERSION:2.0\r\n${events.join('')}END:VCALENDAR\r\n`;
const session=(uid,title,date='20260908')=>`BEGIN:VEVENT\r\nUID:${uid}\r\nDTSTART:${date}T080000Z\r\nDTEND:${date}T100000Z\r\nSUMMARY:${title}\r\nEND:VEVENT\r\n`;

test('worker has no visible content, controls, web bridge, or browser persistence',async()=>{
 const {dom,w}=await setup();
 assert.equal(w.document.body.children.length,1);
 assert.equal(w.document.body.firstElementChild.tagName,'SCRIPT');
 assert.equal(w.document.querySelector('input,button,a,iframe,svg,canvas'),null);
 assert.equal(w.webkit,undefined);
 assert.equal(dom.window.localStorage?.length,0);
 dom.window.close();
});

test('saved settings, custom dimensions, unknown fields and exclusions survive load and refresh',async()=>{
 const {dom,w,seed,snapshot}=await setup();
 assert.equal(snapshot().editor.showTitle,false);
 const uid=snapshot().events.find(event=>event.title==='Launch presentation').uid;
 w.nativeInclude(uid,false);
 const editor={...snapshot().editor,name:'Saved module',showTitle:true,rooms:false,theme:'dark',width:2880,height:1800,futureSetting:{enabled:true}};
 w.nativeLoad({...seed,editor});
 assert.equal(snapshot().editor.name,'Saved module');
 assert.match(snapshot().svg,/>Saved module<\/text>/);
 assert.equal(snapshot().editor.rooms,false);
 assert.equal(snapshot().editor.width,2880);
 w.nativeFeed(seed.ics,'2026-09-07T12:00:00Z');
 assert.doesNotMatch(snapshot().svg,/Launch presentation/);
 assert.deepEqual(snapshot().editor.futureSetting,{enabled:true});
 const before=snapshot();
 assert.throws(()=>w.nativeFeed('invalid ICS','2026-09-08T12:00:00Z'));
 assert.deepEqual(snapshot(),before);
 dom.window.close();
});

test('wallpaper matches the shared renderer exactly and preserves plain event details',async()=>{
 const {dom,seed,snapshot}=await setup();
 const current=snapshot();
 assert.equal(current.svg,renderWallpaper(parseCalendar(seed.ics,current.editor.timeZone).events,current.editor).svg);
 dom.window.nativeFeed(calendar(session('markup','<script>alert(1)</script>').replace('END:VEVENT','DESCRIPTION:Full plain text\r\nLOCATION:Room 12\r\nEND:VEVENT')),'2026-09-08T12:00:00Z');
 dom.window.nativeUpdate({mode:'month',month:'2026-09',course:''});
 assert.equal(snapshot().events[0].description,'Full plain text');
 assert.equal(snapshot().events[0].location,'Room 12');
 assert.equal(snapshot().events[0].title,'<script>alert(1)</script>');
 assert.match(snapshot().svg,/&lt;script&gt;/);
 assert.equal(dom.window.document.querySelectorAll('script').length,1);
 dom.window.close();
});

test('invalid edits are transactional, and repairing the range permits subsequent edits',async()=>{
 const {dom,w,snapshot}=await setup();
 const before=snapshot();
 for(const patch of [{start:'2026-11-20',end:'2026-10-05'},{width:100},{height:99999},{name:''},{mode:'week'},{theme:'unknown'},{excludedEventIds:[]}]){
  assert.throws(()=>w.nativeUpdate(patch));assert.deepEqual(snapshot(),before);
 }
 w.nativeUpdate({start:'2026-09-01',end:'2026-09-30',name:'September'});
 assert.equal(snapshot().editor.name,'September');
 dom.window.close();
});

test('suggestions require an explicit choice and accept edited dates without changing exclusions',async()=>{
 const {dom,w,snapshot}=await setup();
 const before=snapshot();
 assert.equal(before.suggestions.length,2);
 const suggestion=before.suggestions[0];
 assert.ok(suggestion.reasons.length);assert.equal(snapshot().editor.name,before.editor.name);
 w.nativeUpdate({mode:'module',name:'My foundations module',start:'2026-08-31',end:suggestion.end,proposed:false});
 assert.equal(snapshot().editor.name,'My foundations module');
 assert.equal(snapshot().editor.start,'2026-08-31');
 assert.deepEqual(snapshot().editor.excludedEventIds,before.editor.excludedEventIds);
 dom.window.close();
});

test('cached startup and refresh retain exclusions through moves, deletions and cancellations',async()=>{
 const {dom,w,seed,snapshot}=await setup();
 w.nativeLoad({...seed,ics:calendar(session('kept','Original'),session('deleted','Deleted later')),editor:{mode:'module',start:'2026-09-01',end:'2026-09-30',course:'',excludedEventIds:['kept']}});
 assert.equal(snapshot().includedCount,1);assert.equal(snapshot().events.length,2);
 w.nativeFeed(calendar(session('kept','Moved','20260909'),session('new','New session'),'BEGIN:VEVENT\r\nUID:cancelled\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\n'),'2026-09-08T12:00:00Z');
 const before=snapshot();
 assert.match(before.svg,/New session/);assert.doesNotMatch(before.svg,/Moved|Deleted later/);
 assert.equal(before.events.find(e=>e.uid==='kept').included,false);
 assert.throws(()=>w.nativeFeed(calendar(session('duplicate','One'),session('duplicate','Two')),'2026-09-09T12:00:00Z'),/duplicate/);
 assert.deepEqual(snapshot(),before);
 w.nativeFeed(calendar(),'2026-09-09T12:00:00Z');
 assert.equal(snapshot().includedCount,0);assert.ok(snapshot().editor.excludedEventIds.includes('kept'));
 dom.window.close();
});

test('wake, startup, and refresh advance a following month across year end and preserve historical months',async()=>{
 for(const action of ['day','feed','load'])for(const following of [true,false]){
  const {dom,w,seed,snapshot}=await setup();
  const RealDate=w.Date;let now='2026-12-31T22:30:00Z';
  w.Date=class extends RealDate { constructor(...args){super(...(args.length?args:[now]));} static now(){return new RealDate(now).getTime();} };
  w.nativeLoad({...seed,ics:calendar(),editor:{mode:'month',month:following?'2026-12':'2026-09',today:'2026-12-31',course:''}});
  const previous=snapshot().editor;
  now='2026-12-31T23:30:00Z';
  if(action==='day')assert.equal(w.nativeDay(),true);
  else if(action==='feed')w.nativeFeed(calendar(),now);
  else w.nativeLoad({...seed,ics:calendar(),editor:previous});
  assert.equal(snapshot().editor.today,'2027-01-01');
  assert.equal(snapshot().editor.month,following?'2027-01':'2026-09');
  assert.equal(w.nativeDay(),false);
  dom.window.close();
 }
});

test('reset clears cached calendar, exclusions and course filter',async()=>{
 const {dom,w,snapshot}=await setup();
 assert.ok(snapshot().events.length>0);
 assert.equal(w.nativeReset(),true);
 assert.equal(snapshot().events.length,0);
 assert.equal(snapshot().editor.course,'');assert.equal(snapshot().courseCode,'');
 assert.equal(snapshot().editor.name,'New module');
 assert.equal(snapshot().editor.snapshotDate,'none');
 assert.equal(snapshot().editor.excludedEventIds.length,0);
 dom.window.close();
});

test('multiple subscriptions retain independent identities and validate before replacing',async()=>{
 const {dom,w,seed,snapshot}=await setup();
 const sources=[{id:'legacy',legacyIds:true,name:'TimeEdit',kind:'timeedit',ics:calendar(session('same','Lecture'))},
  {id:'moodle',name:'Moodle',kind:'generic',ics:calendar(session('same','Assignment deadline'))}];
 w.nativeLoad({...seed,subscriptions:sources,editor:{course:'',mode:'module',start:'2026-09-01',end:'2026-09-30',excludedEventIds:['same']}});
 assert.match(snapshot().svg,/Assignment deadline/);assert.doesNotMatch(snapshot().svg,/>Lecture</);
 assert.equal(snapshot().events.length,2);
 assert.equal(snapshot().events.find(e=>e.calendarId==='moodle')?.sourceName??snapshot().events.find(e=>e.sourceName==='Moodle').sourceName,'Moodle');
 const before=snapshot();
 assert.throws(()=>w.nativeCalendars([...sources,{id:'invalid',ics:'invalid'}],'2026-09-09T12:00:00Z'));
 assert.deepEqual(snapshot(),before);
 w.nativeCalendars(sources.toReversed(),'2026-09-09T12:00:00Z');
 assert.equal(snapshot().events.find(e=>e.uid==='same').included,false);
 w.nativeCalendars([sources[1]],'2026-09-09T12:00:00Z');
 assert.equal(snapshot().events.length,1);assert.ok(snapshot().editor.excludedEventIds.includes('same'));
 w.nativeCalendars([],'2026-09-09T12:00:00Z');assert.equal(snapshot().events.length,0);
 dom.window.close();
});

test('both export appearances capture the same revision even if settings change while rasterizing',async()=>{
 const {dom,w,snapshot}=await setup();
 const frames=[];
 w.pngBase64=async svg=>{frames.push(svg);w.nativeUpdate({name:'Changed during export',showTitle:true});return 'UE5H';};
 const before=snapshot().editor;
 const pair=await w.nativePair();
 assert.equal(pair.version,1);assert.equal(pair.name,before.name);
 assert.equal(frames.length,2);assert.match(frames[0],/#f0efe9/);assert.match(frames[1],/#18231f/);
 assert.doesNotMatch(frames[1],/Changed during export/);
 assert.equal(pair.light,'UE5H');assert.equal(pair.dark,'UE5H');
 dom.window.close();
});
