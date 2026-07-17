import SwiftUI

struct CoffeeEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var time = Date()
    @State private var selectedType = CoffeeService.typeOptions[0]
    @State private var useCustomType = false
    @State private var customType = ""
    @State private var memo = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                    Text("저장")
                }
            }
            .disabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let finalType = useCustomType ? customType : selectedType
        let combined = Self.combine(date: date, time: time)

        do {
            try await CoffeeService.logCoffee(
                dateTime: combined,
                type: finalType.isEmpty ? nil : finalType,
                memo: memo.isEmpty ? nil : memo
            )
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private static func combine(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute

        return calendar.date(from: merged) ?? date
    }
}
