// Network/HTTPClient+RawJSON.swift
import Foundation

extension HTTPClient {

    @discardableResult
    func postRawJSON(_ url: URL, rawJSONString: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // Авторизация (если есть токен-провайдер)
        if let token = tokenProvider?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Сырое тело, без JSONEncoder — строго как пришло с BLE
        req.httpBody = Data(rawJSONString.utf8)

        let (data, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw NetworkError.noData
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                // Если нужен автоперезапрос — добавим позже под твой протокол рефреша.
                throw NetworkError.unauthorized
            }
            throw NetworkError.server(status: http.statusCode, data: data)
        }
    }
}

