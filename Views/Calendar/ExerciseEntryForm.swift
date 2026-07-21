import SwiftUI

struct ExerciseEntryForm: View {
    let date: Date
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
                    Text("저장")
                }
            }
            .disabled(isSaving)
        }
        .task { await loadEntries() }
        .onChange(of: durationMinutes) { _, _ in
            endTime = startTime.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
        .onChange(of: startTime) { _, newStart in
            endTime = newStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
        }
        .onChange(of: endTime) { _, newEnd in
            let minutes = Int((newEnd.timeIntervalSince(startTime) / 60).rounded())
            durationMinutes = min(300, max(1, minutes))
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
            try await ExerciseService.logExercise(
                start: effectiveStart,
                end: effectiveEnd,
                type: finalType,
                intensity: intensity
            )
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
