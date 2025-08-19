import Foundation

extension URL {
    /// Возвращает URL, где параметр `oldName` заменён на `newName=value`.
    func replacingQueryParam(_ oldName: String, with newName: String, value: String) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == oldName }
        items.removeAll { $0.name == newName }
        items.append(URLQueryItem(name: newName, value: value))
        comps.queryItems = items
        return comps.url ?? self
    }
}
