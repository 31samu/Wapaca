import {readFile,writeFile,mkdir} from 'node:fs/promises';
import sharp from 'sharp';
import {parseCalendar,localParts} from '../src/calendar.mjs';
import {renderWallpaper,selectEvents} from '../src/layout.mjs';

const config=JSON.parse(await readFile('config.local.json','utf8').catch(()=>readFile('config.example.json','utf8')));
const source=await readFile('data/calendar.ics','utf8').catch(()=>{throw new Error('No snapshot yet. Run npm run refresh with CALENDAR_URL set, or put an ICS file at data/calendar.ics.');});
const parsed=parseCalendar(source,config.timeZone);
const metadata=JSON.parse(await readFile('data/source.json','utf8').catch(()=>'{}'));
const today=process.env.TIMETABLE_TODAY || localParts(new Date(),config.timeZone).date;
const snapshotDate=metadata.fetchedAt?localParts(metadata.fetchedAt,config.timeZone).date:'unknown';
const shared={...config,...config.module,today,snapshotDate,rooms:true,iconSpace:true};
await mkdir('output',{recursive:true});
const reports=[];
for(const mode of ['month','module'])for(const theme of ['light','dark']){
  const options={...shared,mode,theme,month:today.slice(0,7)};
  const result=renderWallpaper(parsed.events,options);
  const name=mode==='month'?`month-${today.slice(0,7)}-${theme}`:`module-${config.module.start}-${theme}`;
  await writeFile(`output/${name}.svg`,result.svg);
  await sharp(Buffer.from(result.svg)).png().toFile(`output/${name}.png`);
  reports.push({name,width:config.width,height:config.height,eventCount:result.grid.visible.length,weeks:result.grid.weeks,warnings:result.warnings});
}
// Embed only trusted layout code. Calendar data is JSON-escaped before entering
// the script element; the renderer separately escapes every SVG text value.
const scriptJson=value=>JSON.stringify(value).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
const layout=(await readFile('src/layout.mjs','utf8')).replace(/^export /gm,'');
const suggestions=(await readFile('src/suggestions.mjs','utf8')).replace(/^export /gm,'');
const data={...parsed,today,snapshotDate};
const {subscriptionUrl,...previewConfig}=config;
const template=await readFile('src/preview.html','utf8');
const html=template.replace('/*__LAYOUT__*/',()=>layout+'\n'+suggestions).replace('/*__DATA__*/',()=>scriptJson(data)).replace('/*__CONFIG__*/',()=>scriptJson(previewConfig));
await writeFile('output/preview.html',html);
await writeFile('output/events.json',JSON.stringify(data,null,2));
await writeFile('output/validation.json',JSON.stringify({generatedAt:new Date().toISOString(),totalEvents:parsed.events.length,courseEvents:selectEvents(parsed.events,config.course).length,reports},null,2));
await writeFile('output/module-appearance.json',JSON.stringify([
  {fileName:`module-${config.module.start}-light.png`,isPrimary:true,isForLight:true},
  {fileName:`module-${config.module.start}-dark.png`,isForDark:true}
],null,2));
console.log(JSON.stringify({totalEvents:parsed.events.length,courseEvents:selectEvents(parsed.events,config.course).length,reports,preview:'output/preview.html'},null,2));
