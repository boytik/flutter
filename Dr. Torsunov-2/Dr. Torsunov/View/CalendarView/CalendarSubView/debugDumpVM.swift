// VMIntrospectionDebug.swift
// Один раз положи в проект, чтобы увидеть реальные ключи и примеры значений.

import Foundation

func debugDumpVM(_ vm: Any) {
    print("===== DEBUG VM DUMP START =====")
    dumpPublishedJSONDict(vm, labelContains: "_metadata", title: "METADATA")
    dumpPublishedJSONDict(vm, labelContains: "_metrics",  title: "METRICS")
    print("===== DEBUG VM DUMP END =====")
}

private func dumpPublishedJSONDict(_ vm: Any, labelContains: String, title: String) {
    guard let any = readPublishedAny(vm, labelContains: labelContains) else {
        print("[\(title)] not found")
        return
    }
    print("[\(title)] keys preview:")
    var printed = 0
    visitJSON(any) { path, value in
        if printed < 40 { // чтобы не залить консоль
            print("  • \(path) = \(type(of: value))  ->  \(String(describing: value))")
            printed += 1
        }
    }
}

private func readPublishedAny(_ vm: Any, labelContains: String) -> Any? {
    let mirror = Mirror(reflecting: vm)
    guard let pub = mirror.children.first(where: { ($0.label ?? "").contains(labelContains) })?.value else { return nil }
    let m1 = Mirror(reflecting: pub)
    if let storage = m1.children.first(where: { $0.label == "storage" })?.value {
        let m2 = Mirror(reflecting: storage)
        return m2.children.first(where: { $0.label == "value" })?.value
    }
    return nil
}

private func visitJSON(_ any: Any, path: String = "", depth: Int = 0, visit: (String, Any) -> Void) {
    if depth > 6 { return }
    let m = Mirror(reflecting: any)
    switch m.displayStyle {
    case .dictionary:
        for child in m.children {
            let pair = Mirror(reflecting: child.value).children.map { $0.value }
            if pair.count == 2 {
                let keyStr = pair[0] as? String ?? "<non-string-key>"
                visitJSON(pair[1], path: path.isEmpty ? keyStr : "\(path).\(keyStr)", depth: depth + 1, visit: visit)
            }
        }
    case .collection:
        var idx = 0
        for child in m.children {
            visitJSON(child.value, path: "\(path)[\(idx)]", depth: depth + 1, visit: visit)
            idx += 1
        }
    case .enum:
        // вероятно JSONValue — распакуем
        if let assoc = Mirror(reflecting: any).children.first?.value {
            visitJSON(assoc, path: path, depth: depth + 1, visit: visit)
        } else {
            visit(path, any)
        }
    case .struct, .class, .tuple:
        // попробуем пройтись по полям
        var hadChildren = false
        for child in m.children {
            let label = child.label ?? "<field>"
            hadChildren = true
            visitJSON(child.value, path: path.isEmpty ? label : "\(path).\(label)", depth: depth + 1, visit: visit)
        }
        if !hadChildren { visit(path, any) }
    default:
        visit(path, any)
    }
}
