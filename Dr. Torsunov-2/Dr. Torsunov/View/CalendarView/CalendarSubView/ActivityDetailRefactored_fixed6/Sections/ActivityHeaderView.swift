import SwiftUI

@MainActor

struct ActivityHeaderView: View {
    let activity: Activity
    init(activity: Activity) { self.activity = activity }

    var body: some View {
        HStack(spacing: 12) {
            headerIcon(for: activity).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(titleEN(for: activity)).font(.headline).foregroundColor(.white)
                if let date = activity.createdAt {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
        }
    }

    private func titleEN(for activity: Activity) -> String {
        let base = ((activity.name ?? "") + " " + (activity.description ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let t = canonicalType(inferType(from: base))
        return enName(for: t) ?? (activity.name ?? "Activity")
    }

    private func enName(for type: String) -> String? {
        [
            "swim":"Swim","water":"Water","bike":"Cycling",
            "run":"Run","walk":"Walk","run_walk":"Run/Walk",
            "yoga":"Yoga","strength":"Strength","sauna":"Sauna",
            "fasting":"Fasting","triathlon":"Triathlon"
        ][type]
    }

    @ViewBuilder
    private func headerIcon(for activity: Activity) -> some View {
        let base = ((activity.name ?? "") + " " + (activity.description ?? "")).trimmingCharacters(in: .whitespacesAndNewlines)
        let t = canonicalType(inferType(from: base))

        if let asset = iconAssetName(for: t), UIImage(named: asset) != nil {
            circleIcon(image: Image(asset), bg: colorByType(t))
        } else {
            circleIcon(system: glyphSymbolByType(t), bg: colorByType(t))
        }
    }

    private func iconAssetName(for type: String) -> String? {
        switch type {
        case "yoga": return "ic_workout_yoga"
        case "run": return "ic_workout_run"
        case "walk": return "ic_workout_walk"
        case "run_walk": return "ic_workout_run"
        case "bike": return "ic_workout_bike"
        case "swim": return "ic_workout_swim"
        case "water": return "ic_workout_water"
        case "strength": return "ic_workout_strength"
        case "sauna": return "ic_workout_sauna"
        case "fasting": return "ic_workout_fast"
        default: return nil
        }
    }

    private func glyphSymbolByType(_ type: String) -> String {
        switch type {
        case "yoga": return "figure.mind.and.body"
        case "run": return "figure.run"
        case "walk": return "figure.walk"
        case "run_walk": return "figure.run"
        case "bike": return "bicycle"
        case "swim", "water": return "drop.fill"
        case "strength":
            if #available(iOS 16.0, *) { return "dumbbell.fill" } else { return "bolt.heart" }
        case "sauna": return "flame.fill"
        case "fasting": return "fork.knife"
        default: return "checkmark.seal.fill"
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

    private func circleIcon(system: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            Image(systemName: system).font(.system(size: 18, weight: .semibold)).foregroundColor(bg)
        }
    }
    private func circleIcon(image: Image, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg.opacity(0.18))
            Circle().stroke(bg.opacity(0.35), lineWidth: 1)
            image.resizable().scaledToFit().padding(8)
        }
    }
}
