import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

if (process.platform !== 'darwin') throw new Error('Release packaging requires macOS.');
if (process.argv.length !== 2) throw new Error('Usage: npm run package:release');
const { version } = JSON.parse(await readFile('package.json', 'utf8'));
if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error('Invalid package version.');
if (!['arm64', 'x64'].includes(process.arch)) throw new Error('Unsupported Mac architecture.');
if (process.env.GITHUB_REF_TYPE === 'tag' && process.env.GITHUB_REF_NAME !== `v${version}`)
  throw new Error('Release tag must match the package.json version.');

// Always rebuild without private seed data, even if output contains a private app.
execFileSync(process.execPath, ['scripts/build-native.mjs'], { stdio: 'inherit' });
const bundle = resolve('output/Wapacal.app');
const expectedSeed = { subscriptions: [], courseCode: '', editor: { mode: 'month' } };
const seed = JSON.parse(await readFile(join(bundle, 'Contents/Resources/seed.json'), 'utf8'));
if (JSON.stringify(seed) !== JSON.stringify(expectedSeed))
  throw new Error('Refusing to package an app with unexpected seed data.');
const architecture = process.arch === 'arm64' ? 'arm64' : 'x86_64';
execFileSync('lipo', [join(bundle, 'Contents/MacOS/Wapacal'), '-verify_arch', architecture]);
await mkdir('output/releases', { recursive: true });
const filename = `Wapacal-${version}-macOS-${architecture}.zip`;
const archive = resolve('output/releases', filename);
const temporary = await mkdtemp(join(tmpdir(), 'wapacal-release-'));
try {
  await rm(archive, { force: true });
  execFileSync('ditto', ['-c', '-k', '--sequesterRsrc', '--keepParent', bundle, archive]);
  // Verify the actual download after extracting it, including its signature and seed.
  execFileSync('ditto', ['-x', '-k', archive, temporary]);
  const extracted = join(temporary, 'Wapacal.app');
  execFileSync('codesign', ['--verify', '--deep', '--strict', extracted], { stdio: 'inherit' });
  if (
    (await readFile(join(extracted, 'Contents/Resources/seed.json'), 'utf8')) !==
    JSON.stringify(expectedSeed)
  )
    throw new Error('Packaged seed data did not match the public build.');
  const checksum = createHash('sha256')
    .update(await readFile(archive))
    .digest('hex');
  await writeFile(`${archive}.sha256`, `${checksum}  ${filename}\n`);
  console.log(`Release archive: ${archive}`);
} catch (error) {
  await rm(archive, { force: true });
  await rm(`${archive}.sha256`, { force: true });
  throw error;
} finally {
  await rm(temporary, { recursive: true, force: true });
}
