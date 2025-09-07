
import Foundation

/// Drop-in helper you can call from your current CalendarViewModel without rewriting it.
/// Call `loadMonthOfflineAware(for:)` wherever you load month (range/day).
public protocol CalendarMonthConsumer: AnyObject {
    var items: [CachedWorkout] { get set }     // or adapt to your CalendarItem by mapping back
    var isOfflineFallback: Bool { get set }
}

public final class CalendarOfflineLoader {
    private let repo: OfflineWorkoutRepository
    public init(repo: OfflineWorkoutRepository) { self.repo = repo }

    public func loadMonthOfflineAware(for date: Date, into consumer: CalendarMonthConsumer) async {
        let mk = MonthKey.from(date: date)
        let before = Date()
        let fresh = await repo.loadMonth(mk, source: .networkThenCache)
        consumer.items = fresh
        consumer.isOfflineFallback = !fresh.isEmpty && Date().timeIntervalSince(before) < 0.5
    }
}

/*
 MINIMAL PATCH (example):

 final class CalendarViewModel: ObservableObject, CalendarMonthConsumer {
     @Published var items: [CachedWorkout] = []
     @Published var isOfflineFallback = false

     private let offline: CalendarOfflineLoader

     init(offline: CalendarOfflineLoader /*, ... your deps */) {
         self.offline = offline
     }

     @MainActor
     func loadCurrentMonth() async {
         await offline.loadMonthOfflineAware(for: currentDate, into: self)
     }
 }
*/
