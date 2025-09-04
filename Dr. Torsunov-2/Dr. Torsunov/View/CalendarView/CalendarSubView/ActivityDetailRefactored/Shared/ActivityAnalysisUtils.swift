import SwiftUI
import Foundation

func canonicalType(_ raw: String) -> String {
    let s = raw.lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: " ", with: "_")

    if (s.contains("run") || s.contains("running")) &&
       (s.contains("walk") || s.contains("walking")) { return "run_walk" }

    if s.contains("swim")                   { return "swim" }
    if s.contains("water")                  { return "water" }
    if s.contains("bike") || s.contains("cycl") { return "bike" }
    if s.contains("running") || s == "run"  { return "run" }
    if s.contains("walking") || s == "walk" { return "walk" }
    if s.contains("yoga")                   { return "yoga" }
    if s.contains("strength") || s.contains("gym") { return "strength" }
    if s.contains("sauna")                  { return "sauna" }
    if s.contains("fast") || s.contains("fasting") || s.contains("active") { return "fasting" }
    if s.contains("triathlon")              { return "triathlon" }
    return s
}

func inferType(from name: String) -> String {
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

// MARK: - Yoga helpers

func defaultYogaLabels() -> [String] {
    ["Lotus", "Half lotus", "Diamond", "Standing", "Kneeling", "Butterfly", "Other"]
}

func mapStringSeriesToIndices(_ series: [String], preferredLabels: [String]?) -> ([Double],[String]) {
    var labels: [String] = preferredLabels ?? []
    var indexByLabel: [String:Int] = [:]
    func index(for label: String) -> Int {
        if let i = indexByLabel[label] { return i }
        if let i = labels.firstIndex(of: label) {
            indexByLabel[label] = i; return i
        }
        labels.append(label)
        let i = labels.count - 1
        indexByLabel[label] = i
        return i
    }
    let indices = series.map { Double(index(for: $0)) }
    return (indices, labels)
}

func asDoubleArray(_ any: Any) -> [Double]? {
    if let d = any as? [Double] { return d }
    if let i = any as? [Int]    { return i.map(Double.init) }
    let m = Mirror(reflecting: any)
    if m.displayStyle == .optional, let c = m.children.first { return asDoubleArray(c.value) }
    return nil
}

func firstStepLikeSeries(in vm: Any) -> [Double]? {
    let mir = Mirror(reflecting: vm)
    var candidates: [[Double]] = []
    for ch in mir.children {
        guard let arr = asDoubleArray(ch.value), arr.count >= 4 else { continue }
        let rounded = arr.map { round($0) }
        let uniq = Set(rounded)
        let integerish = zip(arr, rounded).allSatisfy { abs($0.0 - $0.1) < 0.001 }
        if integerish && uniq.count >= 2 && uniq.count <= 16 {
            let hasSteps = (1..<rounded.count).contains { rounded[$0] == rounded[$0-1] } || uniq.count < rounded.count
            if hasSteps { candidates.append(rounded) }
        }
    }
    return candidates.max(by: { $0.count < $1.count })
}

func findYogaPositionsSoft(in vm: Any) -> (indices: [Double], labels: [String])? {
    let mir = Mirror(reflecting: vm)

    var numericCandidate: [Double]? = nil
    var stringCandidate: [String]? = nil
    var labelsCandidate: [String]? = nil

    for ch in mir.children {
        guard let name = ch.label?.lowercased() else { continue }
        let hitsName = ["pose","position","yoga","asana","posture","step","stage","state","label","class","category"]
            .contains { name.contains($0) }

        if hitsName {
            if let arr = asDoubleArray(ch.value), !arr.isEmpty {
                numericCandidate = arr
            } else if let arrS = ch.value as? [String], !arrS.isEmpty {
                if Set(arrS).count == arrS.count && arrS.count <= 24 {
                    labelsCandidate = arrS
                } else {
                    stringCandidate = arrS
                }
            }
        }
    }

    if let s = stringCandidate {
        let (idx, labs) = mapStringSeriesToIndices(s, preferredLabels: labelsCandidate)
        return (!idx.isEmpty) ? (idx, labs) : nil
    }
    if numericCandidate == nil {
        numericCandidate = firstStepLikeSeries(in: vm)
    }
    if let idx = numericCandidate, !idx.isEmpty {
        return (idx.map { round($0) }, labelsCandidate ?? defaultYogaLabels())
    }
    return nil
}

extension Array {
    subscript(safe i: Index) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
