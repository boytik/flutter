import Foundation

struct WorkoutMedia {
    let before: URL?
    let after: URL?
    let currentLayerChecked: Int?
    let currentSubLayerChecked: Int?
    let comment: String?
}

protocol WorkoutMediaRepository {
    func fetch(workoutId: String, email: String) async throws -> WorkoutMedia
}

final class WorkoutMediaRepositoryImpl: WorkoutMediaRepository {
    private let client = HTTPClient.shared

    private struct DTO: Decodable {
        let activityGraph: String?
        let heartRateGraph: String?
        let map: String?
        let photoBefore: String?
        let photoAfter: String?
        let currentLayerChecked: String?
        let currentsubLayerChecked: String?
        let comment: String?

        enum Camel: String, CodingKey {
            case activityGraph, heartRateGraph, map, photoBefore, photoAfter
            case currentLayerChecked, currentsubLayerChecked, comment
        }
        enum Snake: String, CodingKey {
            case activity_graph, heartRateGraph, map, photo_before, photo_after
            case currentLayerChecked, currentsubLayerChecked, comment
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Camel.self)
            let s = try? decoder.container(keyedBy: Snake.self)
            func pick(_ camel: Camel, _ snake: Snake) -> String? {
                (try? c.decodeIfPresent(String.self, forKey: camel))
                ?? (try? s?.decodeIfPresent(String.self, forKey: snake)) ?? nil
            }
            activityGraph          = pick(.activityGraph, .activity_graph)
            heartRateGraph         = pick(.heartRateGraph, .heartRateGraph)
            map                    = pick(.map, .map)
            photoBefore            = pick(.photoBefore, .photo_before)
            photoAfter             = pick(.photoAfter, .photo_after)
            currentLayerChecked    = pick(.currentLayerChecked, .currentLayerChecked)
            currentsubLayerChecked = pick(.currentsubLayerChecked, .currentsubLayerChecked)
            comment                = pick(.comment, .comment)
        }
    }

    func fetch(workoutId: String, email: String) async throws -> WorkoutMedia {
        let urlKey  = ApiRoutes.Workouts.metadata(workoutKey: workoutId, email: email)
        let urlId   = urlKey.replacingQueryParam("workout_key", with: "workoutId", value: workoutId)

        let endpoint: URL
        let dto: DTO
        do {
            dto = try await client.request(DTO.self, url: urlId)
            endpoint = urlId
        } catch {
            dto = try await client.request(DTO.self, url: urlKey)
            endpoint = urlKey
        }

        let comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let origin = URL(string: "\(comps?.scheme ?? "https")://\(comps?.host ?? "")")!

        let beforeU = absoluteMediaURL(dto.photoBefore, origin: origin)
        let afterU  = absoluteMediaURL(dto.photoAfter,  origin: origin)

        let layer = Int(dto.currentLayerChecked ?? "")
        let sub   = Int(dto.currentsubLayerChecked ?? "")

        return WorkoutMedia(
            before: beforeU,
            after : afterU,
            currentLayerChecked: layer,
            currentSubLayerChecked: sub,
            comment: dto.comment
        )
    }

    private func absoluteMediaURL(_ raw: String?, origin: URL) -> URL? {
        guard let s = raw, !s.isEmpty else { return nil }
        if let u = URL(string: s), u.scheme != nil { return u } 

        var path = s
        if let r = s.range(of: "/static/") {
            path = String(s[r.lowerBound...])
        }
        var comps = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        comps.path = path.hasPrefix("/") ? path : "/" + path
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }
}
