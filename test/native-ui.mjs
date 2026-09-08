import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFile,writeFile,mkdir,mkdtemp,copyFile} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {loadFixtureApp} from './helpers/fixture-app.mjs';

test('AppKit interface and detached WebKit worker integrate using isolated fixture data',{timeout:120000},async()=>{
 const temp=await mkdtemp(join(tmpdir(),'wapacal-native-ui-'));
 const bundle=join(temp,'WapacalUITest.app'),resources=join(bundle,'Contents/Resources');
 await mkdir(resources,{recursive:true});await mkdir(join(bundle,'Contents/MacOS'),{recursive:true});
 await writeFile(join(bundle,'Contents/Info.plist'),`<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>WapacalUITest</string><key>CFBundleIdentifier</key><string>local.wapacal.uitest</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`);
 await copyFile('output/Wapacal.app/Contents/Resources/calendar-worker.html',join(resources,'calendar-worker.html'));
 const {seed,config}=await loadFixtureApp();
 await writeFile(join(resources,'seed.json'),JSON.stringify({...seed,subscriptions:[{id:'legacy',legacyIds:true,name:'Fixture calendar',kind:'timeedit',url:'https://example.invalid/calendar.ics',ics:seed.ics,fetchedAt:seed.fetchedAt}],refreshInterval:1800,nextCheck:Date.now()/1000+86400,
  editor:{...config.module,mode:'module',theme:'light',course:config.course,timeZone:config.timeZone,width:2880,height:1800,futureSetting:'kept'}}));
 const source=(await readFile('native/Wallpaper.swift','utf8')).split('let args = Array')[0]+'\n'+
  (await Promise.all(['native/CalendarEngine.swift','native/EditorView.swift','native/Editor.swift','test/native-ui.swift'].map(file=>readFile(file,'utf8')))).join('\n');
 await writeFile(join(temp,'main.swift'),source);
 const binary=join(bundle,'Contents/MacOS/WapacalUITest');
 execFileSync('swiftc',['-target',`${process.arch==='arm64'?'arm64':'x86_64'}-apple-macosx13.0`,'-module-cache-path','/tmp/wapacal-swift-cache',join(temp,'main.swift'),'-o',binary],{stdio:'pipe'});
 execFileSync('xattr',['-cr',bundle]);execFileSync('codesign',['--force','--sign','-',bundle],{stdio:'pipe'});
 const output=execFileSync(binary,[],{encoding:'utf8',timeout:90000,env:{...process.env,WAPACAL_APP_SUPPORT:join(temp,'support'),WAPACAL_LEGACY_WORKSPACE:join(temp,'legacy'),WAPACAL_UI_OUTPUT:temp}});
 assert.match(output,/integration checks passed/);
 console.log(`Native UI screenshots and exports: ${temp}`);
});
