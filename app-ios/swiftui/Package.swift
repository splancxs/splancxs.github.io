// swift-tools-version: 6.0
// App iPhone di Recomp scritta in SwiftUI (niente Capacitor, niente sito dentro). La costruisce xtool da Windows:
// app-ios/xtool/installa-nuova.sh.
import PackageDescription

// Il linker di xtool (lld) scrive «sdk 17.0» nel file: iOS allora non applica il Liquid Glass.
// Con -platform_version dico l'SDK vero. Il resto serve alla firma e alle estensioni:
//   -headerpad  lascia spazio per la firma nel file
//   -u _main    obbliga a includere il codice dell'estensione, che altrimenti il linker scarta (esce un guscio vuoto)
let linker: [LinkerSetting] = [.unsafeFlags([
    "-Xlinker", "-platform_version", "-Xlinker", "ios", "-Xlinker", "18.0", "-Xlinker", "27.0",
    "-Xlinker", "-headerpad", "-Xlinker", "0x4000",
    "-Xlinker", "-u", "-Xlinker", "_main",
])]

let package = Package(
    name: "RecompNuova",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "RecompNuova", targets: ["RecompNuova"]),
        .library(name: "RecompLive", targets: ["RecompLive"]),
    ],
    targets: [
        .target(
            name: "RecompNuova",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: linker
        ),
        .target(
            name: "RecompLive",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: linker
        ),
    ]
)
