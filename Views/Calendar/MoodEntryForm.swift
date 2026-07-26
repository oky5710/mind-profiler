import SwiftUI

struct MoodEntryForm: View {
    let date: Date
    // 이 값이 있으면 새로 만들지 않고 이 기록의 점수만 바꾼다(캘린더 날짜 요약 화면의 수정 아이콘).
    var editingEntry: MoodLogEntry? = nil
    var onSaved: () async -> Void
    var onRefresh: () async -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var entries: [MoodLogEntry] = []
    @State private var isLoadingEntries = true
    @State private var entriesErrorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Text("오늘 기분은 어땠나요?")
                .font(.headline)

            HStack(spacing: 20) {
                ForEach(MoodService.options, id: \.score) { option in
                    Button {
                        Task { await save(score: option.score) }
                    } label: {
                        Text(option.emoji)
                            .font(.system(size: 40))
                            .opacity(editingEntry != nil && editingEntry?.score != option.score ? 0.4 : 1)
                    }
                    .disabled(isSaving)
                }
            }

            if isSaving {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // 수정 모드는 이 기록 하나의 점수만 바꾸는 게 목적이라, 그날 전체 기록 목록은 필요 없다.
            if editingEntry == nil {
                entryList
            }

            Spacer()
        }
        .padding()
        .task {
            if editingEntry == nil {
                await loadEntries()
            }
        }
    }

    @ViewBuilder
    private var entryList: some View {
        if isLoadingEntries {
            ProgressView()
        } else if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("이 날의 기록")
                    .font(.subheadline.bold())
                ForEach(entries) { entry in
                    HStack {
                        Text(MoodService.options.first { $0.score == entry.score }?.emoji ?? "\(entry.score)")
                        Spacer()
                        Button(role: .destructive) {
                            Task { await removeEntry(entry) }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                if let entriesErrorMessage {
                    Text(entriesErrorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadEntries() async {
        isLoadingEntries = true
        do {
            entries = try await MoodService.entries(on: date)
        } catch {
            entriesErrorMessage = error.localizedDescription
        }
        isLoadingEntries = false
    }

    private func removeEntry(_ entry: MoodLogEntry) async {
        do {
            try await MoodService.removeMood(id: entry.id)
        } catch {
            entriesErrorMessage = error.localizedDescription
        }
        await loadEntries()
        await onRefresh()
    }

    private func save(score: Int) async {
        isSaving = true
        errorMessage = nil
        do {
            if let editingEntry {
                try await MoodService.updateMood(id: editingEntry.id, date: DateKey.string(from: date), score: score)
            } else {
                try await MoodService.logMood(date: DateKey.string(from: date), score: score)
            }
            await onSaved()
        } catch APIError.server(409, _) {
            // 백엔드가 하루 1건 제약을 409로 강제한다 — mind-record 웹과 동일한 안내 문구.
            errorMessage = "오늘 기분은 이미 입력됐어요"
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
