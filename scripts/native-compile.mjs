import {execFileSync} from 'node:child_process';

// App and test executables compile the same production files with separate entry points.
const sources = [
  'native/Wallpaper.swift',
  'native/CalendarEngine.swift',
  'native/EditorView.swift',
  'native/Editor.swift'
];

export function compileNative(entryPoint, output, {stdio = 'inherit'} = {}) {
  execFileSync('swiftc', [
    '-target', `${process.arch === 'arm64' ? 'arm64' : 'x86_64'}-apple-macosx13.0`,
    '-module-cache-path', '/tmp/wapacal-swift-cache',
    ...sources, entryPoint, '-o', output
  ], {stdio});
}
