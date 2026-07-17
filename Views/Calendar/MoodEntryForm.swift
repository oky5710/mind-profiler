import SwiftUI

struct MoodEntryForm: View {
    let date: Date
    var onSaved: () async -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

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
    }

    private func save(score: Int) async {
        isSaving = true
        errorMessage = nil
        do {
            try await MoodService.logMood(date: DateKey.string(from: date), score: score)
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
