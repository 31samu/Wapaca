import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFile,writeFile,mkdtemp,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import sharp from 'sharp';
import {renderWallpaper} from '../src/layout.mjs';
import {loadFixtureApp} from './helpers/fixture-app.mjs';
const binary=resolve('output/Wapacal.app/Contents/MacOS/Wapacal');
test('native export imports, validates both frames, and rejects invalid inputs without overwriting',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'wapacal-heic-'));
 const {data,config}=await loadFixtureApp();
 const images={};
 for(const theme of ['light','dark']){
  images[theme]=join(dir,`${theme}.png`);
  const rendered=renderWallpaper(data.events,{...config,...config.module,mode:'module',theme});
  await sharp(Buffer.from(rendered.svg)).png().toFile(images[theme]);
 }
 const pair={version:1,name:'Test',light:(await readFile(images.light)).toString('base64'),dark:(await readFile(images.dark)).toString('base64')};
 const source=join(dir,'test.wapacal'),output=join(dir,'test.heic');
 await writeFile(source,JSON.stringify(pair));
 const info=JSON.parse(execFileSync(binary,['import',source,output],{encoding:'utf8'}));
 assert.deepEqual(info,{frameCount:2,width:3024,height:1964,lightIndex:0,darkIndex:1});
 execFileSync(binary,['inspect',output,dir]);
 for(const theme of ['light','dark']){
  const actual=await sharp(join(dir,theme+'.png')).removeAlpha().raw().toBuffer();
  const expected=await sharp(images[theme]).removeAlpha().raw().toBuffer();
  assert.equal(actual.length,expected.length);
  let error=0;for(let i=0;i<actual.length;i++)error+=Math.abs(actual[i]-expected[i]);
  assert.ok(error/actual.length<3,`${theme}: average channel error ${error/actual.length}`);
 }
 const original=await readFile(output);
 pair.version=99;await writeFile(source,JSON.stringify(pair));
 assert.notEqual(spawnSync(binary,['import',source,output]).status,0);
 assert.deepEqual(await readFile(output),original);
 const small=join(dir,'small.png');await sharp({create:{width:10,height:10,channels:3,background:'#fff'}}).png().toFile(small);
 const failed=spawnSync(binary,['encode',small,images.dark,output]);
 assert.notEqual(failed.status,0);assert.match(failed.stderr.toString(),/same dimensions/);
 assert.deepEqual(await readFile(output),original);
 assert.notEqual(spawnSync(binary,['inspect',small]).status,0);
});

test('missing wallpaper sources can be recorded without blocking Apply and old backups still decode',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'wapacal-backup-'));
 const source=(await readFile('native/Wallpaper.swift','utf8')).split('final class WallpaperApp:')[0];
 const file=join(dir,'backup.swift');
 await writeFile(file,source+`
let missing = URL(fileURLWithPath: "/nonexistent/wapacal-test-wallpaper.png")
for url in [nil, missing, URL(string: "https://example.com/image.png")] as [URL?] {
 let record = WallpaperBackup(screenID: "test", url: url, options: [.imageScaling: 3, .allowClipping: true])
 let decoded = try JSONDecoder().decode(WallpaperBackup.self, from: JSONEncoder().encode(record))
 assert(!decoded.canRestore)
 assert(decoded.url == url)
 assert(decoded.scaling == 3 && decoded.clipping == true)
}
let old = #"{"screen":"test","url":"file:///System/Library/CoreServices/SystemVersion.plist","scaling":3,"clipping":true}"#.data(using: .utf8)!
let decoded = try JSONDecoder().decode(WallpaperBackup.self, from: old)
assert(decoded.canRestore)
print("Backup regression checks passed")
`);
 assert.match(execFileSync('swift',['-module-cache-path','/tmp/wapacal-swift-cache',file],{encoding:'utf8'}),/checks passed/);
});

test('refresh frequency accepts only the choices shown in the app',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'wapacal-cache-'));
 const policy=(await readFile('native/Editor.swift','utf8')).split('final class EditorApp:')[0];
 const file=join(dir,'policy.swift');
 await writeFile(file,'import Foundation\n'+policy+`
assert(savedRefreshInterval(nil) == 3600)
assert(savedRefreshInterval(900) == 900)
assert(savedRefreshInterval(1800) == 1800)
assert(savedRefreshInterval(86400) == 86400)
assert(savedRefreshInterval(0) == 3600)
assert(savedRefreshInterval(-1) == 3600)
assert(savedRefreshInterval(.nan) == 3600)
assert(savedRefreshInterval(.infinity) == 3600)
print("Cache policy checks passed")
`);
 assert.match(execFileSync('swift',['-module-cache-path','/tmp/wapacal-swift-cache',file],{encoding:'utf8'}),/checks passed/);
});

test('legacy runtime data migrates to app support and reset preserves active recovery records',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'wapacal-storage-'));
 const legacy=join(dir,'legacy'),support=join(dir,'support');
 await mkdir(join(legacy,'applied'),{recursive:true});
 await Promise.all([
  writeFile(join(legacy,'app-state.json'),'{}'),
  writeFile(join(legacy,'editor-wallpaper.heic'),'editor'),
  writeFile(join(legacy,'restore-display.json'),'{}'),
  writeFile(join(legacy,'restored-old.json'),'{}'),
  writeFile(join(legacy,'applied','old.heic'),'wallpaper')
 ]);
 const source=(await readFile('native/Wallpaper.swift','utf8')).split('final class WallpaperApp:')[0];
 const file=join(dir,'storage.swift');
 await writeFile(file,source+`
try migrateLegacyWorkspace()
let files = FileManager.default
assert(files.fileExists(atPath: stateDirectory().appendingPathComponent("app-state.json").path))
assert(files.fileExists(atPath: recoveryDirectory().appendingPathComponent("restore-display.json").path))
assert(files.fileExists(atPath: recoveryDirectory().appendingPathComponent("restored-old.json").path))
assert(files.fileExists(atPath: appliedDirectory().appendingPathComponent("old.heic").path))
assert(!files.fileExists(atPath: legacyWorkspaceDirectory().appendingPathComponent("app-state.json").path))
try resetInactiveRuntimeData()
assert(!files.fileExists(atPath: stateDirectory().appendingPathComponent("app-state.json").path))
assert(files.fileExists(atPath: recoveryDirectory().appendingPathComponent("restore-display.json").path))
assert(!files.fileExists(atPath: recoveryDirectory().appendingPathComponent("restored-old.json").path))
assert(!files.fileExists(atPath: appliedDirectory().appendingPathComponent("old.heic").path))
print("Storage migration checks passed")
`);
 const output=execFileSync('swift',['-module-cache-path','/tmp/wapacal-swift-cache',file],{encoding:'utf8',env:{...process.env,WAPACAL_APP_SUPPORT:support,WAPACAL_LEGACY_WORKSPACE:legacy}});
 assert.match(output,/checks passed/);
});
