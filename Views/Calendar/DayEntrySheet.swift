import SwiftUI

struct DayEntrySheet: View {
    let date: Date
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: EntryType?

    var body: some View {
        NavigationStack {
            Group {
                if let selected {
                    formView(for: selected)
                } else {
                    typeList
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selected != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            self.selected = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        let base = formatter.string(from: date)
        guard let selected else { return base }
        return "\(base) · \(selected.title)"
    }

    private var typeList: some View {
        List(EntryType.allCases) { type in
            Button {
                selected = type
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.title)
                        .font(.headline)
                    Text(type.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func formView(for type: EntryType) -> some View {
        switch type {
        case .mood:
            MoodEntryForm(date: date) {
                await onSaved()
                dismiss()
            }
        case .coffee:
            CoffeeEntryForm(date: date) {
                await onSaved()
                dismiss()
            }
        case .exam:
            ExamEntryForm(date: date) {
                await onSaved()
                dismiss()
            }
        case .exercise:
            ExerciseEntryForm(date: date) {
                await onSaved()
                dismiss()
            }
        case .medication:
            MedicationEntryForm(date: date) {
                await onSaved()
                dismiss()
            }
        case .event:
            LifeEventEntryForm(date: date) {
                await onSaved()
                dismiss()
            }
        }
    }
}
