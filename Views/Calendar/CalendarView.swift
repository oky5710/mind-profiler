import SwiftUI

struct CalendarView: View {
    @State private var viewModel = CalendarViewModel()
    // 날짜를 탭하면 그날 입력된 내용을 보여주는 요약 시트, "+" 버튼(또는 요약 시트 안의 추가
    // 버튼)을 탭하면 입력 화면으로 가는 시트 — 서로 다른 상태로 나눠서 각자 필요할 때만 뜨게 한다.
    @State private var selectedDetailDay: SelectedDay?
    @State private var selectedEntryDay: SelectedDay?
    // 요약 시트의 "추가" 버튼을 누르면, 시트가 아직 떠 있는 동안 바로 입력 시트를 띄우지 않고
    // 여기 담아뒀다가 onDismiss에서 연다 — SwiftUI는 형제 .sheet를 동시에 못 띄운다.
    @State private var pendingEntryDay: SelectedDay?
    // UIKit(UIScreen) 없이 실제 레이아웃 높이를 구하기 위해 GeometryReader로 실측한다
    // (AGENTS.md: UIKit 사용 금지) — 실측 전에는 대략적인 기본값으로 잠깐 대체한다.
    @State private var headerHeight: CGFloat = 44
    @State private var weekdayHeaderHeight: CGFloat = 36

    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    header
                        .measureHeight { headerHeight = $0 }
                    weekdayHeader
                        .measureHeight { weekdayHeaderHeight = $0 }
                    Divider()
                    calendarGrid(rowHeight: rowHeight(forTotalHeight: geo.size.height))
                    Divider()

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                    }

                    Spacer(minLength: 0)
                }
            }
            .navigationTitle("캘린더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("캘린더").font(Typography.screenTitle)
                }
                // 날짜를 탭하면 이제 그날 기록을 보여주기만 하므로, 입력은 이 버튼(오늘 날짜
                // 기본)으로 따로 들어간다.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedEntryDay = SelectedDay(date: Date())
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        // 캘린더 탭을 다시 들어올 때마다(다른 기기/화면에서 바뀌었을 수도 있으니) 매번 새로
        // 불러온다 — .task는 TabView에서 탭을 오갈 때 다시 실행된다는 보장이 없어 .onAppear를 쓴다.
        .onAppear {
            Task { await viewModel.reload() }
        }
        .sheet(item: $selectedDetailDay, onDismiss: {
            if let pendingEntryDay {
                selectedEntryDay = pendingEntryDay
                self.pendingEntryDay = nil
            }
        }) { day in
            DayDetailSheet(
                date: day.date,
                mood: viewModel.mood(on: day.date),
                coffees: viewModel.coffees(on: day.date),
                exercises: viewModel.exercises(on: day.date),
                medicationLogs: viewModel.medicationLogs(on: day.date)
            ) {
                pendingEntryDay = day
            } onRefresh: {
                await viewModel.reload()
            }
        }
        .sheet(item: $selectedEntryDay) { day in
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
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom)
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
        .padding(.vertical, 10)
    }

    private static let rowSpacing: CGFloat = 4
    private static let columnSpacing: CGFloat = 4
    private static let dateCircleSize: CGFloat = 24
    private static let minRowHeight: CGFloat = 40
    // 실제 그 달의 주 수(4~6주)와 무관하게 항상 6주 기준으로 칸 높이를 나눈다 — 달마다 칸 크기가
    // 들쭉날쭉해지지 않고, 6주짜리 달이 와도 제목줄/하단 탭바를 침범하지 않는다.
    private static let fixedRowCount: CGFloat = 6
    // 주 사이에 넣는 구분선 두께 — 6주짜리 달 기준으로 항상 5개를 예약해 둔다.
    private static let weekDividerHeight: CGFloat = 1

    // 상단 헤더(월 이동)와 요일 줄이 차지하는 실측 높이를 뺀 나머지를 6등분한다.
    // 6주짜리 달 기준으로 주 사이 구분선 5개(두께 + 추가로 생기는 VStack 간격)도 함께 예약해서,
    // 구분선을 추가해도 6주짜리 달에서 하단 탭바를 침범하지 않게 한다.
    private func rowHeight(forTotalHeight totalHeight: CGFloat) -> CGFloat {
        let available = totalHeight - headerHeight - weekdayHeaderHeight
        let dividerCount = Self.fixedRowCount - 1
        let gridHeight = available
            - Self.rowSpacing * (Self.fixedRowCount - 1)
            - Self.rowSpacing * dividerCount
            - Self.weekDividerHeight * dividerCount
        return max(gridHeight / Self.fixedRowCount, Self.minRowHeight)
    }

    private func calendarGrid(rowHeight: CGFloat) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { weekIndex, week in
                if weekIndex > 0 {
                    Divider()
                }
                HStack(spacing: Self.columnSpacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, date in
                        if let date {
                            dayCell(date: date, columnIndex: index, cellHeight: rowHeight)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: rowHeight)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // 기분만 이모지 그대로 두고(어떤 기분이었는지가 색보다 중요), 나머지는 유형별 색이 있는 원
    // 배지로 통일한다 — 여러 건이면 원 안에 개수를 숫자로 보여준다.
    private enum DayBadgeKind {
        case emoji(String)
        case circle(color: Color, count: Int)
    }

    private struct DayBadge: Identifiable {
        let id = UUID()
        let kind: DayBadgeKind
    }

    private static let circleBadgeSize: CGFloat = 14

    private func badges(mood: MoodLogEntry?, coffeeCount: Int, exerciseCount: Int, medicationCount: Int) -> [DayBadge] {
        var result: [DayBadge] = []
        if let mood, let emoji = MoodService.options.first(where: { $0.score == mood.score })?.emoji {
            result.append(DayBadge(kind: .emoji(emoji)))
        }
        if coffeeCount > 0 {
            result.append(DayBadge(kind: .circle(color: .brown, count: coffeeCount)))
        }
        if exerciseCount > 0 {
            result.append(DayBadge(kind: .circle(color: Theme.exercise, count: exerciseCount)))
        }
        if medicationCount > 0 {
            result.append(DayBadge(kind: .circle(color: .yellow, count: medicationCount)))
        }
        return result
    }

    @ViewBuilder
    private func badgeView(_ badge: DayBadge) -> some View {
        switch badge.kind {
        case .emoji(let text):
            Text(text)
                .font(.caption2)
        case .circle(let color, let count):
            Circle()
                .fill(color)
                .frame(width: Self.circleBadgeSize, height: Self.circleBadgeSize)
                .overlay {
                    if count > 1 {
                        // 노랑처럼 밝은 배경엔 흰 숫자가 잘 안 보여서, 배경 밝기에 따라 글자
                        // 색을 검정/흰색으로 바꾼다.
                        Text("\(count)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(color == .yellow ? .black : .white)
                    }
                }
        }
    }

    private func dayCell(date: Date, columnIndex: Int, cellHeight: CGFloat) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let mood = viewModel.mood(on: date)
        let coffeeCount = viewModel.coffees(on: date).count
        let exerciseCount = viewModel.exercises(on: date).count
        let medicationCount = viewModel.medicationLogs(on: date).count
        let isToday = Calendar.current.isDateInToday(date)

        let allBadges = badges(mood: mood, coffeeCount: coffeeCount, exerciseCount: exerciseCount, medicationCount: medicationCount)

        return Button {
            selectedDetailDay = SelectedDay(date: date)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day)")
                    .font(.footnote.bold())
                    .foregroundStyle(color(forColumn: columnIndex))
                    .frame(width: Self.dateCircleSize, height: Self.dateCircleSize)
                    .background(isToday ? Color.accentColor.opacity(0.2) : .clear, in: Circle())

                // 배지는 가로로 나란히 놓다가 칸 너비를 넘기면 다음 줄로 줄바꿈한다(BadgeFlowLayout).
                // 정확히 몇 줄까지 들어가는지는 미리 계산하지 않고, 칸 높이를 넘는 나머지 줄은
                // 아래 .clipped()로 그냥 잘라 숨긴다 — 날짜를 탭하면 요약 시트에서 어차피 전부 보인다.
                BadgeFlowLayout(spacing: 3) {
                    ForEach(allBadges) { badge in
                        badgeView(badge)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: cellHeight, alignment: .topLeading)
            .clipped()
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

private struct HeightMeasuring: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, newValue in onChange(newValue) }
            }
        )
    }
}

private extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(HeightMeasuring(onChange: onChange))
    }
}

#Preview {
    CalendarView()
}
