import SwiftUI

enum CalendarColors {
    static func color(for w: Workout) -> Color {
        if let t = w.activityType, !t.isEmpty {
            return color(forTypeKey: t)
        }
        return color(forName: w.name)
    }

    static func color(forName name: String) -> Color {
        let s = name.lowercased()
        if s.contains("yoga") || s.contains("йога") { return .purple }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return .orange }
        if s.contains("water") || s.contains("вода") || s.contains("swim") || s.contains("плав") { return .blue }
        if s.contains("sauna") || s.contains("баня") || s.contains("хаммам") { return .red }
        if s.contains("fast")  || s.contains("пост")  || s.contains("голод") { return .yellow }
        return .green
    }

    static func color(forTypeKey keyRaw: String) -> Color {
        let key = keyRaw.lowercased()
        if key.contains("yoga") { return .purple }
        if key.contains("run")  || key.contains("walk") { return .orange }
        if key.contains("swim") || key.contains("water") { return .blue }
        if key.contains("bike") || key.contains("cycl") || key.contains("вел") { return .yellow }
        if key.contains("sauna") || key.contains("баня") { return .red }
        return .green
    }

    static func prettyType(_ raw: String) -> String {
        let s = raw.lowercased()
        if s.contains("yoga") || s.contains("йога") { return "Йога" }
        if s.contains("walk") || s.contains("run") || s.contains("ход") || s.contains("бег") { return "Бег/Ходьба" }
        if s.contains("water") || s.contains("вода") || s.contains("swim") || s.contains("плав") { return "Вода" }
        if s.contains("sauna") || s.contains("баня") || s.contains("хаммам") { return "Баня" }
        if s.contains("fast")  || s.contains("пост")  || s.contains("голод") { return "Пост" }
        return raw.capitalized
    }
}
