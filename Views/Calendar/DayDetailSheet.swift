import SwiftUI

// 같은 시간대(예: "아침")에 등록된 약이 여러 개면 medicationLogs에 그만큼 로그가 들어있는데,
// 이 화면과 MedicationLogEditForm 둘 다 "그 시간대를 챙겼는지" 하나로만 다뤄야 해서 이 타입으로
// 묶어서 넘긴다.
struct MedicationTimingGroup: Identifiable {
    let timing: String?
    let entries: [MedicationLogEntry]
    var id: String { timing ?? "unknown" }

    var earliestTakenAt: Date? {
        entries.compactMap { $0.takenAt.flatMap(DateKey.parseISODate) }.min()
    }
}

// 날짜를 탭하면 바로 입력 화면으로 가던 것을 이 읽기 전용 요약 화면으로 바꿨다 — 입력은 대신
// 캘린더 화면 우측 상단의 "+" 버튼(오늘 날짜 기본)이나, 이 화면 우측 상단의 "추가" 버튼(이 날짜
// 기준)으로 들어간다.
struct DayDetailSheet: View {
    let date: Date
    let mood: MoodLogEntry?
    let coffees: [CoffeeLogEntry]
    let exercises: [ExerciseLogEntry]
    let medicationLogs: [MedicationLogEntry]
    let events: [LifeEventEntry]
    var onAddEntry: () -> Void
    // 수정/삭제 후 캘린더 데이터를 다시 불러온다 — 이 화면 자체는 mood/coffees/exercises를 그대로
    // 받아 보여주기만 하므로(상태를 직접 들고 있지 않음), 부모가 다시 불러오면 이 시트가 열린 채로도
    // 최신 값으로 갱신된다.
    var onRefresh: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditingMood = false
    @State private var editingCoffee: CoffeeLogEntry?
    @State private var editingExercise: ExerciseLogEntry?
    @State private var editingMedicationGroup: MedicationTimingGroup?
    @State private var deletionErrorMessage: String?

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 EEEE"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var isEmpty: Bool {
        mood == nil && coffees.isEmpty && exercises.isEmpty && medicationLogs.isEmpty && events.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isEmpty {
                    Text("이 날 입력된 기록이 없어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let mood {
                    Section("기분") {
                        HStack {
                            Text("\(MoodService.options.first { $0.score == mood.score }?.emoji ?? "") \(mood.score)점")
                            Spacer()
                            rowActions {
                                isEditingMood = true
                            }
                        }
                        .swipeToDelete { Task { await deleteMood(mood) } }
                    }
                }

                if !coffees.isEmpty {
                    Section("커피 \(coffees.count)잔") {
                        ForEach(coffees) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.type ?? "커피")
                                    if let entryDate = DateKey.parseISODate(entry.date) {
                                        Text(Self.timeFormatter.string(from: entryDate))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let memo = entry.memo, !memo.isEmpty {
                                    Text(memo)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                rowActions {
                                    editingCoffee = entry
                                }
                            }
                            .swipeToDelete { Task { await deleteCoffee(entry) } }
                        }
                    }
                }

                if !exercises.isEmpty {
                    Section("운동 \(exercises.count)건") {
                        ForEach(exercises) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.type)
                                    if let start = DateKey.parseISODate(entry.startedAt),
                                       let end = DateKey.parseISODate(entry.endedAt) {
                                        Text("\(Self.timeFormatter.string(from: start)) ~ \(Self.timeFormatter.string(from: end))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                rowActions {
                                    editingExercise = entry
                                }
                            }
                            .swipeToDelete { Task { await deleteExercise(entry) } }
                        }
                    }
                }

                if !medicationTimingGroups.isEmpty {
                    // "그 시간대 약을 챙겼는지"만 중요하지, 그 시간대에 약이 몇 개 등록돼 있는지나
                    // 부분적으로만 먹었는지는 개념 자체가 없다 — 그래서 시간대 하나당 등록된 약이
                    // 10개든 1개든 항상 한 줄로만 보여준다(실제 약 이름도 안 보여준다, 등록 목록은
                    // 설정의 약 등록 화면에 따로 있음). 삭제는 지원하지 않고(실수로 지웠다가 잘못된
                    // 시간대로 다시 체크하기보다 수정으로 바로잡는 게 안전) 수정 아이콘만 남긴다 —
                    // 수정하면 그 시간대에 걸린 약 전부가 한 번에 새 시간대로 옮겨간다.
                    Section("약 복용 \(medicationTimingGroups.count)건") {
                        ForEach(medicationTimingGroups) { group in
                            HStack {
                                Text(group.timing.flatMap(MedicationTiming.init(rawValue:))?.label ?? "약 복용")
                                Spacer()
                                if let takenAt = group.earliestTakenAt {
                                    Text(Self.timeFormatter.string(from: takenAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    editingMedicationGroup = group
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !events.isEmpty {
                    // 이벤트는 아직 수정(PATCH) 엔드포인트가 없어서 삭제만 지원한다 — 스와이프로만
                    // 지운다(휴지통 아이콘 버튼은 다른 섹션들과 마찬가지로 빼서 중복 없이 스와이프
                    // 하나로 통일).
                    Section("이벤트 \(events.count)건") {
                        ForEach(events) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    if let eventDate = DateKey.parseISODate(entry.date) {
                                        Text(Self.timeFormatter.string(from: eventDate))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .swipeToDelete { Task { await deleteEvent(entry) } }
                        }
                    }
                }

                if let deletionErrorMessage {
                    Text(deletionErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(Self.titleFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onAddEntry()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .sheet(isPresented: $isEditingMood) {
                NavigationStack {
                    MoodEntryForm(date: date, editingEntry: mood, onSaved: {
                        await onRefresh()
                        isEditingMood = false
                    }, onRefresh: onRefresh)
                }
            }
            .sheet(item: $editingCoffee) { entry in
                NavigationStack {
                    CoffeeEntryForm(date: date, editingEntry: entry, onSaved: {
                        await onRefresh()
                        editingCoffee = nil
                    }, onRefresh: onRefresh)
                }
            }
            .sheet(item: $editingExercise) { entry in
                NavigationStack {
                    ExerciseEntryForm(date: date, editingEntry: entry, onSaved: {
                        await onRefresh()
                        editingExercise = nil
                    }, onRefresh: onRefresh)
                }
            }
            .sheet(item: $editingMedicationGroup) { group in
                NavigationStack {
                    MedicationLogEditForm(entries: group.entries, onSaved: {
                        await onRefresh()
                        editingMedicationGroup = nil
                    }, onRefresh: onRefresh)
                }
            }
        }
    }

    // 휴지통 아이콘 버튼은 뺐다 — 삭제는 스와이프(.swipeToDelete)만으로 충분하고, 아이콘 버튼까지
    // 같이 있으면 같은 동작이 중복으로 보인다.
    @ViewBuilder
    private func rowActions(onEdit: @escaping () -> Void) -> some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // 시간대 하나(예: "아침")에 여러 약이 등록돼 있으면 medicationLogs에 그 시간대·그 날짜의
    // 로그가 약 개수만큼 들어있다 — 화면에는 "그 시간대를 챙겼는지" 하나로만 보여줘야 하니 시간대
    // 기준으로 묶는다.
    private var medicationTimingGroups: [MedicationTimingGroup] {
        let grouped = Dictionary(grouping: medicationLogs, by: \.timing)
        let order = MedicationTiming.allCases.map(\.rawValue)
        return grouped
            .map { MedicationTimingGroup(timing: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.timing.flatMap { order.firstIndex(of: $0) } ?? order.count
                let rhsIndex = rhs.timing.flatMap { order.firstIndex(of: $0) } ?? order.count
                return lhsIndex < rhsIndex
            }
    }

    private func deleteMood(_ entry: MoodLogEntry) async {
        deletionErrorMessage = nil
        do {
            try await MoodService.removeMood(id: entry.id)
            await onRefresh()
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    private func deleteCoffee(_ entry: CoffeeLogEntry) async {
        deletionErrorMessage = nil
        do {
            try await CoffeeService.removeCoffee(id: entry.id)
            await onRefresh()
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    private func deleteExercise(_ entry: ExerciseLogEntry) async {
        deletionErrorMessage = nil
        do {
            try await ExerciseService.removeExercise(id: entry.id)
            await onRefresh()
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    private func deleteEvent(_ entry: LifeEventEntry) async {
        deletionErrorMessage = nil
        do {
            try await LifeEventService.removeEvent(id: entry.id)
            await onRefresh()
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }
}

private extension View {
    // rowActions의 명시적 휴지통 버튼과는 별개로, 표준 iOS 스와이프 삭제 제스처도 그대로 지원한다 —
    // 둘 다 같은 삭제 동작을 부르므로 어느 쪽을 써도 결과는 같다.
    func swipeToDelete(action: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing) {
            Button(role: .destructive, action: action) {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}
