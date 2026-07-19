import SwiftUI

struct ExerciseEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var selectedType = ExerciseService.typeOptions[0]
    @State private var useCustomType = false
    @State private var customType = ""
    @State private var durationMinutes = 30
    @State private var intensity = 3
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                date: date,
                type: finalType,
                durationMinutes: durationMinutes,
                intensity: intensity
            )
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
