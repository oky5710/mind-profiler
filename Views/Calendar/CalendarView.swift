import SwiftUI

struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()
    @State private var selectedDay: SelectedDay?

    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                weekdayHeader
                calendarGrid

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer()
            }
            .navigationTitle("캘린더")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .sheet(item: $selectedDay) { day in
            DayEntrySheet(date: day.date) {
                await viewModel.reload()
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding()
    }

    private var monthTitle: String {
        "\(viewModel.year)년 \(viewModel.month)월"
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundStyle(color(forColumn: index))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }

    // 달력 전체 높이가 항상 최대 800pt를 넘지 않도록, 그 주 수에 맞춰 칸 높이를 나눠 계산한다 —
    // 주가 적은 달(4주)은 칸이 커지고, 많은 달(6주)은 칸이 작아지지만 전체 높이는 항상 같다.
    private static let maxCalendarGridHeight: CGFloat = 800
    private static let rowSpacing: CGFloat = 4
    private static let dateCircleSize: CGFloat = 24
    // 배지 한 줄(이모지+캡션 폰트)의 대략적인 높이 — 칸에 몇 줄까지 들어갈 수 있는지 계산하는 데만 쓴다.
    private static let badgeLineHeight: CGFloat = 16

    private var dayCellHeight: CGFloat {
        let rows = max(viewModel.weeks.count, 1)
        let available = Self.maxCalendarGridHeight - Self.rowSpacing * CGFloat(rows - 1)
        return available / CGFloat(rows)
    }

    private var calendarGrid: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                        if let date {
                            dayCell(date: date, columnIndex: index)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: dayCellHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private struct DayBadge {
        let text: String
        let color: Color
    }

    private func badges(mood: MoodLogEntry?, coffeeCount: Int, exerciseCount: Int) -> [DayBadge] {
        var result: [DayBadge] = []
        if let mood {
            result.append(DayBadge(text: MoodService.options.first { $0.score == mood.score }?.emoji ?? "", color: .primary))
        }
        if coffeeCount > 0 {
            result.append(DayBadge(text: coffeeCount > 1 ? "☕×\(coffeeCount)" : "☕", color: .brown))
        }
        if exerciseCount > 0 {
            result.append(DayBadge(text: exerciseCount > 1 ? "🏃×\(exerciseCount)" : "🏃", color: .primary))
        }
        return result
    }

    private func dayCell(date: Date, columnIndex: Int) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let mood = viewModel.mood(on: date)
        let coffeeCount = viewModel.coffees(on: date).count
        let exerciseCount = viewModel.exercises(on: date).count
        let isToday = Calendar.current.isDateInToday(date)

        let allBadges = badges(mood: mood, coffeeCount: coffeeCount, exerciseCount: exerciseCount)
        // 칸 높이(주 수에 따라 달라짐)에 실제로 들어갈 수 있는 배지 줄 수를 계산해서, 다 못 들어가면
        // 마지막 한 자리를 "+N"으로 남겨 보이지 않는 항목이 있다는 걸 알린다.
        let maxBadgeLines = max(Int((dayCellHeight - Self.dateCircleSize) / Self.badgeLineHeight), 0)
        let visibleBadges = allBadges.count > maxBadgeLines ? Array(allBadges.prefix(max(maxBadgeLines - 1, 0))) : allBadges
        let overflowCount = allBadges.count - visibleBadges.count

        return Button {
            selectedDay = SelectedDay(date: date)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.footnote.bold())
                    .foregroundStyle(color(forColumn: columnIndex))
                    .frame(width: Self.dateCircleSize, height: Self.dateCircleSize)
                    .background(isToday ? Color.accentColor.opacity(0.2) : .clear, in: Circle())

                ForEach(Array(visibleBadges.enumerated()), id: \.offset) { _, badge in
                    Text(badge.text)
                        .font(.caption2)
                        .foregroundStyle(badge.color)
                }
                if overflowCount > 0 {
                    Text("+\(overflowCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: dayCellHeight, alignment: .topLeading)
        }
        .buttonStyle(.plain)
    }

    private func color(forColumn index: Int) -> Color {
        switch index {
        case 0: .red
        case 6: .blue
        default: .primary
        }
    }
}

private struct SelectedDay: Identifiable {
    let date: Date
    var id: Date { date }
}

#Preview {
    CalendarView()
}
