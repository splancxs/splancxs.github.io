import Capacitor
import UIKit

// Controller principale dell'app: è quello di Capacitor, in più registra i plugin scritti apposta per Recomp.
// patch-ios.mjs lo imposta in Main.storyboard al posto di CAPBridgeViewController.
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(RestActivityPlugin())
    }
}
