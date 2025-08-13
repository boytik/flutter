import Foundation

/// DTO для /list_workouts_for_check и /list_workouts_for_check_full.
/// Сделано максимально толерантно к «плавающим» типам (строка/число/массив/…).
struct ActivityForCheckDTO: Decodable {
    // Стабильные строки
    let workoutKey: String?
    let workoutActivityType: String?
    let workoutStartDate: String?
    let minStartTime: String?
    let comment: String?
    let photoAfter: String?
    let photoBefore: String?
    let activityGraph: String?
    let heartRateGraph: String?
    let map: String?

    // Плавающие значения
    let avg_humidity: JSONValue?
    let avg_temp:     JSONValue?
    let distance:     JSONValue?
    let duration:     JSONValue?
    let list_positions: JSONValue?
    let maxLayer:     JSONValue?
    let maxSubLayer:  JSONValue?

    enum CodingKeys: String, CodingKey {
        case activityGraph, avg_humidity, avg_temp, comment
        case distance, duration, heartRateGraph, list_positions, map
        case maxLayer, maxSubLayer, photoAfter, photoBefore
        case workoutActivityType, workoutKey, workoutStartDate, minStartTime
        // сервер иногда присылает эти ключи — просто игнорируем
        case currentLayerChecked, currentsubLayerChecked
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        workoutKey           = try c.decodeIfPresent(String.self, forKey: .workoutKey)
        workoutActivityType  = try c.decodeIfPresent(String.self, forKey: .workoutActivityType)
        workoutStartDate     = try c.decodeIfPresent(String.self, forKey: .workoutStartDate)
        minStartTime         = try c.decodeIfPresent(String.self, forKey: .minStartTime)
        comment              = try c.decodeIfPresent(String.self, forKey: .comment)
        photoAfter           = try c.decodeIfPresent(String.self, forKey: .photoAfter)
        photoBefore          = try c.decodeIfPresent(String.self, forKey: .photoBefore)
        activityGraph        = try c.decodeIfPresent(String.self, forKey: .activityGraph)
        heartRateGraph       = try c.decodeIfPresent(String.self, forKey: .heartRateGraph)
        map                  = try c.decodeIfPresent(String.self, forKey: .map)

        avg_humidity         = try c.decodeIfPresent(JSONValue.self, forKey: .avg_humidity)
        avg_temp             = try c.decodeIfPresent(JSONValue.self, forKey: .avg_temp)
        distance             = try c.decodeIfPresent(JSONValue.self, forKey: .distance)
        duration             = try c.decodeIfPresent(JSONValue.self, forKey: .duration)
        list_positions       = try c.decodeIfPresent(JSONValue.self, forKey: .list_positions)
        maxLayer             = try c.decodeIfPresent(JSONValue.self, forKey: .maxLayer)
        maxSubLayer          = try c.decodeIfPresent(JSONValue.self, forKey: .maxSubLayer)

        // лишние ключи, если будут — просто читаем и не сохраняем
        _ = try? c.decodeIfPresent(String.self, forKey: .currentLayerChecked)
        _ = try? c.decodeIfPresent(String.self, forKey: .currentsubLayerChecked)
    }

    /// Унифицированная дата начала (первое непустое из workoutStartDate / minStartTime)
    var startedAt: Date? {
        for raw in [workoutStartDate, minStartTime] {
            if let s = raw, let d = Self.parseDate(s) { return d }
        }
        return nil
    }

    private static func parseDate(_ s: String) -> Date? {
        let fmts = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }
}


