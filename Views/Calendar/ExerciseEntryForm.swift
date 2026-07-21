import SwiftUI

struct ExerciseEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var selectedType = ExerciseService.typeOptions[0]
    @State private var useCustomType = false
    @State private var customType = ""
    @State private var durationMinutes = 30
    @State private var intensity = 3
    @State private var useStartTime = false
    @State private var startTime = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    // 시각을 입력하지 않으면 그 날의 정오를 기준으로 저장한다 — 간트 차트 등 시간축 표시를 위해
    // 시작/종료 시각이 항상 필요하지만, 정확한 시각을 모르는 기록도 허용해야 하기 때문.
    private static let defaultHour = 12

    private var effectiveStart: Date {
        useStartTime ? DateKey.combine(date: date, time: startTime) : defaultStart
    }

    private var defaultStart: Date {
        Calendar.current.date(bySettingHour: Self.defaultHour, minute: 0, second: 0, of: date) ?? date
    }

    private var effectiveEnd: Date {
        effectiveStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
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

            Section("운동 시간") {
                Stepper("\(durationMinutes)분", value: $durationMinutes, in: 1...300, step: 5)
            }

            Section("시작 시각") {
                Toggle("시각 입력", isOn: $useStartTime.animation())
                if useStartTime {
                    DatePicker("시작 시각", selection: $startTime, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "en_GB")) // 24시간 표기 강제
                        .datePickerStyle(.compact)
                }
                Text("\(Self.timeFormatter.string(from: effectiveStart)) ~ \(Self.timeFormatter.string(from: effectiveEnd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_GB")
        return formatter
    }()

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
