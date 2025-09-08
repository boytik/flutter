//
//  WorkoutDetailViewModel+DerivedSeries.swift
//  Restores `rebuildDerivedSeries()` used by UI (poses/yoga).
//

import Foundation

extension WorkoutDetailViewModel {
    /// Пересобирает производные серии поз (для таблиц/легенд). Совместимо с прежними вызовами UI.
    func rebuildDerivedSeries() {
        guard let rows = self.metricObjectsArray else {
            self.yogaPoseTimeline = []
            self.yogaPoseLabels   = []
            self.yogaPoseIndices  = []
            return
        }
        let poseKeys = [
            "bodyPosition","body_position","position","pose","yogaPose","yoga_pose",
            "asana","posture","state","class","category","label"
        ]
        // Базовые ярлыки по умолчанию (если не пришли из данных)
        var labels: [String] = self.yogaPoseLabels.isEmpty ?
            ["Lotus","Half lotus","Diamond","Standing","Kneeling","Butterfly","Other"] :
            self.yogaPoseLabels

        var timeline: [String] = []
        timeline.reserveCapacity(rows.count)
        var last: String? = nil

        for row in rows {
            var s: String? = nil
            for key in poseKeys {
                if let v = value(for: [key], in: row) {
                    switch v {
                    case .string(let str):
                        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { s = trimmed }
                    case .number(let d):
                        let i = Int(d.rounded())
                        if labels.indices.contains(i) { s = labels[i] } else { s = "\(i)" }
                    default:
                        break
                    }
                    if s != nil { break }
                }
            }
            if s == nil { s = last ?? "Other" }
            if let val = s, !val.isEmpty {
                if !labels.contains(val) { labels.append(val) }
                timeline.append(val)
                last = val
            } else {
                timeline.append(last ?? "Other")
            }
        }

        let indexBy = Dictionary(uniqueKeysWithValues: labels.enumerated().map { ($1, $0) })
        let indices = timeline.map { Double(indexBy[$0] ?? 0) }

        self.yogaPoseTimeline = timeline
        self.yogaPoseLabels   = labels
        self.yogaPoseIndices  = indices
    }
}
