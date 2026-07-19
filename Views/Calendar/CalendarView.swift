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
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // 날짜 칸 높이를 고정값으로 둬서(가변 minHeight가 아니라) 그 날의 배지 개수(기분/커피/운동)와
    // 무관하게 같은 주의 모든 칸, 나아가 달력 전체의 모든 주가 항상 같은 높이로 보이게 한다.
    // 하루에 배지가 다 붙는 최악의 경우(날짜 원 + 배지 3줄)까지 잘리지 않을 만큼 넉넉하게 잡았다.
    private static let dayCellHeight: CGFloat = 80

    private var calendarGrid: some View {
        VStack(spacing: 4) {
            ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                        if let date {
                            dayCell(date: date, columnIndex: index)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: Self.dayCellHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func dayCell(date: Date, columnIndex: Int) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let mood = viewModel.mood(on: date)
        let coffeeCount = viewModel.coffees(on: date).count
        let exerciseCount = viewModel.exercises(on: date).count
        let isToday = Calendar.current.isDateInToday(date)

        return Button {
            selectedDay = SelectedDay(date: date)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.footnote.bold())
                    .foregroundStyle(color(forColumn: columnIndex))
                    .frame(width: 24, height: 24)
                    .background(isToday ? Color.accentColor.opacity(0.2) : .clear, in: Circle())

                if let mood {
                    Text(MoodService.options.first { $0.score == mood.score }?.emoji ?? "")
                        .font(.caption2)
                }
                if coffeeCount > 0 {
                    Text(coffeeCount > 1 ? "☕×\(coffeeCount)" : "☕")
                        .font(.caption2)
                        .foregroundStyle(.brown)
                }
                if exerciseCount > 0 {
                    Text(exerciseCount > 1 ? "🏃×\(exerciseCount)" : "🏃")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.dayCellHeight, alignment: .topLeading)
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
