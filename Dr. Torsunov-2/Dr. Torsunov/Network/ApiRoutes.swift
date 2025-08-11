// ApiRoutes.swift
import Foundation

// MARK: - BASE
enum APIEnv {
    static var baseURL: URL {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BASE_URL") as? String,
           let u = URL(string: s) { return u }
        return URL(string: "https://revive-server.dev.myrevive.app")!
    }
}

// MARK: - ROUTES
enum ApiRoutes {

    // MARK: Auth
    enum Auth {
        // то, что ожидает текущий код
        static var login: URL { url("auth/login") }   // email+password
        static var apple: URL { url("auth/apple") }   // Sign in with Apple

        // дополнительные
        static var demoSignIn: URL  { url("auth/demo") }
        static var refresh: URL     { url("auth/refresh") }
        static var logout: URL      { url("auth/logout") }

        // алиас для совместимости
        static var appleSignIn: URL { apple }
    }

    // MARK: Profile / User
    enum Profile {
        static var me: URL        { url("user") }
        static var physical: URL  { url("user/physical") }
        static var avatar: URL    { url("user/avatar") }
    }

    // MARK: Workouts
    enum Workouts {
        static var list: URL                   { url("workouts") }              // GET
        static func by(id: String) -> URL      { url("workouts/\(id)") }        // GET
        static var upload: URL                 { url("workouts") }              // POST
    }

    // MARK: Activities
    enum Activities {
        static var list: URL                   { url("activities") }                    // GET
        static func by(id: String) -> URL      { url("activities/\(id)") }             // GET
        static func submit(id: String) -> URL  { url("activities/\(id)/submit") }      // POST
        static var upload: URL                 { url("activities") }                    // POST
    }

    // MARK: Calendar
    enum Calendar {
        static func get(email: String) -> URL    { url("calendar",      query: ["email": email]) }
        static func add(email: String) -> URL    { url("calendar/add",  query: ["email": email]) }
        static func delete(email: String) -> URL { url("calendar/delete",query: ["email": email]) }
    }

    // MARK: Inspector
    enum Inspector {
        static var toCheck: URL       { url("inspector/to_check") }
        static var fullCheck: URL     { url("inspector/full_check") }
        static var checkWorkout: URL  { url("add_workout_check") } // как во Flutter
    }

    // MARK: Chat
    enum Chat {
        static var ask: URL           { url("chat/ask") }
        static var askAudio: URL      { url("chat/ask/audio") }
        static var list: URL          { url("chat/messages") }

        // алиасы под существующий код
        static var question: URL      { ask }
        static var questionAudio: URL { askAudio }
    }

    // (опционально) статические ссылки
    enum StaticLinks {
        static var privacy: URL { URL(string: "https://myrevive.app/privacy")! }
        static var terms: URL   { URL(string: "https://myrevive.app/terms")! }
        static var support: URL { URL(string: "https://t.me/+nEbw3Z-mCiFkYTA0")! }
    }
}

// MARK: - Helpers
private extension ApiRoutes {
    static func url(_ path: String, query: [String: String]? = nil) -> URL {
        var url = APIEnv.baseURL.appendingPathComponent(path)
        if let query, !query.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = comps.url ?? url
        }
        return url
    }
}
