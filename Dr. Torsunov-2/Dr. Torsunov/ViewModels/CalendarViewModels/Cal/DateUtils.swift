import Foundation

public enum DateUtils {
    public static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd"; return f
    }()
    public static let ymdhmsT: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"; return f
    }()
    public static let ymdhmsSp: DateFormatter = {
        let f = DateFormatter(); f.locale = .init(identifier: "en_US_POSIX")
        f.timeZone = .current; f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    @inlinable
    public static func parse(_ s: String?) -> Date? {
        guard let s = s, !s.isEmpty else { return nil }
        if let d = ymdhmsT.date(from: s) { return d }
        if let d = ymdhmsSp.date(from: s) { return d }
        if let d = ymd.date(from: s) { return d }
        return nil
    }
}
