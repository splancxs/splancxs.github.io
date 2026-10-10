"""Modifiche al codice di xtool (https://github.com/xtool-org/xtool, commit d802c71) per fargli gestire l'Apple Watch.

xtool non sa fare app Watch: queste modifiche gli insegnano cinque cose. Sono scritte come sostituzioni di testo
(con controllo), così funzionano finché il codice di xtool è quello del commit indicato. Si possono rilanciare: salta
le modifiche già fatte.

Uso:  python applica-patch.py /percorso/di/xtool-src      poi:  swift build -c release --product xtool

 1. «xtool ds devices add --udid … --name …»: registra a mano un dispositivo (l'orologio non si vede via USB).
 2. Costruttore dell'SDK: include anche WatchOS (xtool lo scarta); serve a compilare l'app Watch.
 3. App Watch annidate: registra identificativi e profili anche per Watch/*.app e le loro estensioni, legge i permessi
    da un file xtool-entitlements.plist dentro il bundle (i binari fatti a mano non li hanno incorporati) e riscrive
    WKCompanionAppBundleIdentifier con il nuovo identificativo dell'app iPhone.
 4. I profili includono anche i dispositivi Apple Watch (prima solo iPhone, iPad, iPod).
5. Firma: ogni parte (app, estensioni, app Watch) usa i suoi permessi e il suo profilo (prima tutto con quelli
    dell'app principale), e con XTOOL_KEEP_SIGNED=<cartella> salva una copia dell'app firmata (serve per installare
    l'app Watch direttamente sull'orologio).
 6. I gruppi condivisi (App Groups) sono ammessi anche sui team gratuiti: la complicazione legge da lì i dati dell'app Watch.
"""
import sys
from pathlib import Path

R = Path(sys.argv[1])


def patch(rel, marker, pairs):
    p = R / rel
    s = p.read_text(encoding="utf-8")
    if marker in s:
        print("già applicata:", rel, "→", marker)
        return
    for old, new in pairs:
        assert old in s, f"{rel}: testo da sostituire non trovato (versione di xtool diversa?):\n{old[:120]}"
        s = s.replace(old, new, 1)
    p.write_text(s, encoding="utf-8")
    print("applicata:", rel, "→", marker)


# 1 ─ xtool ds devices add
patch("Sources/XToolSupport/DSCommands/DSDevicesCommand.swift", "DSDevicesAddCommand", [(
    """        subcommands: [
            DSDevicesListCommand.self,
        ],""",
    """        subcommands: [
            DSDevicesListCommand.self,
            DSDevicesAddCommand.self,
        ],"""), (
    """struct DSDevicesListCommand: AsyncParsableCommand {""",
    """// Registra a mano un dispositivo con il suo UDID (utile per l'Apple Watch, che xtool non vede via USB).
struct DSDevicesAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Register a device by UDID"
    )

    @Option(help: "UDID of the device") var udid: String
    @Option(help: "Name shown in the developer portal") var name: String

    func run() async throws {
        let client = DeveloperAPIClient(auth: try AuthToken.saved().authData())
        let response = try await client.devicesCreateInstance(
            body: .json(.init(data: .init(
                _type: .devices,
                attributes: .init(
                    name: name,
                    platform: .init(.ios),
                    udid: udid
                )
            )))
        )
        if (try? response.conflict) != nil {
            print("Already registered: \\(udid)")
            return
        }
        _ = try response.created
        print("Registered: \\(name) (\\(udid))")
    }
}

struct DSDevicesListCommand: AsyncParsableCommand {""")])

# 2 ─ SDK con watchOS
patch("Sources/XToolSupport/SDKBuilder.swift", "watchOSSDK", [
    ('        let macOSSDK = try sdk(platform: "MacOSX", prefix: "MacOSX")\n',
     '        let macOSSDK = try sdk(platform: "MacOSX", prefix: "MacOSX")\n'
     '        let watchOSSDK = try sdk(platform: "WatchOS", prefix: "WatchOS")\n'),
    ('        - \\(macOSSDK)\n        """)', '        - \\(macOSSDK)\n        - \\(watchOSSDK)\n        """)'),
    ('                "x86_64-apple-macosx": triple(platform: "MacOSX", sdk: macOSSDK),\n',
     '                "x86_64-apple-macosx": triple(platform: "MacOSX", sdk: macOSSDK),\n'
     '                "arm64_32-apple-watchos": triple(platform: "WatchOS", sdk: watchOSSDK),\n'
     '                "arm64-apple-watchos": triple(platform: "WatchOS", sdk: watchOSSDK),\n'),
    ('for platform in ["iPhoneOS", "MacOSX", "iPhoneSimulator"] {',
     'for platform in ["iPhoneOS", "MacOSX", "iPhoneSimulator", "WatchOS"] {'),
    ('E("Platforms", ["iPhoneOS", "MacOSX", "iPhoneSimulator"].map {',
     'E("Platforms", ["iPhoneOS", "MacOSX", "iPhoneSimulator", "WatchOS"].map {'),
])

# 3 ─ app Watch annidate e permessi dichiarati a parte
patch("Sources/XKit/DeveloperServices/App IDs/DeveloperServicesAddAppOperation.swift", "xtool-entitlements.plist", [(
    """        var entitlements: Entitlements
        // if the executable doesn't already have entitlements, that's
        // okay. We don't have to throw an error.
        if let entitlementsData = try? await context.signer.analyze(executable: executableURL),
            let decodedEntitlements = try? PropertyListDecoder().decode(Entitlements.self, from: entitlementsData) {
            entitlements = decodedEntitlements
""",
    """        var entitlements: Entitlements
        // Recomp: i binari costruiti a mano (app Watch) non hanno permessi incorporati: li dichiara il file
        // xtool-entitlements.plist dentro il bundle, che si toglie dopo la lettura.
        var declared: Entitlements?
        let sidecarURL = app.appendingPathComponent("xtool-entitlements.plist")
        if let sidecarData = try? Data(contentsOf: sidecarURL),
            let sidecarEntitlements = try? PropertyListDecoder().decode(Entitlements.self, from: sidecarData) {
            declared = sidecarEntitlements
            try? FileManager.default.removeItem(at: sidecarURL)
        } else if let entitlementsData = try? await context.signer.analyze(executable: executableURL),
            let decodedEntitlements = try? PropertyListDecoder().decode(Entitlements.self, from: entitlementsData) {
            declared = decodedEntitlements
        }
        // if the executable doesn't already have entitlements, that's
        // okay. We don't have to throw an error.
        if let decodedEntitlements = declared {
            entitlements = decodedEntitlements
"""), (
    """            apps += plugins.implicitContents.filter { $0.pathExtension.lowercased() == "appex" }
        }
""",
    """            apps += plugins.implicitContents.filter { $0.pathExtension.lowercased() == "appex" }
        }
        // Recomp: app Apple Watch incorporate in Watch/ e le loro estensioni (complicazioni)
        let watchDir = root.appendingPathComponent("Watch")
        if watchDir.dirExists {
            for watchApp in watchDir.implicitContents where watchApp.pathExtension.lowercased() == "app" {
                apps.append(watchApp)
                let watchPlugins = watchApp.appendingPathComponent("PlugIns")
                if watchPlugins.dirExists {
                    apps += watchPlugins.implicitContents.filter { $0.pathExtension.lowercased() == "appex" }
                }
            }
        }
""")])

patch("Sources/XKit/Signer/AutoSigner.swift", "WKCompanionAppBundleIdentifier", [(
    """            nsDict["CFBundleIdentifier"] = info.newBundleID
""",
    """            nsDict["CFBundleIdentifier"] = info.newBundleID
            // Recomp: l'app Watch deve puntare all'identificativo (già riscritto) dell'app iPhone che la contiene
            if nsDict["WKCompanionAppBundleIdentifier"] != nil {
                nsDict["WKCompanionAppBundleIdentifier"] = mainInfo.newBundleID
            }
""")])

# 4 ─ i profili includono l'Apple Watch
patch("Sources/XKit/DeveloperServices/Profiles/DeveloperServicesFetchProfileOperation.swift", ".appleWatch", [(
    "case .ipad, .iphone, .ipod: true", "case .ipad, .iphone, .ipod, .appleWatch: true")])

# 5 ─ firma: permessi e profilo di ogni parte; copia dell'app firmata
patch("Sources/XKit/Signer/SignerImpl.swift", "con una firma vera ogni parte", [(
    """        let entitlementMapping = entitlementMapping.filter { $0.key.path == app.path }
""",
    """        // Recomp: con una firma vera ogni parte (app, estensioni, app Watch) usa i suoi permessi;
        // con la firma «adhoc» (solo permessi incorporati) resta l'app principale
        var entitlementMapping = entitlementMapping
        if case .adhoc = identity {
            entitlementMapping = entitlementMapping.filter { $0.key.path == app.path }
        }
""")])

patch("Sources/XKit/Signer/AutoSigner.swift", "XTOOL_KEEP_SIGNED", [(
    """        progress(1)

        return mainInfo.newBundleID""",
    """        progress(1)

        // Recomp: se XTOOL_KEEP_SIGNED è impostata salvo una copia dell'app firmata in quella cartella
        if let keep = ProcessInfo.processInfo.environment["XTOOL_KEEP_SIGNED"] {
            let dest = URL(fileURLWithPath: keep, isDirectory: true).appendingPathComponent(app.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: app, to: dest)
        }

        return mainInfo.newBundleID""")])

# 6 ─ i gruppi condivisi (App Groups) ammessi sui team gratuiti (la complicazione legge i dati dell'app Watch da lì)
patch("Sources/XKit/DeveloperServices/App IDs/Entitlements/DeveloperServicesCapability.swift", "appGroups, isFree: true", [(
    "DeveloperServicesCapability(.appGroups, isFree: false)", "DeveloperServicesCapability(.appGroups, isFree: true)")])

# 5b ─ il firmatario in C++ (zsign, scaricato da SwiftPM in .build/checkouts): una risorsa di firma per ogni parte
zup = R / ".build/checkouts/zsign/src/lib/Zupersign.cpp"
if zup.exists():
    patch(".build/checkouts/zsign/src/lib/Zupersign.cpp", "std::list<ZSignAsset> assets;", [(
        """    ZBundle bundle;
    success = bundle.SignFolder(
        &asset,
        app_directory,""",
        """    ZBundle bundle;
    // Recomp: più parti con permessi diversi (app, estensioni, app Watch): una risorsa di firma ciascuna,
    // col profilo incorporato nella sua cartella; zsign sceglie quella il cui identificativo coincide.
    std::list<ZSignAsset> assets;
    if (!is_adhoc && num_entitlements > 1) {
        std::string root = app_directory;
        while (root.size() > 1 && root.back() == '/') root.pop_back();
        std::vector<size_t> order;
        for (size_t i = 0; i < num_entitlements; i++) {
            std::string p = entitlements[i].bundle_path;
            while (p.size() > 1 && p.back() == '/') p.pop_back();
            if (p == root) order.insert(order.begin(), i); else order.push_back(i);
        }
        for (size_t i : order) {
            string prov;
            ZFile::ReadFile((string(entitlements[i].bundle_path) + "/embedded.mobileprovision").c_str(), prov);
            assets.emplace_back();
            if (!assets.back().Init(
                    cert, pkey, prov,
                    string(static_cast<const char *>(entitlements[i].data), entitlements[i].len),
                    false, false, false)) {
                *exception = strdup("Invalid developer certificate/private key (bundle)");
                EVP_PKEY_free(pkey);
                X509_free(cert);
                return -1;
            }
        }
        success = bundle.SignFolder(
            &assets,
            app_directory,
            "",
            "",
            "",
            std::vector<string>(),
            std::vector<string>(),
            true,
            false,
            false,
            false
        );
    } else
    success = bundle.SignFolder(
        &asset,
        app_directory,""")])
else:
    print("NOTA: zsign non è ancora stato scaricato: lancia una volta «swift build», poi rilancia questo script.")
print("fatto")
