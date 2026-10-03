import Foundation
import SwiftUI

// Stato di oggi mandato dall'app iPhone (app.js → WatchBridge). Lo usano l'app Watch e la complicazione sul quadrante,
// che lo leggono dal gruppo condiviso: l'app lo salva a ogni aggiornamento.
struct WatchMeal: Codable, Identifiable, Hashable {
    var si: Int
    var time: String
    var label: String
    var name: String
    var k: Int
    var p: Int
    var eaten: Bool
    var id: Int { si }
}

struct WatchWorkout: Codable, Hashable {
    var name: String
    var ex: String?
    var i: Int?
    var j: Int?
    var set: Int?
    var of: Int?
    var target: String?
    var left: Int?
    var done: Bool?
}

struct WatchSnapshot: Codable, Hashable {
    var date: String
    var day: String
    var type: String
    var kcal: Int
    var kcalTarget: Int
    var p: Int
    var pTarget: Int
    var c: Int
    var cTarget: Int
    var f: Int
    var fTarget: Int
    var meals: [WatchMeal]
    var crea: Bool
    var wo: WatchWorkout?
    var restEnd: Double?   // fine del recupero in millisecondi, come in JavaScript
    var restNext: String?

    var left: Int { max(0, kcalTarget - kcal) }
    var progress: Double { kcalTarget > 0 ? min(1, Double(kcal) / Double(kcalTarget)) : 0 }
    var nextMeal: WatchMeal? { meals.first { !$0.eaten } }
    var isToday: Bool { date == WatchSnapshot.todayKey() }
    var rest: Date? {
        guard let ms = restEnd else { return nil }
        let end = Date(timeIntervalSince1970: ms / 1000)
        return end > Date() ? end : nil
    }

    static func todayKey() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

enum WatchShared {
    static let group = "group.io.github.splancxs.recomp"
    private static let key = "snapshot"
    private static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func load() -> WatchSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchSnapshot.self, from: data)
    }
    static func save(_ snapshot: WatchSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }
}

// colori dell'app: lime per l'accento, rosso, giallo e blu per proteine, carboidrati e grassi
enum Palette {
    static let lime = Color(red: 0.769, green: 0.941, blue: 0.192)
    static let ink = Color(red: 0.106, green: 0.141, blue: 0.0)   // testo scuro sopra il lime
    static let p = Color(red: 0.867, green: 0.310, blue: 0.227)
    static let c = Color(red: 0.847, green: 0.573, blue: 0.122)
    static let f = Color(red: 0.184, green: 0.498, blue: 0.812)
}
