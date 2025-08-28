import SwiftUI

struct DayItemsSheet: View {
    let date: Date
    let items: [CalendarItem]
    let role: PersonalViewModel.Role
    let thumbProvider: (CalendarItem) -> URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Capsule().fill(Color.white.opacity(0.25))
                    .frame(width: 44, height: 5)
                    .padding(.top, 8)

                HStack {
                    Text(dateFormatted(date))
                        .font(.headline).foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items, id: \.id) { item in
                            NavigationLink {
                                destination(for: item).background(Color.black.ignoresSafeArea())
                            } label: {
                                row(for: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
        .tint(.green)
    }

    // MARK: - Destination

    @ViewBuilder
    private func destination(for item: CalendarItem) -> some View {
        if item.asWorkout != nil {
            WorkoutDetailView(item: item, role: role)
        } else if let activity = item.asActivity {
            ActivityDetailView(activity: activity, role: role)
        } else {
            Text("Unknown").foregroundColor(.white)
        }
    }

    // MARK: - Row

    private func row(for item: CalendarItem) -> some View {
        // быстрая диагностика
        // print("DBG name=\(item.name) type=\(item.asWorkout?.activityType ?? "nil")")

        HStack(spacing: 12) {
            iconView(for: item)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleEN(for: item))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let sub = subtitleEN(for: item), !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.date, style: .date)
                    .font(.caption).foregroundColor(.white.opacity(0.7))
                Text(item.date, style: .time)
                    .font(.caption2).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Titles (EN, как во Flutter)

    private func titleEN(for item: CalendarItem) -> String {
        if let raw = item.asWorkout?.activityType?.lowercased(),
           let en = enName(for: canonicalType(raw)) {
            return en
        }
        // если тип не пришёл — оставляем имя, иначе пробуем угадать по имени
        let fallback = enName(for: canonicalType(inferType(from: item.name)))
        return fallback ?? item.name
    }

    private func subtitleEN(for item: CalendarItem) -> String? {
        if let w = item.asWorkout {
            if let d = w.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                return d
            }
            if let raw = w.activityType?.lowercased(),
               let en = enName(for: canonicalType(raw)) {
                return en
            }
        } else if let a = item.asActivity, let n = a.name, !n.isEmpty {
            return n
        }
        return nil
    }

    private func enName(for type: String) -> String? {
        // канонические ключи
        let map: [String: String] = [
            "swim":"Swim",
            "water":"Water",
            "bike":"Cycling",
            "run":"Run",
            "walk":"Walk",
            "run_walk":"Run/Walk",
            "yoga":"Yoga",
            "strength":"Strength",
            "sauna":"Sauna",
            "fasting":"Fasting",
            "triathlon":"Triathlon"
        ]
        return map[type]
    }

    // MARK: - Icons (assets → SF Symbols → default)

    @ViewBuilder
    private func iconView(for item: CalendarItem) -> some View {
        if let url = thumbProvider(item) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                ZStack { placeholderCircle(); ProgressView().tint(.white) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            // тип: activityType → canonical, иначе infer → canonical
            let baseType = item.asWorkout?.activityType?.lowercased()
                ?? inferType(from: item.name)
            let t = canonicalType(baseType)

            if let asset = iconAssetName(for: t), UIImage(named: asset) != nil {
                circleIcon(image: Image(asset), bg: colorByType(t))
            } else {
                let symbol = glyphSymbolByType(t)
                circleIcon(system: symbol, bg: colorByType(t))
            }
        }
    }

    private func iconAssetName(for type: String) -> String? {
        switch type {
        case "yoga":       return "ic_workout_yoga"
        case "run":        return "ic_workout_run"
        case "walk":       return "ic_workout_walk"
        case "run_walk":   return "ic_workout_run"   // объединяем как во Flutter
        case "bike":       return "ic_workout_bike"
        case "swim":       return "ic_workout_swim"
        case "water":      return "ic_workout_water"
        case "strength":   return "ic_workout_strength"
        case "sauna":      return "ic_workout_sauna"
        case "fasting":    return "ic_workout_fast"
        default:           return nil
        }
    }

    // MARK: - Normalization & inference

    /// Приводим тип к каноническому ключу, чтобы ловить варианты:
    /// "walking/running", "walk_run", "RUN-WALK", "runningWalking", и т.п.
    private func canonicalType(_ raw: String) -> String {
        let s = raw
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        // run+walk комбо
        if (s.contains("run") || s.contains("running")) &&
           (s.contains("walk") || s.contains("walking")) { return "run_walk" }

        if s.contains("swim")       { return "swim" }
        if s.contains("water")      { return "water" }
        if s.contains("bike") || s.contains("cycl") { return "bike" }
        if s.contains("running") || s == "run"      { return "run" }
        if s.contains("walking") || s == "walk"     { return "walk" }
        if s.contains("yoga")       { return "yoga" }
        if s.contains("strength") || s.contains("gym") { return "strength" }
        if s.contains("sauna")      { return "sauna" }
        if s.contains("fast") || s.contains("fasting") || s.contains("active") { return "fasting" }
        if s.contains("triathlon")  { return "triathlon" }
        return s
    }

    /// Если типа нет — пытаемся угадать его из имени (EN/RU).
    private func inferType(from name: String) -> String {
        let s = name.lowercased()
        if (s.contains("run") || s.contains("бег")) &&
           (s.contains("walk") || s.contains("ходь")) { return "run_walk" }
        if s.contains("yoga") || s.contains("йога") { return "yoga" }
        if s.contains("run") || s.contains("бег") { return "run" }
        if s.contains("walk") || s.contains("ходь") { return "walk" }
        if s.contains("bike") || s.contains("velo") || s.contains("вел") || s.contains("cycl") { return "bike" }
        if s.contains("swim") || s.contains("плав") { return "swim" }
        if s.contains("water") || s.contains("вода") { return "water" }
        if s.contains("sauna") || s.contains("сауна") { return "sauna" }
        if s.contains("fast") || s.contains("пост") || s.contains("active") { return "fasting" }
        if s.contains("strength") || s.contains("силов") || s.contains("gym") { return "strength" }
        if s.contains("triathlon") { return "triathlon" }
        return ""
    }

    // MARK: - Symbols & Colors

    private func glyphSymbolByType(_ type: String) -> String {
        switch type {
        case "yoga": return "figure.mind.and.body"
        case "run":  return "figure.run"
        case "walk": return "figure.walk"
        case "run_walk": return "figure.run" // единая иконка, как в Flutter
        case "bike": return "bicycle"
        case "swim", "water": return "drop.fill"
        case "strength":
            if #available(iOS 16.0, *) { return "dumbbell.fill" } else { return "bolt.heart" }
        case "sauna": return "flame.fill"
        case "fasting": return "fork.knife"
        default: return "dumbbell.fill"
        }
    }

    private func colorByType(_ type: String) -> Color {
        switch type {
        case "yoga": return .purple
        case "run": return .pink
        case "walk": return .orange
        case "run_walk": return .pink
        case "bike": return .mint
        case "swim", "water": return .blue
        case "strength": return .green
        case "sauna": return .red
        case "fasting": return .yellow
        default: return .gray
        }
    }

    // MARK: - Small views

    private func circleIcon(system: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(bg)
        }
    }

    private func circleIcon(image: Image, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            image.resizable().scaledToFit().padding(10)
        }
    }

    private func placeholderCircle() -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08))
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func dateFormatted(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM yyyy"
        return df.string(from: d)
    }
}
