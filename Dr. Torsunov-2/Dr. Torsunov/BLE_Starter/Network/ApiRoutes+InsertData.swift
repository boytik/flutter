
import Foundation

extension ApiRoutes.Workouts {

    // Локальный билдер URL (через BASE_URL из Info.plist), чтобы не зависеть от приватного url(...)
    private static func buildURL(_ path: String, query: [String: String]? = nil) -> URL {
        // BASE_URL должен быть полным — например: https://revive-server.dev.myrevive.app
        let base = (Bundle.main.object(forInfoDictionaryKey: "BASE_URL") as? String) ?? ""
        guard var comps = URLComponents(string: base) else {
            preconditionFailure("BASE_URL is not a valid URL: \(base)")
        }

        let basePath = comps.path
        if basePath.hasSuffix("/") {
            comps.path = basePath + path
        } else {
            comps.path = basePath + "/" + path
        }

        if let query = query, !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = comps.url else {
            preconditionFailure("Failed to compose URL for path: \(path)")
        }
        return url
    }

    /// POST сырым JSON-массивом на /insert_data
    static var insertData: URL { buildURL("insert_data") }

    /// (Опционально) multipart для фото графика
    static var postPlotPhoto: URL { buildURL("post_plot_photo") }
}
