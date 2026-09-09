import {mkdir,writeFile,readFile,mkdtemp,rename,rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import sharp from 'sharp';
import {loadNativeBuildData} from './native-build-data.mjs';
import {compileNative} from './native-compile.mjs';
const args = process.argv.slice(2);
if (args.some(arg => arg !== '--private-seed')) throw new Error('Usage: node scripts/build-native.mjs [--private-seed]');
const {config, seed} = await loadNativeBuildData({privateSeed: args.includes('--private-seed')});
if (args.includes('--private-seed')) console.warn('Private development build: the app includes local calendar data. Do not share it.');
const outputBundle='output/Wapacal.app';
const temp=await mkdtemp(join(tmpdir(),'wapacal-build-'));
const bundle=join(temp,'Wapacal.app');
await mkdir(`${bundle}/Contents/MacOS`,{recursive:true});
await writeFile(`${bundle}/Contents/Info.plist`,`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Wapacal</string>
<key>CFBundleIdentifier</key><string>local.wapacal.app</string>
<key>CFBundleName</key><string>Wapacal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Wapacal.icns</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Wapacal export</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSItemContentTypes</key><array><string>local.wapacal.export</string><string>local.timetable.export</string></array></dict></array>
<key>UTExportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>local.wapacal.export</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeDescription</key><string>Wapacal light/dark export</string><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>wapacal</string></array></dict></dict></array>
<key>UTImportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>local.timetable.export</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeDescription</key><string>Legacy Wapacal export</string><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>timetable</string></array></dict></dict></array>
</dict></plist>`);
compileNative('native/main.swift', `${bundle}/Contents/MacOS/Wapacal`);
const resources=`${bundle}/Contents/Resources`;
await mkdir(resources,{recursive:true});
const iconSource='assets/app-icon/Wapacal-iOS-Default-1024x1024@1x.png';
const iconEntries=[['icp4',16],['icp5',32],['icp6',64],['ic07',128],['ic08',256],['ic09',512],['ic10',1024]];
const iconChunks=[];
let iconLength=8;
for(const [type,size] of iconEntries){
  const png=await sharp(iconSource).resize(size,size).ensureAlpha().png().toBuffer();
  const chunk=Buffer.alloc(8+png.length);
  chunk.write(type,0,4,'ascii');
  chunk.writeUInt32BE(chunk.length,4);
  png.copy(chunk,8);
  iconChunks.push(chunk);
  iconLength+=chunk.length;
}
const iconHeader=Buffer.alloc(8);
iconHeader.write('icns',0,4,'ascii');
iconHeader.writeUInt32BE(iconLength,4);
await writeFile(`${resources}/Wapacal.icns`,Buffer.concat([iconHeader,...iconChunks]));
const parser=(await readFile('src/calendar.mjs','utf8')).replace(/^import .*$/gm,'').replace(/^export /gm,'');
const engine=await readFile('node_modules/ical.js/dist/ical.es5.min.cjs','utf8');
const layout=(await readFile('src/layout.mjs','utf8')).replace(/^export /gm,'');
const suggestions=(await readFile('src/suggestions.mjs','utf8')).replace(/^export /gm,'');
const editor=await readFile('src/native-editor.js','utf8');
const {subscriptionUrl,subscriptions,...workerConfig}=config;
const scriptJson=value=>JSON.stringify(value).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
// No preview template or browser editor is shipped in the application.
await writeFile(`${resources}/calendar-worker.html`,`<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; img-src blob: data:; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
</head><body><script>${engine}\n${parser}\n${layout}\n${suggestions}\nconst config=${scriptJson(workerConfig)};\n${editor}</script></body></html>`);
await writeFile(`${resources}/seed.json`,JSON.stringify(seed));
await writeFile(`${resources}/ICAL-LICENSE`,await readFile('node_modules/ical.js/LICENSE'));
// File Provider can attach metadata anywhere inside the generated bundle.
execFileSync('xattr',['-cr',bundle]);
try { execFileSync('xattr',['-d','com.apple.FinderInfo',bundle],{stdio:'ignore'}); } catch {}
execFileSync('codesign',['--force','--sign','-',bundle],{stdio:'inherit'});
await mkdir('output',{recursive:true});
await rm(outputBundle,{recursive:true,force:true});
await rename(bundle,outputBundle);
let verified=false;
for(let attempt=0;attempt<5&&!verified;attempt++){
  await new Promise(resolve=>setTimeout(resolve,50));
  execFileSync('xattr',['-cr',outputBundle]);
  try {
    execFileSync('codesign',['--verify','--deep','--strict',outputBundle],{stdio:'ignore'});
    verified=true;
  } catch {}
}
if(!verified)execFileSync('codesign',['--verify','--deep','--strict',outputBundle],{stdio:'inherit'});
console.log(outputBundle);
