import Foundation

struct DailyValue: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
