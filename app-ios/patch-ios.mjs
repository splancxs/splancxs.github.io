// Adatta il progetto Xcode generato da "npx cap add ios" (gira su macOS, dentro GitHub Actions):
// permessi di Apple Salute, entitlement HealthKit, solo verticale, icona e schermata di avvio di Recomp.
import { execFileSync } from 'node:child_process';
import { copyFileSync, readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const APP = 'ios/App/App';
const plist = join(APP, 'Info.plist');
const pl = (...args) => execFileSync('plutil', [...args, plist], { stdio: 'inherit' });

// 1. Info.plist
pl('-replace', 'NSHealthShareUsageDescription', '-string',
  'Recomp legge da Salute peso, grasso corporeo e passi per aggiornare i tuoi progressi.');
pl('-replace', 'NSHealthUpdateUsageDescription', '-string',
  'Recomp scrive in Salute i pesi che registri nell\'app.');
pl('-replace', 'UISupportedInterfaceOrientations', '-json', '["UIInterfaceOrientationPortrait"]');
pl('-replace', 'UIViewControllerBasedStatusBarAppearance', '-bool', 'YES');
pl('-replace', 'ITSAppUsesNonExemptEncryption', '-bool', 'NO');

// 2. Entitlement HealthKit
copyFileSync('App.entitlements', join(APP, 'App.entitlements'));
const pbx = 'ios/App/App.xcodeproj/project.pbxproj';
let p = readFileSync(pbx, 'utf8');
if (!p.includes('CODE_SIGN_ENTITLEMENTS')) {
  p = p.replaceAll('INFOPLIST_FILE = App/Info.plist;', 'CODE_SIGN_ENTITLEMENTS = App/App.entitlements;\n\t\t\t\tINFOPLIST_FILE = App/Info.plist;');
  writeFileSync(pbx, p);
}

// 3. Icona e schermata di avvio (ridimensionate con sips alla misura di ogni file del template)
function fill(dir, src) {
  if (!existsSync(dir)) return;
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.png'))) {
    const dest = join(dir, f);
    const w = execFileSync('sips', ['-g', 'pixelWidth', dest]).toString().match(/pixelWidth: (\d+)/)[1];
    const h = execFileSync('sips', ['-g', 'pixelHeight', dest]).toString().match(/pixelHeight: (\d+)/)[1];
    copyFileSync(src, dest);
    execFileSync('sips', ['-z', h, w, dest], { stdio: 'ignore' });
  }
}
fill(join(APP, 'Assets.xcassets/AppIcon.appiconset'), 'resources/icon-1024.png');
fill(join(APP, 'Assets.xcassets/Splash.imageset'), 'resources/splash-2732.png');

console.log('Progetto iOS adattato.');
