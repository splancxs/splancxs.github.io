import Capacitor
import UIKit

// Barra in basso nativa di iOS al posto di quella della pagina: su iOS 26 ha il Liquid Glass di sistema,
// che rifrange la pagina che ci scorre sotto. Il tocco su una voce arriva al JavaScript come evento "select".
// JS: NativeTabs.show({ items: [{ title, icon }], selected, dark }) la mette (icon = nome di un simbolo SF),
//     select({ index }) cambia la voce attiva, setHidden({ hidden }) la nasconde mentre è aperto un pannello,
//     style({ dark }) segue il tema dell'app, remove() la toglie e torna la barra della pagina.
// Come RestActivityPlugin, Capacitor lo crea perché il workflow aggiunge "NativeTabsPlugin" a packageClassList.
@objc(NativeTabsPlugin)
public class NativeTabsPlugin: CAPPlugin, CAPBridgedPlugin, UITabBarDelegate {
    public let identifier = "NativeTabsPlugin"
    public let jsName = "NativeTabs"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "show", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "select", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setHidden", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "style", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "remove", returnType: CAPPluginReturnPromise),
    ]
    private var bar: UITabBar?

    // voce attiva lime sul tema scuro, verde oliva sul chiaro (il lime su fondo chiaro non si legge)
    private func paint(_ bar: UITabBar, dark: Bool) {
        bar.overrideUserInterfaceStyle = dark ? .dark : .light
        bar.tintColor = dark
            ? UIColor(red: 0.769, green: 0.941, blue: 0.192, alpha: 1)
            : UIColor(red: 0.302, green: 0.420, blue: 0.0, alpha: 1)
    }

    @objc func show(_ call: CAPPluginCall) {
        let items = call.getArray("items", JSObject.self) ?? []
        let selected = call.getInt("selected") ?? 0
        let dark = call.getBool("dark") ?? true
        DispatchQueue.main.async {
            guard let host = self.bridge?.viewController?.view else {
                call.reject("La vista dell'app non è pronta")
                return
            }
            let bar = self.bar ?? UITabBar()
            bar.delegate = self
            bar.items = items.enumerated().map { index, item in
                UITabBarItem(title: item["title"] as? String,
                             image: UIImage(systemName: item["icon"] as? String ?? "circle"),
                             tag: index)
            }
            if let all = bar.items, selected >= 0, selected < all.count { bar.selectedItem = all[selected] }
            self.paint(bar, dark: dark)
            if bar.superview == nil {
                // sopra la pagina, attaccata al fondo dello schermo: l'altezza della zona del tasto Home la aggiunge iOS
                bar.translatesAutoresizingMaskIntoConstraints = false
                host.addSubview(bar)
                NSLayoutConstraint.activate([
                    bar.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                    bar.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                    bar.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                ])
            }
            self.bar = bar
            bar.isHidden = false
            bar.alpha = 1
            bar.isUserInteractionEnabled = true
            host.layoutIfNeeded()
            call.resolve(["height": bar.frame.height])
        }
    }

    @objc func select(_ call: CAPPluginCall) {
        let index = call.getInt("index") ?? -1
        DispatchQueue.main.async {
            if let bar = self.bar, let all = bar.items, index >= 0, index < all.count, bar.selectedItem !== all[index] {
                bar.selectedItem = all[index]
            }
            call.resolve()
        }
    }

    @objc func setHidden(_ call: CAPPluginCall) {
        let hidden = call.getBool("hidden") ?? false
        DispatchQueue.main.async {
            guard let bar = self.bar else {
                call.resolve()
                return
            }
            bar.isUserInteractionEnabled = !hidden
            if !hidden { bar.isHidden = false }
            UIView.animate(withDuration: 0.2, animations: { bar.alpha = hidden ? 0 : 1 }, completion: { _ in
                if bar.alpha == 0 { bar.isHidden = true }
            })
            call.resolve()
        }
    }

    @objc func style(_ call: CAPPluginCall) {
        let dark = call.getBool("dark") ?? true
        DispatchQueue.main.async {
            if let bar = self.bar { self.paint(bar, dark: dark) }
            call.resolve()
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.bar?.removeFromSuperview()
            self.bar = nil
            call.resolve()
        }
    }

    // arriva anche quando si tocca la voce già attiva: la pagina allora torna in cima
    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        notifyListeners("select", data: ["index": item.tag])
    }
}
