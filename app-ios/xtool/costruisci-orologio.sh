#!/bin/bash
# Compila e collega da Linux l'app per Apple Watch (RecompWatch) e la complicazione (RecompWatchWidgets).
# Risultato: $LAVORO/orologio/out/RecompWatch.app, pronto da mettere in Watch/ dentro l'app iPhone.
# L'orologio SE 3 ha il processore a 64 bit: si compila per arm64 (arm64_32 è dei modelli più vecchi).
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$QUI/../.." && pwd)"
. "$QUI/config.sh"
. "$HOME/.local/share/swiftly/env.sh"

B="$SDK_OROLOGIO"
SDK="$B/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS27.0.sdk"
XC="$B/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib"
RES="$XC/swift"
TOOLS="$B/toolset/bin"
RT="$XC/clang/21/lib/darwin/libclang_rt.watchos.a"
W="$LAVORO/${WATCH_DIR:-orologio}"   # cartella di lavoro: l'app «Recomp 2» (installa-nuova.sh) ne usa una sua
APP="$W/out/RecompWatch.app"
EXT="$APP/PlugIns/RecompWatchWidgets.appex"
PHONE="${PHONE_ID:-io.github.splancxs.recomp.prova}"   # identificativo dell'app iPhone (xtool.yml); xtool poi aggiunge il suo prefisso
GRUPPO="${GROUP_ID:-group.io.github.splancxs.recomp}"   # gruppo condiviso con la complicazione
NOME="${WATCH_NAME:-Recomp}"

# le intestazioni del compilatore di questo PC al posto di quelle di Xcode (lo fa «xtool sdk install», qui l'SDK non è installato)
if [ ! -d "$RES/clang/include" ]; then
  cp -r "$(dirname "$(dirname "$(readlink -f "$(command -v swift)")")")/lib/clang/21/include" "$RES/clang/include"
fi

rm -rf "$W"
mkdir -p "$W/src" "$W/src2" "$W/obj" "$W/obj2" "$APP" "$EXT"
cp "$REPO/app-ios/native/Watch/App/"*.swift "$REPO/app-ios/native/Watch/Shared/WatchModel.swift" "$W/src/"
cp "$REPO/app-ios/native/Watch/Widgets/RecompWatchWidgets.swift" "$REPO/app-ios/native/Watch/Shared/WatchModel.swift" "$W/src2/"

SW=(-target arm64-apple-watchos10.0 -sdk "$SDK" -resource-dir "$RES" -Xfrontend -enable-cross-import-overlays -swift-version 5)
# lld dice che non supporta watchOS: è solo un avviso. Il «driver» di Swift userebbe un altro linker, quindi si lancia a mano.
LLD=("$TOOLS/ld64.lld" -demangle -dynamic -arch arm64 -platform_version watchos 10.0.0 27.0.0 -syslibroot "$SDK"
     "-L$RES/watchos" "-L$SDK/usr/lib/swift" -headerpad 0x4000)
senza_avvisi() { { grep -v "warning:" || true; }; }

echo "• app Watch: compilo…"
swiftc "${SW[@]}" -parse-as-library -module-name RecompWatch -O -wmo -emit-object -o "$W/obj/RecompWatch.o" "$W"/src/*.swift
echo "• app Watch: collego…"
"${LLD[@]}" -rpath /usr/lib/swift -rpath @executable_path/Frameworks "$W/obj/RecompWatch.o" "$RT" -lSystem \
  -o "$APP/RecompWatch" 2>&1 | senza_avvisi

echo "• complicazione: compilo e collego…"
swiftc "${SW[@]}" -application-extension -parse-as-library -module-name RecompWatchWidgets -O -wmo -emit-object \
  -o "$W/obj2/ext.o" "$W"/src2/*.swift
"${LLD[@]}" -application_extension -e _NSExtensionMain -rpath /usr/lib/swift -rpath @executable_path/../../Frameworks \
  "$W/obj2/ext.o" "$RT" -framework Foundation -lSystem -o "$EXT/RecompWatchWidgets" 2>&1 | senza_avvisi

[ -s "$APP/RecompWatch" ] && [ -s "$EXT/RecompWatchWidgets" ] || { echo "Collegamento non riuscito"; exit 1; }

python3 - "$PHONE" "$APP" "$EXT" "$GRUPPO" "$NOME" <<'EOF'
import plistlib, sys
phone, app, ext, gruppo, nome = sys.argv[1:6]
common = {
    "CFBundleDevelopmentRegion": "it", "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "1",
    "CFBundleSupportedPlatforms": ["WatchOS"], "DTPlatformName": "watchos", "DTPlatformVersion": "27.0",
    "DTSDKName": "watchos27.0", "MinimumOSVersion": "10.0", "UIDeviceFamily": [4],
}
watch = dict(common, **{
    "CFBundleDisplayName": nome, "CFBundleExecutable": "RecompWatch",
    "CFBundleIdentifier": phone + ".watchkitapp", "CFBundleName": "RecompWatch", "CFBundlePackageType": "APPL",
    "NSHealthShareUsageDescription": "Recomp legge battito e calorie durante l'allenamento per mostrarteli sull'orologio.",
    "NSHealthUpdateUsageDescription": "Recomp salva i tuoi allenamenti in Salute, così contano negli anelli Attività.",
    "WKApplication": True, "WKBackgroundModes": ["workout-processing", "physical-therapy"],
    "WKCompanionAppBundleIdentifier": phone,
    # icona: xtool/lld non hanno il compilatore di cataloghi di Apple, quindi un PNG sciolto
    "CFBundleIconFile": "AppIcon",
    "CFBundleIcons": {"CFBundlePrimaryIcon": {"CFBundleIconFiles": ["AppIcon"], "CFBundleIconName": "AppIcon"}},
})
widgets = dict(common, **{
    "CFBundleDisplayName": nome, "CFBundleExecutable": "RecompWatchWidgets",
    "CFBundleIdentifier": phone + ".watchkitapp.widgets", "CFBundleName": "RecompWatchWidgets",
    "CFBundlePackageType": "XPC!", "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
})
for d, v in ((app, watch), (ext, widgets)):
    plistlib.dump(v, open(d + "/Info.plist", "wb"))
# permessi richiesti: li legge xtool (patchato) per creare gli identificativi e i profili, poi cancella il file
plistlib.dump({"com.apple.developer.healthkit": True,
               "com.apple.security.application-groups": [gruppo]},
              open(app + "/xtool-entitlements.plist", "wb"))
plistlib.dump({"com.apple.security.application-groups": [gruppo]},
              open(ext + "/xtool-entitlements.plist", "wb"))
EOF
cp "$REPO/app-ios/resources/icon-1024.png" "$APP/AppIcon.png"
echo "• app Watch pronta: $APP"
