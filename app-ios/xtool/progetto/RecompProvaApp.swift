import SwiftUI
import UIKit
import Capacitor
import AppPlugin
import BrowserPlugin
import HapticsPlugin
import LocalNotificationsPlugin
import StatusBarPlugin

// Guscio dell'app per xtool: la pagina di Recomp dentro il motore di Capacitor (al posto di AppDelegate e storyboard).
struct BridgeView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CAPBridgeViewController { CAPBridgeViewController() }
    func updateUIViewController(_ vc: CAPBridgeViewController, context: Context) {}
}

@main
struct RecompProvaApp: App {
    init() {
        // Capacitor trova i plugin per nome (packageClassList): nominarli qui evita che il linker li scarti
        let plugins: [AnyClass] = [AppPlugin.self, CAPBrowserPlugin.self, HapticsPlugin.self,
                                   LocalNotificationsPlugin.self, StatusBarPlugin.self, NativeTabsPlugin.self,
                                   RestActivityPlugin.self, HealthPlugin.self, WatchBridgePlugin.self]
        print("Plugin collegati:", plugins.count)
    }

    var body: some Scene {
        WindowGroup {
            BridgeView()
                .ignoresSafeArea()
                .onOpenURL { url in
                    _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: url, options: [:])
                }
        }
    }
}
