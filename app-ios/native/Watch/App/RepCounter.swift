import CoreMotion
import Foundation

// Conta le ripetizioni dai movimenti del polso (accelerometro dell'orologio, senza Salute). È una prova:
// funziona dove il polso si muove (spinte, tirate, curl, alzate); su leg press, leg extension o crunch il braccio sta fermo
// e il conteggio resta a zero. Il numero è solo una proposta: si corregge con la corona.
final class RepCounter: ObservableObject {
    @Published private(set) var reps = 0
    private let motion = CMMotionManager()
    private var t: [TimeInterval] = []
    private var axes: [[Double]] = [[], [], []]
    private var lastCount: TimeInterval = 0

    func start() {
        stop()
        t = []
        axes = [[], [], []]
        reps = 0
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            let a = m.userAcceleration // senza la gravità
            self.t.append(m.timestamp)
            self.axes[0].append(a.x)
            self.axes[1].append(a.y)
            self.axes[2].append(a.z)
            let keep = 50 * 150 // al massimo gli ultimi due minuti e mezzo
            if self.t.count > keep {
                let cut = self.t.count - keep
                self.t.removeFirst(cut)
                for i in 0..<3 { self.axes[i].removeFirst(cut) }
            }
            if m.timestamp - self.lastCount > 0.5 { // ricalcolo due volte al secondo
                self.lastCount = m.timestamp
                let n = self.count()
                if n != self.reps { self.reps = n }
            }
        }
    }

    func stop() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }

    // l'asse con più movimento, smussato (0,2 s); una ripetizione = un picco alto, separato dal precedente
    // da almeno 0,8 s e da un ritorno sotto la media
    private func count() -> Int {
        let n = t.count
        guard n > 100 else { return 0 }
        func mean(_ v: [Double]) -> Double { v.reduce(0, +) / Double(v.count) }
        func variance(_ v: [Double]) -> Double { let m = mean(v); return v.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(v.count) }
        guard let signal = axes.max(by: { variance($0) < variance($1) }) else { return 0 }
        var smooth = [Double](repeating: 0, count: n)
        var acc = 0.0
        for i in 0..<n {
            acc += signal[i]
            if i >= 10 { acc -= signal[i - 10] }
            smooth[i] = acc / Double(min(i + 1, 10))
        }
        let m = mean(smooth)
        let sd = variance(smooth).squareRoot()
        guard sd > 0.03 else { return 0 } // polso quasi fermo
        let high = m + 0.6 * sd
        var count = 0
        var lastPeak = -1e9
        var armed = true
        for i in 1..<(n - 1) {
            if smooth[i] < m { armed = true }
            if armed, smooth[i] > high, smooth[i] >= smooth[i - 1], smooth[i] >= smooth[i + 1], t[i] - lastPeak > 0.8 {
                count += 1
                lastPeak = t[i]
                armed = false
            }
        }
        return count
    }
}
