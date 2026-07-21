import SwiftUI

struct MoodEntryForm: View {
    let date: Date
    var onSaved: () async -> Void
    var onRefresh: () async -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var entries: [MoodLogEntry] = []
    @State private var isLoadingEntries = true
    @State private var entriesErrorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            entryList

            Text("오늘 기분은 어땠나요?")
                .font(.headline)

            HStack(spacing: 20) {
                ForEach(MoodService.options, id: \.score) { option in
                    Button {
                        Task { await save(score: option.score) }
                    } label: {
                        Text(option.emoji)
                            .font(.system(size: 40))
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

            Spacer()
        }
        .padding()
        .task { await loadEntries() }
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
            try await MoodService.logMood(date: DateKey.string(from: date), score: score)
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
