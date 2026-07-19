import SwiftUI

struct LifeEventEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var selectedType: LifeEventType = .medicationChange
    @State private var customTitle = ""
    @State private var description = ""
    @State private var time = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("유형") {
                Picker("유형", selection: $selectedType) {
                    ForEach(LifeEventType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if selectedType == .other {
                    TextField("어떤 일이었는지 입력", text: $customTitle)
                }
            }

            Section("시간") {
                DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
            }

            Section("설명") {
                TextField("자세한 내용을 입력해주세요 (선택)", text: $description, axis: .vertical)
                    .lineLimit(3...6)
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
        let title = selectedType == .other ? customTitle.trimmingCharacters(in: .whitespaces) : selectedType.label
        guard !title.isEmpty else {
            errorMessage = "내용을 입력해주세요."
            return
        }

        isSaving = true
        let combined = DateKey.combine(date: date, time: time)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await LifeEventService.logEvent(
                dateTime: combined,
                type: selectedType,
                title: title,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription
            )
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
