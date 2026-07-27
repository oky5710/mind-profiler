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
                medicationLogs: viewModel.medicationLogs(on: day.date),
                events: viewModel.events(on: day.date)
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

    // 기분은 날짜 숫자와 같은 줄에 이모지로 따로 보여주고(어떤 기분이었는지가 중요해서 색으로
    // 뭉뚱그리지 않음), 나머지(커피/운동/약복용/이벤트)만 유형별 색이 있는 원 배지로 통일한다 —
    // 개수만큼 원을 그대로 나란히 그린다(숫자로 뭉뚱그리지 않음).
    private struct DayBadge: Identifiable {
        let id = UUID()
        let color: Color
        // 화면에는 안 보이고 VoiceOver 접근성 요약에만 쓴다 — 원 배지 자체는 색으로만 구분돼서,
        // 그것만으로는 "커피"인지 "운동"인지 시각 정보 없이는 알 수 없다.
        let label: String
    }

    private static let circleBadgeSize: CGFloat = 12
    // 채도를 낮춘 파스텔 톤 — 원래 브랜드/차트 색(Theme.exercise 등)은 진해서 작은 원 배지로 쓰면
    // 너무 튀어 보인다.
    private static let coffeeBadgeColor = Color(red: 0.80, green: 0.65, blue: 0.52)
    private static let exerciseBadgeColor = Color(red: 0.70, green: 0.85, blue: 0.75)
    private static let medicationBadgeColor = Color(red: 0.98, green: 0.90, blue: 0.62)
    private static let eventBadgeColor = Color(red: 0.72, green: 0.82, blue: 0.95)

    private func badges(coffeeCount: Int, exerciseCount: Int, medicationCount: Int, eventCount: Int) -> [DayBadge] {
        // Array(repeating:count:)는 단 하나의 인스턴스를 복사하므로 id(UUID())가 전부 같아져
        // ForEach가 요구하는 고유성이 깨진다 — 매번 새로 만들어야 한다.
        func dots(_ count: Int, color: Color, label: String) -> [DayBadge] {
            (0..<count).map { _ in DayBadge(color: color, label: label) }
        }
        return dots(coffeeCount, color: Self.coffeeBadgeColor, label: "커피")
            + dots(exerciseCount, color: Self.exerciseBadgeColor, label: "운동")
            + dots(medicationCount, color: Self.medicationBadgeColor, label: "약 복용")
            + dots(eventCount, color: Self.eventBadgeColor, label: "이벤트")
    }

    // 배지 하나하나는 색만 있는 원이라 VoiceOver에 개별로 노출하면 "커피, 커피, 커피"처럼 겹쳐
    // 읽힌다 — 원 배지 전체를 하나로 묶어서 유형별 개수 요약 하나로만 읽히게 한다.
    private func badgesAccessibilitySummary(coffeeCount: Int, exerciseCount: Int, medicationCount: Int, eventCount: Int) -> String {
        var parts: [String] = []
        if coffeeCount > 0 { parts.append("커피 \(coffeeCount)건") }
        if exerciseCount > 0 { parts.append("운동 \(exerciseCount)건") }
        if medicationCount > 0 { parts.append("약 복용 \(medicationCount)건") }
        if eventCount > 0 { parts.append("이벤트 \(eventCount)건") }
        return parts.joined(separator: ", ")
    }

    private func badgeView(_ badge: DayBadge) -> some View {
        Circle()
            .fill(badge.color)
            .frame(width: Self.circleBadgeSize, height: Self.circleBadgeSize)
    }

    private func dayCell(date: Date, columnIndex: Int, cellHeight: CGFloat) -> some View {
        let day = Calendar.current.component(.day, from: date)
        let mood = viewModel.mood(on: date)
        let moodEmoji = mood.flatMap { entry in MoodService.options.first { $0.score == entry.score }?.emoji }
        let coffeeCount = viewModel.coffees(on: date).count
        let exerciseCount = viewModel.exercises(on: date).count
        let medicationCount = viewModel.medicationLogs(on: date).count
        let eventCount = viewModel.events(on: date).count
        let isToday = Calendar.current.isDateInToday(date)

        let allBadges = badges(coffeeCount: coffeeCount, exerciseCount: exerciseCount, medicationCount: medicationCount, eventCount: eventCount)

        return Button {
            selectedDetailDay = SelectedDay(date: date)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                // 날짜 숫자와 기분 이모지를 한 줄에 양 끝으로 배치한다 — 기분은 그 자체가 중요한
                // 정보라 아래 배지 줄로 내려서 다른 유형과 뒤섞이지 않고 항상 날짜 바로 옆에 보인다.
                HStack {
                    Text("\(day)")
                        .font(.footnote.bold())
                        .foregroundStyle(color(forColumn: columnIndex))
                        .frame(width: Self.dateCircleSize, height: Self.dateCircleSize)
                        .background(isToday ? Color.accentColor.opacity(0.2) : .clear, in: Circle())
                    Spacer(minLength: 0)
                    if let moodEmoji {
                        Text(moodEmoji)
                            .font(.caption2)
                    }
                }
                // 정렬을 명시하지 않으면 기본값(center)이라, 날짜 숫자의 왼쪽 끝이 아래 배지 줄의
                // 왼쪽 끝과 안 맞을 수 있다 — 둘 다 leading으로 명시해서 같은 세로선에 맞춘다.
                .frame(maxWidth: .infinity, alignment: .leading)

                // 배지는 가로로 나란히 놓다가 칸 너비를 넘기면 다음 줄로 줄바꿈한다(BadgeFlowLayout).
                // 정확히 몇 줄까지 들어가는지는 미리 계산하지 않고, 칸 높이를 넘는 나머지 줄은
                // 아래 .clipped()로 그냥 잘라 숨긴다 — 날짜를 탭하면 요약 시트에서 어차피 전부 보인다.
                BadgeFlowLayout(spacing: 3) {
                    ForEach(allBadges) { badge in
                        badgeView(badge)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(badgesAccessibilitySummary(
                    coffeeCount: coffeeCount,
                    exerciseCount: exerciseCount,
                    medicationCount: medicationCount,
                    eventCount: eventCount
                ))
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
