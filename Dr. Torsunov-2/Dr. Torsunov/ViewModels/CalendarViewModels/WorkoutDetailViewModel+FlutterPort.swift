// WorkoutDetailViewModel+FlutterPort.swift
//
// Port of Flutter layer logic: unique (layer, subLayer) transitions and per-index lookup.
// Use from your UI without making these APIs public.

import Foundation

struct FlutterLayerTransition: Hashable {
    let layer: Int
    let subLayer: Int
    let timeSeconds: Double       // seconds from workout start
    let isFirstLayer: Bool        // true only for the first time a given layer appears
}

extension WorkoutDetailViewModel {

    // Keys (same vocabulary we already use elsewhere)
    private var __tKeys: [String] {
        ["workoutDuration","workout_duration","durationFromStart","duration_from_start",
         "sec_from_start","seconds_from_start","time_numeric","timeNumeric","time","t","seconds","secs","minutes","mins"]
    }
    private var __layerKeys: [String] {
        ["currentLayerChecked","currentLayer","layer_checked","layer","layerIndex","layer_now","stage","phase"]
    }
    private var __subLayerKeys: [String] {
        ["currentsubLayerChecked","currentSubLayerChecked","subLayer","sub_layer","sublayer","subLayerIndex","sublayer_now","subStage","subPhase"]
    }

    // Normalize any numeric time value to SECONDS (ms/sec/min → sec), with a hint from the key name.
    private func __normalizeToSeconds(_ raw: Double, hintKey: String?) -> Double {
        if let h = hintKey?.lowercased() {
            if h.contains("min") { return raw * 60.0 }        // minutes → seconds
            if h.contains("sec") { return raw }               // already seconds
            if h == "t" || h == "time" {
                if raw > 12 * 3600 { return raw / 1000.0 }    // looks like milliseconds
                if raw > 360.0 { return raw }                 // seconds
                return raw * 60.0                              // minutes
            }
            if h.contains("duration") || h.contains("from_start") {
                return raw // workoutDuration is already seconds
            }
        }
        // Fallback by magnitude
        if raw > 12 * 3600 { return raw / 1000.0 } // ms
        if raw > 360.0     { return raw }          // sec
        return raw * 60.0                          // min
    }

    /// Flutter-like unique (layer, subLayer) transitions.
    /// - isFullScreen: false → only first entries of each *layer* (normal mode).
    ///                 true  → all unique (layer, subLayer) entries (fullscreen).
    @MainActor
    func flutterLayerTransitions(isFullScreen: Bool) -> [FlutterLayerTransition] {
        guard let rows = self.metricObjectsArray, !rows.isEmpty else { return [] }

        struct Row { let t: Double; let layer: Int; let sub: Int }
        var out: [Row] = []
        out.reserveCapacity(rows.count)

        for row in rows {
            // time seconds
            var tSeconds: Double? = nil
            var hitKey: String? = nil
            for k in __tKeys {
                if let tv = self.value(for: [k], in: row), let t = self.number(in: tv) {
                    tSeconds = __normalizeToSeconds(t, hintKey: k)
                    hitKey = k
                    break
                }
            }
            guard let tSec = tSeconds else { continue }

            // layer / sublayer (truncate toward zero, like Dart .toInt())
            func truncInt(_ v: Double) -> Int { v >= 0 ? Int(floor(v)) : Int(ceil(v)) }

            guard let lv = self.value(for: __layerKeys, in: row), let l = self.number(in: lv) else { continue }
            guard let sv = self.value(for: __subLayerKeys, in: row), let s = self.number(in: sv) else { continue }
            let L = truncInt(l), S = truncInt(s)

            out.append(.init(t: tSec, layer: L, sub: S))
        }

        guard !out.isEmpty else { return [] }
        out.sort { $0.t < $1.t }

        // First occurrence per (layer, sub) pair — earliest time
        struct Pair: Hashable { let l: Int; let s: Int }
        var seenPairs = Set<Pair>()
        var firstTimeForLayer = [Int: Double]() // to compute isFirstLayer

        var transitions: [FlutterLayerTransition] = []
        transitions.reserveCapacity(out.count)

        for r in out {
            let p = Pair(l: r.layer, s: r.sub)
            if !seenPairs.contains(p) {
                seenPairs.insert(p)
                if firstTimeForLayer[r.layer] == nil { firstTimeForLayer[r.layer] = r.t }
                let isFirst = (firstTimeForLayer[r.layer] == r.t)
                transitions.append(FlutterLayerTransition(layer: r.layer, subLayer: r.sub, timeSeconds: r.t, isFirstLayer: isFirst))
            }
        }

        // normal → only first layer entries; fullscreen → all unique pairs
        let filtered: [FlutterLayerTransition] = isFullScreen ? transitions : transitions.filter { $0.isFirstLayer }

        if let total = self.totalDurationSeconds, total > 0 {
            return filtered.filter { $0.timeSeconds <= total + 1 }
        }
        return filtered
    }

    // MARK: - Per-index lookup like Flutter (cursor → header)

    /// Returns the data index for a normalized X position in [0, 1].
    /// Make x01 = (x - leftPadding) / chartWidth, clipped to [0, 1] before passing here.
    @MainActor
    func indexForNormalizedX(_ x01: Double) -> Int? {
        guard let rows = self.metricObjectsArray, rows.count >= 1 else { return nil }
        let n = rows.count
        let clamped = max(0.0, min(1.0, x01))
        return Int(floor(clamped * Double(n - 1)))
    }

    /// Layer at normalized X (index-based, like Flutter).
    @MainActor
    func layerAtNormalizedX(_ x01: Double) -> Int? {
        guard let idx = indexForNormalizedX(x01),
              let arr = self.layerSeriesInt, idx < arr.count else { return nil }
        return arr[idx]
    }

    /// SubLayer at normalized X (index-based, like Flutter).
    @MainActor
    func subLayerAtNormalizedX(_ x01: Double) -> Int? {
        guard let idx = indexForNormalizedX(x01),
              let arr = self.subLayerSeriesInt, idx < arr.count else { return nil }
        return arr[idx]
    }
}
