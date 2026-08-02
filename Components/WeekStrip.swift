import SwiftUI

// 일~토 요일 머리글과 그 아래 날짜를 보여주는 주간 스트립. 좌우로 스와이프하면 이전/다음 주로
// 넘어가고, 날짜를 탭하면 선택된다. 선택된 날짜는 Theme.primary 원 배경에 흰 글씨로 강조한다.
struct WeekStrip: View {
    @Binding var selectedDate: Date
    @State private var weekOffset = 0

    private let calendar = Calendar.current
    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private static let swipeThreshold: CGFloat = 40

    private var weekDates: [Date] {
        guard let startOfWeek = Self.startOfWeek(containing: Date(), calendar: calendar),
              let shiftedStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: startOfWeek)
        else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: shiftedStart) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { date in
                dayColumn(date)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard abs(value.translation.width) > Self.swipeThreshold else { return }
                    // 오늘이 속한 주(weekOffset 0)보다 미래 주로는 넘어가지 못하게 막는다.
                    let nextOffset = weekOffset + (value.translation.width < 0 ? 1 : -1)
                    guard nextOffset <= 0 else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        weekOffset = nextOffset
                    }
                }
        )
    }

    private func dayColumn(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        // 아직 데이터가 있을 수 없는 오늘 이후 날짜는 선택하지 못하게 막는다.
        let isFuture = date > calendar.startOfDay(for: Date())
        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 6) {
                Text(Self.weekdaySymbols[calendar.component(.weekday, from: date) - 1])
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)

                Text("\(calendar.component(.day, from: date))")
                    .font(Typography.body.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isFuture ? .secondary.opacity(0.4) : .primary))
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Theme.primary : Color.clear, in: Circle())
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
    }

    private static func startOfWeek(containing date: Date, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: date)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: date))
    }
}

#Preview {
    @Previewable @State var selectedDate = Date()
    return WeekStrip(selectedDate: $selectedDate)
}
