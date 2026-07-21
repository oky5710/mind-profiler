import SwiftUI

struct LifeEventEntryForm: View {
    let date: Date
    var onSaved: () async -> Void
    var onRefresh: () async -> Void

    @State private var selectedType: LifeEventType = .medicationChange
    @State private var customTitle = ""
    @State private var description = ""
    @State private var time = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var entries: [LifeEventEntry] = []
    @State private var isLoadingEntries = true
    @State private var entriesErrorMessage: String?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var body: some View {
        Form {
            Section("이 날의 기록") {
                if isLoadingEntries {
                    ProgressView()
                } else if entries.isEmpty {
                    Text("이 날 기록된 이벤트가 없어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            if let eventDate = DateKey.parseISODate(entry.date) {
                                Text(Self.timeFormatter.string(from: eventDate))
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
        .task { await loadEntries() }
    }

    private func loadEntries() async {
        isLoadingEntries = true
        do {
            entries = try await LifeEventService.entries(on: date)
        } catch {
            entriesErrorMessage = error.localizedDescription
        }
        isLoadingEntries = false
    }

    private func removeEntries(at offsets: IndexSet) async {
        for index in offsets {
            do {
                try await LifeEventService.removeEvent(id: entries[index].id)
            } catch {
                entriesErrorMessage = error.localizedDescription
            }
        }
        await loadEntries()
        await onRefresh()
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
