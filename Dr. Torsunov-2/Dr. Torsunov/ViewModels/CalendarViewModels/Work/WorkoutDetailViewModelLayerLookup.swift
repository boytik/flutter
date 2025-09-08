//
//  WorkoutDetailViewModelLayerLookup.swift
//  Поиск слоя/подслоя на курсоре X (секунды от старта).
//

import Foundation

extension WorkoutDetailViewModel {
    /// Возвращает индекс ближайшей точки по оси времени X (в секундах от старта).
    public func nearestIndexForX(_ x: Double) -> Int? {
        guard let xs = self.timeSeries, !xs.isEmpty else { return nil }
        // Приводим xs к секундам (если в минутах/мс)
        let toSec: (Double) -> Double = { v in
            if v > 12 * 3600 { return v / 1000.0 } // мс
            if v > 360.0     { return v }          // сек
            return v * 60.0                         // мин
        }
        let arr = xs.map(toSec)
        var lo = 0, hi = arr.count - 1
        if x <= arr[lo] { return lo }
        if x >= arr[hi] { return hi }
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if arr[mid] == x { return mid }
            if arr[mid] < x { lo = mid } else { hi = mid }
        }
        return (abs(arr[lo] - x) <= abs(arr[hi] - x)) ? lo : hi
    }

    /// Слой в точке курсора (усечение как во Flutter).
    public func layerAtX(_ x: Double) -> Int? {
        guard let i = nearestIndexForX(x) else { return nil }
        if let arr = self.layerSeriesInt, i < arr.count { return arr[i] }
        return nil
    }

    /// Подслой (done/total) в точке курсора; total берём как максимум по серии.
    public func subLayerAtX(_ x: Double) -> (done: Int, total: Int)? {
        guard let i = nearestIndexForX(x) else { return nil }
        if let arr = self.subLayerSeriesInt, i < arr.count {
            let total = arr.max() ?? 0
            return (arr[i], total)
        }
        return nil
    }
}
