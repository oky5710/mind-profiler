import SwiftUI

struct CoffeeEntryForm: View {
    let date: Date
    // 이 값이 있으면 새로 만들지 않고 이 기록 하나만 수정한다(캘린더 날짜 요약 화면의 수정 아이콘).
    var editingEntry: CoffeeLogEntry? = nil
    var onSaved: () async -> Void
    var onRefresh: () async -> Void

    @State private var time = Date()
    @State private var selectedType = CoffeeService.typeOptions[0]
    @State private var useCustomType = false
    @State private var customType = ""
    @State private var memo = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var entries: [CoffeeLogEntry] = []
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
            Section("종류") {
                Picker("종류", selection: $selectedType) {
                    ForEach(CoffeeService.typeOptions, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("직접 입력", isOn: $useCustomType)
                if useCustomType {
                    TextField("커피 종류", text: $customType)
                }
            }

            Section("시간") {
                DatePicker("시간", selection: $time, displayedComponents: .hourAndMinute)
            }

            Section("메모") {
                TextField("메모 (선택)", text: $memo)
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
                        Text("이 날 기록된 커피가 없어요.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
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
                                    Spacer()
                                    Text(memo)
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
    }

    private func prefill(from entry: CoffeeLogEntry) {
        if let entryDate = DateKey.parseISODate(entry.date) {
            time = entryDate
        }
        if let type = entry.type {
            if CoffeeService.typeOptions.contains(type) {
                selectedType = type
            } else {
                useCustomType = true
                customType = type
            }
        }
        memo = entry.memo ?? ""
    }

    private func loadEntries() async {
        isLoadingEntries = true
        do {
            entries = try await CoffeeService.entries(on: date)
        } catch {
            entriesErrorMessage = error.localizedDescription
        }
        isLoadingEntries = false
    }

    private func removeEntries(at offsets: IndexSet) async {
        for index in offsets {
            do {
                try await CoffeeService.removeCoffee(id: entries[index].id)
            } catch {
                entriesErrorMessage = error.localizedDescription
            }
        }
        await loadEntries()
        await onRefresh()
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let finalType = useCustomType ? customType : selectedType
        let combined = DateKey.combine(date: date, time: time)

        do {
            if let editingEntry {
                try await CoffeeService.updateCoffee(
                    id: editingEntry.id,
                    dateTime: combined,
                    type: finalType.isEmpty ? nil : finalType,
                    memo: memo.isEmpty ? nil : memo
                )
            } else {
                try await CoffeeService.logCoffee(
                    dateTime: combined,
                    type: finalType.isEmpty ? nil : finalType,
                    memo: memo.isEmpty ? nil : memo
                )
            }
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
