import Foundation

// MARK: - Public JSON helpers (module-wide)
// These are internal (module-visible) so их можно вызывать из любых файлов таргета.

@inline(__always) public func __findInt(_ value: Any?) -> Int? {
    if let v = value as? Int { return v }
    if let v = value as? NSNumber { return v.intValue }
    if let v = value as? Double { return Int(v) }
    if let v = value as? Float { return Int(v) }
    if let v = value as? Bool { return v ? 1 : 0 }
    if let s = value as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = Int(t) { return i }
        if let d = Double(t.replacingOccurrences(of: ",", with: ".")) { return Int(d) }
    }
    return nil
}

@inline(__always) public func __findInt(_ dict: [String: Any]?, _ key: String) -> Int? {
    guard let dict = dict else { return nil }
    return __findInt(dict[key])
}

@inline(__always) public func __findInt(_ dict: [String: Any]?, keys: [String]) -> Int? {
    guard let dict = dict else { return nil }
    for k in keys {
        if let v = dict[k], let i = __findInt(v) { return i }
    }
    return nil
}

// Double

@inline(__always) public func __findDouble(_ value: Any?) -> Double? {
    if let v = value as? Double { return v }
    if let v = value as? Float { return Double(v) }
    if let v = value as? Int { return Double(v) }
    if let v = value as? NSNumber { return v.doubleValue }
    if let s = value as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(t.replacingOccurrences(of: ",", with: ".")) { return d }
    }
    return nil
}

@inline(__always) public func __findDouble(_ dict: [String: Any]?, _ key: String) -> Double? {
    guard let dict = dict else { return nil }
    return __findDouble(dict[key])
}

@inline(__always) public func __findDouble(_ dict: [String: Any]?, keys: [String]) -> Double? {
    guard let dict = dict else { return nil }
    for k in keys {
        if let v = dict[k], let d = __findDouble(v) { return d }
    }
    return nil
}

// String / enum-like

@inline(__always) public func __unwrapJSONEnum(_ value: Any?) -> String? {
    if let s = value as? String { return s }
    if let i = value as? Int { return String(i) }
    if let b = value as? Bool { return b ? "true" : "false" }
    if let dict = value as? [String: Any] {
        if let s = dict["name"] as? String { return s }
        if let s = dict["key"] as? String { return s }
        if let s = dict["value"] as? String { return s }
        if let s = dict["label"] as? String { return s }
    }
    return nil
}

@inline(__always) public func __unwrapJSONEnum(_ dict: [String: Any]?, _ key: String) -> String? {
    guard let dict = dict else { return nil }
    return __unwrapJSONEnum(dict[key])
}

@inline(__always) public func __unwrapJSONEnum(_ dict: [String: Any]?, keys: [String]) -> String? {
    guard let dict = dict else { return nil }
    for k in keys {
        if let s = __unwrapJSONEnum(dict[k]) { return s }
    }
    return nil
}

// Date

@inline(__always) public func __findDate(_ value: Any?) -> Date? {
    if let d = value as? Date { return d }
    if let s = value as? String {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        // Fallback: unix seconds (or ms) in string
        if let sec = Double(s.replacingOccurrences(of: ",", with: ".")) {
            let seconds = (sec > 10_000_000_000) ? (sec / 1000.0) : sec
            return Date(timeIntervalSince1970: seconds)
        }
    }
    if let n = value as? NSNumber {
        let sec = n.doubleValue
        let seconds = (sec > 10_000_000_000) ? (sec / 1000.0) : sec
        return Date(timeIntervalSince1970: seconds)
    }
    if let sec = value as? Double {
        let seconds = (sec > 10_000_000_000) ? (sec / 1000.0) : sec
        return Date(timeIntervalSince1970: seconds)
    }
    if let i = value as? Int {
        let sec = Double(i)
        let seconds = (sec > 10_000_000_000) ? (sec / 1000.0) : sec
        return Date(timeIntervalSince1970: seconds)
    }
    return nil
}

// Bool

@inline(__always) public func __findBool(_ value: Any?) -> Bool? {
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.boolValue }
    if let s = value as? String {
        let t = s.lowercased()
        if ["true","yes","1"].contains(t) { return true }
        if ["false","no","0"].contains(t) { return false }
    }
    return nil
}

@inline(__always) public func __findBool(_ dict: [String: Any]?, _ key: String) -> Bool? {
    guard let dict = dict else { return nil }
    return __findBool(dict[key])
}

@inline(__always) public func __findBool(_ dict: [String: Any]?, keys: [String]) -> Bool? {
    guard let dict = dict else { return nil }
    for k in keys {
        if let b = __findBool(dict[k]) { return b }
    }
    return nil
}

// Generic: first non-nil for keys
@inline(__always) public func __firstJSONValue(_ dict: [String: Any]?, keys: [String]) -> Any? {
    guard let dict = dict else { return nil }
    for k in keys {
        if let v = dict[k] { return v }
    }
    return nil
}
