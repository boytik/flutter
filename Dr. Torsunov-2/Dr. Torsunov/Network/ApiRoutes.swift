
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
        static var login: URL      { url("auth/login") }
        static var apple: URL      { url("auth/apple") }
        static var demoSignIn: URL { url("auth/demo") }
        static var refresh: URL    { url("auth/refresh") }
        static var logout: URL     { url("auth/logout") }

        static var appleSignIn: URL { apple }
    }

    // MARK: Profile / User (текущая учётка)
    enum Profile {
        static var me: URL       { url("user") }
        static var physical: URL { url("user/physical") }
        static var avatar: URL   { url("user/avatar") }
    }

    // MARK: Workouts
    enum Workouts {
         static var list: URL                  { url("workouts") }
         static func by(id: String) -> URL     { url("workouts/\(id)") }
         static var upload: URL                { url("workouts") }

         static func calendarMonth(email: String, month: String) -> URL {
             let enc = encEmailForPath(email)
             return url("workout_calendar/\(enc)", query: ["filter_date": month])
         }

         static func calendarRange(email: String, startDate: String, endDate: String) -> URL {
             let enc = encEmailForPath(email)
             return url("workout_calendar/\(enc)", query: ["start_date": startDate, "end_date": endDate])
         }

         static func calendarRangeByQuery(email: String, startDate: String, endDate: String) -> URL {
             url("workout_calendar", query: ["email": email, "start_date": startDate, "end_date": endDate])
         }
        // ApiRoutes.swift — внутри ApiRoutes.Workouts

        /// Детали тренировки (для экрана деталки)
        /// GET /metadata?workout_key=<>&email=<>
        static func metadata(workoutKey: String, email: String) -> URL {
            url("metadata", query: [
                "workout_key": workoutKey,
                "email": email
            ])
        }

        /// Метрики / графики
        /// GET /get_diagram_data?workout_key=<>&email=<>
        static func metrics(workoutKey: String, email: String) -> URL {
            url("get_diagram_data", query: [
                "workout_key": workoutKey,
                "email": email
            ])
        }


         fileprivate static func encEmailForPath(_ email: String) -> String {
             let raw = email.removingPercentEncoding ?? email
             var allowed = CharacterSet.alphanumerics
             allowed.insert(charactersIn: "._-+")
             return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
         }
     }

     enum Activities {
         static func listWorkouts(email: String, lastDate: String) -> URL {
             url("list_workouts", query: ["email": email, "lastDate": lastDate])
         }
         static var forCheck: URL  { url("list_workouts_for_check") }
         static var fullCheck: URL { url("list_workouts_for_check_full") }

         // legacy (нужны для upload/submit)
         static var legacy_list: URL                  { url("activities") }
         static func legacy_by(id: String) -> URL     { url("activities/\(id)") }
         static func legacy_submit(id: String) -> URL { url("activities/\(id)/submit") }
         static var legacy_upload: URL                { url("activities") }
     }

     enum Inspector {
         static var checkWorkout: URL { url("add_workout_check") }
     }
    // MARK: Calendar (старые маршруты; не мешают)
    enum Calendar {
        static func get(email: String) -> URL     { url("calendar",       query: ["email": email]) }
        static func add(email: String) -> URL     { url("calendar/add",   query: ["email": email]) }
        static func delete(email: String) -> URL  { url("calendar/delete",query: ["email": email]) }
    }


    // MARK: Chat
    enum Chat {
        static var ask: URL      { url("chat/ask") }
        static var askAudio: URL { url("chat/ask/audio") }
        static var list: URL     { url("chat/messages") }

        static var question: URL      { ask }
        static var questionAudio: URL { askAudio }
    }

    enum StaticLinks {
        static var privacy: URL { URL(string: "https://myrevive.app/privacy")! }
        static var terms: URL   { URL(string: "https://myrevive.app/terms")! }
        static var support: URL { URL(string: "https://t.me/+nEbw3Z-mCiFkYTA0")! }
    }
}

// MARK: - Users (пользователь по e-mail)
extension ApiRoutes {
    enum Users {
        private static func enc(_ email: String) -> String {
            // здесь допускаем '@' в path — так уже использовалось в проекте
            let raw = email.removingPercentEncoding ?? email
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "._-+@")
            return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
        }

        static func get(email: String, short: Bool = false) -> URL {
            url(short ? "users/\(enc(email))/short" : "users/\(enc(email))")
        }
        static func update(email: String) -> URL      { url("users/\(enc(email))") }
        static func physical(email: String) -> URL    { url("users/\(enc(email))/physical") }
        static func avatar(email: String) -> URL      { url("users/\(enc(email))/avatar") }

        // Query-варианты (если вдруг понадобятся)
        static func byQuery(email: String) -> URL         { url("user",          query: ["email": email]) }
        static func physicalByQuery(email: String) -> URL { url("user/physical", query: ["email": email]) }
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
