
import Foundation

//enum HTTPMethod: String { case GET, POST, PUT, DELETE }

enum NetworkError: Error, LocalizedError {
    case badURL
    case noData
    case decoding(Error)
    case encoding(Error)
    case server(status: Int, data: Data?)
    case unauthorized
    case other(Error)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Bad URL"
        case .noData: return "No data received"
        case .decoding(let e): return "Decoding error: \(e.localizedDescription)"
        case .encoding(let e): return "Encoding error: \(e.localizedDescription)"
        case .server(let code, _): return "Server error (\(code))"
        case .unauthorized: return "Unauthorized"
        case .other(let e): return e.localizedDescription
        }
    }
}


// Кто умеет обновлять токен (вызывается на 401)
protocol AuthRefresher {
    func refreshToken() async throws
}

// Откуда брать accessToken для Authorization: Bearer
protocol TokenProvider {
    var accessToken: String? { get }
}

final class HTTPClient {
    static let shared = HTTPClient()
    private init() {}

    enum Method: String { case GET, POST, PUT, PATCH, DELETE }

    // Инъекции
    var tokenProvider: TokenProvider?
    var authRefresher: AuthRefresher?
    var urlSession: URLSession = .shared

    // MARK: - Основной запрос (вариант 1: сначала URL)
    @discardableResult
    func request<T: Decodable>(
        _ url: URL,
        method: Method = .GET,
        headers: [String: String] = [:],
        body: (any Encodable)? = nil,
        decode: T.Type = T.self
    ) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue

        var allHeaders: [String: String] = ["Accept": "application/json"]
        if body != nil { allHeaders["Content-Type"] = "application/json" }
        headers.forEach { allHeaders[$0.key] = $0.value }
        if let token = tokenProvider?.accessToken {
            allHeaders["Authorization"] = "Bearer \(token)"
        }
        req.allHTTPHeaderFields = allHeaders

        if let body = body {
            do { req.httpBody = try JSONEncoder.api.encode(AnyEncodable(body)) }
            catch { throw NetworkError.encoding(error) }
        }

        do {
            let (data, resp) = try await urlSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw NetworkError.noData }

            switch http.statusCode {
            case 200...299:
                if T.self == Empty.self { return Empty() as! T }
                guard !data.isEmpty else { throw NetworkError.noData }
                do { return try JSONDecoder.api.decode(T.self, from: data) }
                catch { throw NetworkError.decoding(error) }

            case 401:
                // одна попытка рефреша и повтор
                if let refresher = authRefresher {
                    try await refresher.refreshToken()
                    return try await request(url, method: method, headers: headers, body: body, decode: decode)
                } else {
                    throw NetworkError.unauthorized
                }

            default:
                throw NetworkError.server(status: http.statusCode, data: data)
            }
        } catch let e as NetworkError {
            throw e
        } catch {
            throw NetworkError.other(error)
        }
    }

    // MARK: - Совместимый оверлоад (вариант 2: сначала тип, потом URL)
    func request<T: Decodable>(
        _ decode: T.Type,
        url: URL,
        method: Method = .GET,
        headers: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws -> T {
        try await request(url, method: method, headers: headers, body: body, decode: decode)
    }

    // MARK: - Запрос без тела ответа (void)
    func requestVoid(
        url: URL,
        method: Method = .POST,
        headers: [String: String] = [:],
        body: (any Encodable)? = nil
    ) async throws {
        let _: Empty = try await request(url, method: method, headers: headers, body: body, decode: Empty.self)
    }

    // MARK: - Multipart upload (например, отправка аудио/файлов)
    struct UploadPart {
        let name: String
        let filename: String
        let mime: String
        let data: Data
    }

    @discardableResult
    func uploadMultipart(
        url: URL,
        fields: [String: String],
        parts: [UploadPart]
    ) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = Method.POST.rawValue

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        for (k, v) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(v)\r\n".data(using: .utf8)!)
        }

        for p in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(p.name)\"; filename=\"\(p.filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(p.mime)\r\n\r\n".data(using: .utf8)!)
            body.append(p.data)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw NetworkError.noData }

        if http.statusCode == 401 {
            if let refresher = authRefresher {
                try await refresher.refreshToken()
                try await uploadMultipart(url: url, fields: fields, parts: parts)
                return
            } else {
                throw NetworkError.unauthorized
            }
        }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.server(status: http.statusCode, data: nil)
        }
    }
}

// MARK: - Вспомогательные типы/кодеки
struct Empty: Decodable {}

struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ enc: Encodable) { self.encodeFunc = { try enc.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

extension JSONDecoder {
    static var api: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static var api: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}
