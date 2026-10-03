// Adatta il progetto Xcode generato da "npx cap add ios" (gira su macOS, dentro GitHub Actions):
// solo verticale, icona e schermata di avvio di Recomp, Live Activity del recupero, link recomp://.
import { execFileSync } from 'node:child_process';
import { copyFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const APP = 'ios/App/App';
const plist = join(APP, 'Info.plist');
const pl = (...args) => execFileSync('plutil', [...args, plist], { stdio: 'inherit' });

// 1. Info.plist
pl('-replace', 'UISupportedInterfaceOrientations', '-json', '["UIInterfaceOrientationPortrait"]');
pl('-replace', 'UIViewControllerBasedStatusBarAppearance', '-bool', 'YES');
pl('-replace', 'ITSAppUsesNonExemptEncryption', '-bool', 'NO');
pl('-replace', 'NSSupportsLiveActivities', '-bool', 'YES'); // conto alla rovescia del recupero sulla schermata di blocco
// link recomp://piano, recomp://scheda… aprono quella sezione (simulatore.sh «vai», Comandi Rapidi)
pl('-replace', 'CFBundleURLTypes', '-json', JSON.stringify([{ CFBundleURLName: 'io.github.splancxs.recomp', CFBundleURLSchemes: ['recomp'] }]));

// 2. Icona e schermata di avvio (ridimensionate con sips alla misura di ogni file del template)
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
