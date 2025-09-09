import Foundation

// MARK: - Planner routes (workout_calendar)
// NOTE: can't use fileprivate helpers from ApiRoutes.swift, so we rebuild URLs here.
extension ApiRoutes {
    enum Planner {
        // Encode email for path (copy of logic from ApiRoutes.Users.enc)
        private static func encEmailForPath(_ email: String) -> String {
            let raw = email.removingPercentEncoding ?? email
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "._-+@")
            return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
        }

        private static func makeUrl(_ segments: [String], query: [String: String]? = nil) -> URL {
            var url = APIEnv.baseURL
            for seg in segments { url.appendPathComponent(seg) }
            if let query, !query.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
                url = comps.url ?? url
            }
            return url
        }

        /// POST /workout_calendar/{email}/create
        static func createPlan(email: String) -> URL {
            makeUrl(["workout_calendar", encEmailForPath(email), "create"])
        }

        /// GET /workout_calendar/{email}/delete
        static func deletePlan(email: String) -> URL {
            makeUrl(["workout_calendar", encEmailForPath(email), "delete"])
        }

        /// POST /workout_calendar/{email}  (bulk update: move/delete workouts)
        static func updateWorkouts(email: String) -> URL {
            makeUrl(["workout_calendar", encEmailForPath(email)])
        }

        /// POST /workout_calendar  (no email in path)
        static var updateWorkoutsNoEmail: URL {
            makeUrl(["workout_calendar"])
        }
    }
}