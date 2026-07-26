import SwiftUI

struct ExerciseEntryForm: View {
    let date: Date
    // 이 값이 있으면 새로 만들지 않고 이 기록 하나만 수정한다(캘린더 날짜 요약 화면의 수정 아이콘).
    var editingEntry: ExerciseLogEntry? = nil
    var onSaved: () async -> Void
    var onRefresh: () async -> Void

    @State private var selectedType = ExerciseService.typeOptions[0]
    @State private var useCustomType = false
    @State private var customType = ""
    @State private var durationMinutes = 60
    @State private var intensity = 3
    @State private var startTime = Date()
    @State private var endTime = Date().addingTimeInterval(60 * 60)
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var entries: [ExerciseLogEntry] = []
    @State private var isLoadingEntries = true
    @State private var entriesErrorMessage: String?

    // startTime/endTime/durationMinutes는 서로를 되먹임하는 onChange로 맞물려 있어서(하나 바꾸면
    // 나머지 둘도 따라 바뀜), prefill이 세 값을 순서대로 대입하면 그 되먹임이 중간에 끼어들어 마지막
    // 값을 덮어써 버린다 — 특히 5시간(300분) 넘는 기존 기록을 수정할 때, durationMinutes를 300으로
    // clamp해 두면 그 되먹임이 실제 종료 시각까지 5시간짜리로 잘라버린다. prefill 동안만 되먹임을
    // 꺼서 원래 시작/종료 시각이 그대로 보존되게 한다.
    @State private var isPrefilling = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var effectiveStart: Date {
        DateKey.combine(date: date, time: startTime)
    }

    private var effectiveEnd: Date {
        DateKey.combine(date: date, time: endTime)
    }

    var body: some View {
        Form {
            Section("운동 종류") {
                Picker("운동 종류", selection: $selectedType) {
                    ForEach(ExerciseService.typeOptions, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("직접 입력", isOn: $useCustomType)
                if useCustomType {
                    TextField("운동 이름", text: $customType)
                }
            }

            // 운동 시간을 따로 건드리지 않으면 기본 60분짜리 운동으로 저장된다.
            Section("운동 시간") {
                Stepper("\(durationMinutes)분", value: $durationMinutes, in: 1...300, step: 5)
            }

            Section("시작/종료 시각") {
                DatePicker("시작 시각", selection: $startTime, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "en_GB")) // 24시간 표기 강제
                    .datePickerStyle(.compact)
                DatePicker("종료 시각", selection: $endTime, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .datePickerStyle(.compact)
            }

            Section("운동 강도") {
                Picker("강도", selection: $intensity) {
                    ForEach(1..<6) { level in
                        Text("\(level)").tag(level)
                    }
                }
                .pickerStyle(.segmented)
                Text(ExerciseService.intensityLabels[intensity])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text(editingEntry == nil ? "저장" : "수정")
                }
            }
            .disabled(isSaving)

            // 수정 모드는 이 기록 하나만 바꾸는 게 목적이라, 그날 전체 기록 목록은 필요 없다.
            if editingEntry == nil {
                Section("이 날의 기록") {
                    if isLoadingEntries {
                        ProgressView()
                    } else if entries.isEmpty {
                        Text("이 날 기록된 운동이 없어요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.type)
                                if let start = DateKey.parseISODate(entry.startedAt),
                                   let end = DateKey.parseISODate(entry.endedAt) {
                                    Text("\(Self.timeFormatter.string(from: start)) ~ \(Self.timeFormatter.string(from: end))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            Task { await removeEntries(at: offsets) }
                        }
                    }
                    if let entriesErrorMessage {
                        Text(entriesErrorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
        }
        .task {
            if let editingEntry {
                prefill(from: editingEntry)
            } else {
                await loadEntries()
            }
        }
        .onChange(of: durationMinutes) { _, _ in
            guard !isPrefilling else { return }
            endTime = startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
        .onChange(of: startTime) { _, newStart in
            guard !isPrefilling else { return }
            endTime = newStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
        .onChange(of: endTime) { _, newEnd in
            guard !isPrefilling else { return }
            let minutes = Int((newEnd.timeIntervalSince(startTime) / 60).rounded())
            durationMinutes = min(300, max(1, minutes))
        }
    }

    private func prefill(from entry: ExerciseLogEntry) {
        isPrefilling = true
        defer { isPrefilling = false }

        if ExerciseService.typeOptions.contains(entry.type) {
            selectedType = entry.type
        } else {
            useCustomType = true
            customType = entry.type
        }
        intensity = entry.intensity ?? intensity
        if let start = DateKey.parseISODate(entry.startedAt), let end = DateKey.parseISODate(entry.endedAt) {
            startTime = start
            endTime = end
            durationMinutes = min(300, max(1, Int((end.timeIntervalSince(start) / 60).rounded())))
        }
    }

    private func loadEntries() async {
        isLoadingEntries = true
        do {
            entries = try await ExerciseService.entries(on: date)
        } catch {
            entriesErrorMessage = error.localizedDescription
        }
        isLoadingEntries = false
    }

    private func removeEntries(at offsets: IndexSet) async {
        for index in offsets {
            do {
                try await ExerciseService.removeExercise(id: entries[index].id)
            } catch {
                entriesErrorMessage = error.localizedDescription
            }
        }
        await loadEntries()
        await onRefresh()
    }

    private func save() async {
        errorMessage = nil

        let finalType = useCustomType ? customType.trimmingCharacters(in: .whitespaces) : selectedType
        guard !finalType.isEmpty else {
            errorMessage = "운동 이름을 입력해주세요."
            return
        }

        isSaving = true
        do {
            if let editingEntry {
                try await ExerciseService.updateExercise(
                    id: editingEntry.id,
                    start: effectiveStart,
                    end: effectiveEnd,
                    type: finalType,
                    intensity: intensity
                )
            } else {
                try await ExerciseService.logExercise(
                    start: effectiveStart,
                    end: effectiveEnd,
                    type: finalType,
                    intensity: intensity
                )
            }
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
