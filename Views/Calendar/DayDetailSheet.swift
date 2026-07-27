import SwiftUI

// 날짜를 탭하면 바로 입력 화면으로 가던 것을 이 읽기 전용 요약 화면으로 바꿨다 — 입력은 대신
// 캘린더 화면 우측 상단의 "+" 버튼(오늘 날짜 기본)이나, 이 화면 우측 상단의 "추가" 버튼(이 날짜
// 기준)으로 들어간다.
struct DayDetailSheet: View {
    let date: Date
    let mood: MoodLogEntry?
    let coffees: [CoffeeLogEntry]
    let exercises: [ExerciseLogEntry]
    let medicationLogs: [MedicationLogEntry]
    var onAddEntry: () -> Void
    // 수정/삭제 후 캘린더 데이터를 다시 불러온다 — 이 화면 자체는 mood/coffees/exercises를 그대로
    // 받아 보여주기만 하므로(상태를 직접 들고 있지 않음), 부모가 다시 불러오면 이 시트가 열린 채로도
    // 최신 값으로 갱신된다.
    var onRefresh: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditingMood = false
    @State private var editingCoffee: CoffeeLogEntry?
    @State private var editingExercise: ExerciseLogEntry?
    @State private var editingMedicationLog: MedicationLogEntry?
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
        mood == nil && coffees.isEmpty && exercises.isEmpty && medicationLogs.isEmpty
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
                            } onDelete: {
                                Task { await deleteMood(mood) }
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
                                } onDelete: {
                                    Task { await deleteCoffee(entry) }
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
                                } onDelete: {
                                    Task { await deleteExercise(entry) }
                                }
                            }
                            .swipeToDelete { Task { await deleteExercise(entry) } }
                        }
                    }
                }

                if !medicationLogs.isEmpty {
                    // 실제 약 이름 대신 어느 시간대(아침/점심/저녁/취침전/필요시)에 복용했는지만
                    // 보여준다 — 이 화면에서는 "그 시간대를 챙겼는지"가 중요하지, 약 이름 자체는
                    // 필요 없다(등록 목록은 설정의 약 등록 화면에 따로 있음). 삭제는 지원하지 않고
                    // (실수로 지웠다가 잘못된 시간대로 다시 체크하기보다 수정으로 바로잡는 게 안전)
                    // 수정 아이콘만 남긴다.
                    Section("약 복용 \(medicationLogs.count)건") {
                        ForEach(medicationLogs) { entry in
                            HStack {
                                Text(entry.timing.flatMap(MedicationTiming.init(rawValue:))?.label ?? "약 복용")
                                Spacer()
                                Button {
                                    editingMedicationLog = entry
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
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
            .sheet(item: $editingMedicationLog) { entry in
                NavigationStack {
                    MedicationLogEditForm(entry: entry, onSaved: {
                        await onRefresh()
                        editingMedicationLog = nil
                    })
                }
            }
        }
    }

    @ViewBuilder
    private func rowActions(onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
