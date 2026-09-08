import {mkdir,writeFile,readFile,mkdtemp} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {loadSnapshots} from '../src/subscriptions.mjs';
const bundle='output/Wapacal.app';
await mkdir(`${bundle}/Contents/MacOS`,{recursive:true});
await writeFile(`${bundle}/Contents/Info.plist`,`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Wapacal</string>
<key>CFBundleIdentifier</key><string>local.wapacal.app</string>
<key>CFBundleName</key><string>Wapacal</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Wapacal export</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSItemContentTypes</key><array><string>local.wapacal.export</string><string>local.timetable.export</string></array></dict></array>
<key>UTExportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>local.wapacal.export</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeDescription</key><string>Wapacal light/dark export</string><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>wapacal</string></array></dict></dict></array>
<key>UTImportedTypeDeclarations</key><array><dict><key>UTTypeIdentifier</key><string>local.timetable.export</string><key>UTTypeConformsTo</key><array><string>public.json</string></array><key>UTTypeDescription</key><string>Legacy Wapacal export</string><key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>timetable</string></array></dict></dict></array>
</dict></plist>`);
const temp=await mkdtemp(join(tmpdir(),'wapacal-build-'));
const native=(await readFile('native/Wallpaper.swift','utf8')).replace('let args = Array', (await readFile('native/Editor.swift','utf8'))+'\nlet args = Array').replace('let delegate = WallpaperApp()', 'let delegate = EditorApp()');
await writeFile(join(temp,'main.swift'),native);
execFileSync('swiftc',['-module-cache-path','/tmp/wapacal-swift-cache',join(temp,'main.swift'),'-o',`${bundle}/Contents/MacOS/Wapacal`],{stdio:'inherit'});
const resources=`${bundle}/Contents/Resources`;
await mkdir(resources,{recursive:true});
const config=JSON.parse(await readFile('config.local.json','utf8').catch(()=>readFile('config.example.json','utf8')));
const metadata=JSON.parse(await readFile('data/source.json','utf8').catch(()=>'{}'));
const parser=(await readFile('src/calendar.mjs','utf8')).replace(/^import .*$/gm,'').replace(/^export /gm,'');
const engine=await readFile('node_modules/ical.js/dist/ical.es5.min.cjs','utf8');
const editor=await readFile('src/native-editor.js','utf8');
const preview=await readFile('output/preview.html','utf8');
await writeFile(`${resources}/editor.html`,preview.replace('</head>',`<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; connect-src 'none'">\n</head>`).replace('</body>',()=>`<script>${engine}\n${parser}\n${editor}</script></body>`));
await writeFile(`${resources}/seed.json`,JSON.stringify({subscriptions:await loadSnapshots(config),courseCode:config.course}));
await writeFile(`${resources}/ICAL-LICENSE`,await readFile('node_modules/ical.js/LICENSE'));
// File Provider can attach metadata anywhere inside the generated bundle.
execFileSync('xattr',['-cr',bundle]);
execFileSync('codesign',['--force','--sign','-',bundle],{stdio:'inherit'});
console.log(bundle);
