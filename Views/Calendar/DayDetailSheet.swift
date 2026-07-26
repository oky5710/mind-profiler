import SwiftUI

// 날짜를 탭하면 바로 입력 화면으로 가던 것을 이 읽기 전용 요약 화면으로 바꿨다 — 입력은 대신
// 캘린더 화면 우측 상단의 "+" 버튼(오늘 날짜 기본)이나, 이 화면 우측 상단의 "추가" 버튼(이 날짜
// 기준)으로 들어간다.
struct DayDetailSheet: View {
    let date: Date
    let mood: MoodLogEntry?
    let coffees: [CoffeeLogEntry]
    let exercises: [ExerciseLogEntry]
    var onAddEntry: () -> Void

    @Environment(\.dismiss) private var dismiss

    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 EEEE"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var isEmpty: Bool {
        mood == nil && coffees.isEmpty && exercises.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isEmpty {
                    Text("이 날 입력된 기록이 없어요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let mood {
                    Section("기분") {
                        Text("\(MoodService.options.first { $0.score == mood.score }?.emoji ?? "") \(mood.score)점")
                    }
                }

                if !coffees.isEmpty {
                    Section("커피 \(coffees.count)잔") {
                        ForEach(coffees) { entry in
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
                    }
                }

                if !exercises.isEmpty {
                    Section("운동 \(exercises.count)건") {
                        ForEach(exercises) { entry in
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
                    }
                }
            }
            .navigationTitle(Self.titleFormatter.string(from: date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onAddEntry()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
