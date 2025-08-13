
import Foundation

extension Date {
    /// Номер месяца (1–12)
    var monthNumber: Int {
        Calendar.current.component(.month, from: self)
    }
    
    /// Название месяца (первая буква заглавная)
    var monthName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: self).capitalized
    }
    
    /// Месяц и год (в верхнем регистре, как в календарях)
    var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: self).uppercased()
    }
}
