import SwiftUI

struct DayEntrySheet: View {
    var onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: EntryType?
    // "+" 버튼은 항상 오늘 날짜로 열리지만, 항목을 고르기 전에 날짜 자체를 바꿀 수 있어야
    // 원하는 날짜를 매번 캘린더에서 직접 탭하지 않고도 입력할 수 있다.
    @State private var date: Date

    init(date: Date, onSaved: @escaping () async -> Void) {
        self._date = State(initialValue: date)
        self.onSaved = onSaved
    }

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
        List {
            Section {
                DatePicker("날짜", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            Section {
                ForEach(EntryType.allCases) { type in
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
        }
    }

    // 저장은 시트를 닫지만(onSaved), 삭제는 "이 날의 기록" 목록만 새로고침하고 시트는 열어둔 채로
    // 유지한다(onRefresh) — 여러 개를 연달아 지울 수 있어야 하는데 첫 삭제마다 시트가 닫히면 매번
    // 다시 열어야 해서 불편하다.
    private func dismissingSaved() async {
        await onSaved()
        dismiss()
    }

    @ViewBuilder
    private func formView(for type: EntryType) -> some View {
        switch type {
        case .mood:
            MoodEntryForm(date: date, onSaved: dismissingSaved, onRefresh: onSaved)
        case .coffee:
            CoffeeEntryForm(date: date, onSaved: dismissingSaved, onRefresh: onSaved)
        case .exam:
            ExamEntryForm(date: date, onSaved: dismissingSaved, onRefresh: onSaved)
        case .exercise:
            ExerciseEntryForm(date: date, onSaved: dismissingSaved, onRefresh: onSaved)
        case .medication:
            MedicationEntryForm(date: date, onSaved: dismissingSaved, onRefresh: onSaved)
        case .event:
            LifeEventEntryForm(date: date, onSaved: dismissingSaved, onRefresh: onSaved)
        }
    }
}
