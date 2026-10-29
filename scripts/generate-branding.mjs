// Run from any directory: node scripts/generate-branding.mjs
// Uses the image renderer already installed with Next.js; adds no dependencies.
import { readFile, writeFile, mkdir, access } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const webRequire = createRequire(resolve(root, 'web-app/package.json'));
const nextRequire = createRequire(webRequire.resolve('next/package.json'));
const sharp = nextRequire('sharp');
const blue = '#2563EB', white = '#FFFFFF';
const source = await readFile(resolve(root, 'branding/visionpark-falcon.svg'), 'utf8');
const paths = [...source.matchAll(/<path\b[^>]*\bd="([^"]+)"/g)].map(match => match[1]);
const viewBox = source.match(/viewBox="([^"]+)"/)[1];
const [vx, vy, vw, vh] = viewBox.split(' ').map(Number);
const shapes = paths.map(d => `<path fill-rule="evenodd" d="${d}"/>`).join('');
const mark = colour => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}" fill="${colour}">${shapes}</svg>\n`;
const square = (background = blue, foreground = white, width = 768) => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="${background}"/><svg x="${(1024 - width) / 2}" y="${(1024 - width * vh / vw) / 2}" width="${width}" height="${width * vh / vw}" viewBox="${viewBox}" fill="${foreground}">${shapes}</svg></svg>\n`;
async function save(path, data) {
  const target = resolve(root, path);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, data);
}
async function png(path, size, svg = square()) {
  await save(path, await sharp(Buffer.from(svg)).resize(size, size).removeAlpha().png().toBuffer());
}
async function ico(path) {
  const sizes = [16, 32, 48, 256];
  const images = await Promise.all(sizes.map(size => sharp(Buffer.from(square(blue, white, 880))).resize(size).png().toBuffer()));
  const header = Buffer.alloc(6 + sizes.length * 16);
  header.writeUInt16LE(1, 2); header.writeUInt16LE(sizes.length, 4);
  let offset = header.length;
  sizes.forEach((size, index) => {
    const at = 6 + index * 16;
    header[at] = size === 256 ? 0 : size; header[at + 1] = header[at];
    header.writeUInt16LE(1, at + 4); header.writeUInt16LE(32, at + 6);
    header.writeUInt32LE(images[index].length, at + 8); header.writeUInt32LE(offset, at + 12);
    offset += images[index].length;
  });
  await save(path, Buffer.concat([header, ...images]));
}

for (const folder of ['branding', 'web-app/public/branding', 'mobile/assets/branding']) {
  await save(`${folder}/visionpark-falcon-blue.svg`, mark(blue));
  await save(`${folder}/visionpark-falcon-white.svg`, mark(white));
  await save(`${folder}/visionpark-blue-on-white.svg`, square(white, blue));
  await save(`${folder}/visionpark-white-on-blue.svg`, square());
}
await save('web-app/src/app/icon.svg', square());
await png('web-app/src/app/apple-icon.png', 180);
await ico('web-app/src/app/favicon.ico');
for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
  await png(`mobile/android/app/src/main/res/mipmap-${density}/ic_launcher.png`, size);
}
await save('mobile/android/app/src/main/res/values/brand_colors.xml', `<?xml version="1.0" encoding="utf-8"?>\n<resources><color name="brand_blue">${blue}</color></resources>\n`);
await save('mobile/android/app/src/main/res/drawable/ic_launcher_foreground.xml', `<?xml version="1.0" encoding="utf-8"?>\n<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1536" android:viewportHeight="1536"><group android:translateX="76.8" android:translateY="307.2" android:scaleX="0.9" android:scaleY="0.9">${paths.map(d => `<path android:fillColor="${white}" android:fillType="evenOdd" android:pathData="${d}"/>`).join('')}</group></vector>\n`);
await save('mobile/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml', '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/brand_blue"/><foreground android:drawable="@drawable/ic_launcher_foreground"/></adaptive-icon>\n');
const iosFolder = 'mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset';
const ios = JSON.parse(await readFile(resolve(root, iosFolder, 'Contents.json'), 'utf8'));
for (const icon of ios.images) {
  await png(`${iosFolder}/${icon.filename}`, Math.round(parseFloat(icon.size) * parseFloat(icon.scale)));
}
for (const size of [192, 512]) {
  await png(`mobile/web/icons/Icon-${size}.png`, size);
  await png(`mobile/web/icons/Icon-maskable-${size}.png`, size, square(blue, white, 680));
}
await png('mobile/web/favicon.png', 32, square(blue, white, 880));
const macFolder = 'mobile/macos/Runner/Assets.xcassets/AppIcon.appiconset';
try {
  await access(resolve(root, macFolder, 'Contents.json'));
  const mac = JSON.parse(await readFile(resolve(root, macFolder, 'Contents.json'), 'utf8'));
  for (const icon of mac.images) await png(`${macFolder}/${icon.filename}`, parseFloat(icon.size) * parseFloat(icon.scale));
} catch (error) { if (error.code !== 'ENOENT') throw error; }
await ico('mobile/windows/runner/resources/app_icon.ico');

// Native Flutter paths keep the logo vector-sharp without adding an SVG package.
const arity = { M: 2, L: 2, C: 6, Z: 0 };
const methods = { M: 'moveTo', L: 'lineTo', C: 'cubicTo', Z: 'close' };
const commands = [];
for (const d of paths) {
  const tokens = d.match(/[MLCZ]|-?\d+(?:\.\d+)?/g);
  while (tokens.length) {
    const command = tokens.shift();
    if (!(command in arity)) throw new Error(`Unsupported vector command: ${command}`);
    commands.push(`  ..${methods[command]}(${tokens.splice(0, arity[command]).join(', ')})`);
  }
}
await save('mobile/lib/shared/brand_falcon.g.dart', `// Generated by scripts/generate-branding.mjs. Edit branding/visionpark-falcon.svg.\nimport 'package:flutter/material.dart';\n\nconst falconViewBox = Rect.fromLTWH(${vx}, ${vy}, ${vw}, ${vh});\nfinal falconPath = Path()\n  ..fillType = PathFillType.evenOdd\n${commands.join('\n')};\n`);
await png('branding/brand-preview.png', 768, square(white, blue));
console.log('Generated falcon vectors, native Flutter paths, favicon, and launcher icons.');
