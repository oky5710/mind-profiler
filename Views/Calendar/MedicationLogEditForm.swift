import SwiftUI

// 캘린더 날짜 요약 시트의 연필 아이콘으로 들어오는 수정 화면 — 복용 기록 자체(누가/언제 눌렀는지)는
// 바꿀 게 없고, 잘못 고른 시간대(아침/점심/저녁/취침전/필요시)만 바로잡는 용도라 다른 입력 폼처럼
// 크지 않다. 화면은 시간대 하나를 "그 시간대를 챙겼는지"로 다루므로, 그 시간대에 걸린 약 로그가
// 여러 개(예: 아침약 10개)여도 한 번에 전부 새 시간대로 옮긴다 — 그중 하나만 골라 옮기는 개념이
// 아니다.
struct MedicationLogEditForm: View {
    let entries: [MedicationLogEntry]
    var onSaved: () async -> Void
    // 각 로그를 순서대로 하나씩 PATCH하다 중간에 실패하면, 이미 옮겨진 로그와 아직 안 옮겨진
    // 로그가 서버에 섞여 남는다 — 진짜 트랜잭션으로 묶는 백엔드 배치 엔드포인트 없이는 이걸 완전히
    // 막을 수는 없지만, 최소한 화면이 그 실제 상태를 거짓 없이 다시 보여주도록 onSaved(성공 시
    // 새로고침+닫기)와 별개로 onRefresh(실패해도 새로고침만)를 따로 받는다.
    var onRefresh: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTiming: MedicationTiming
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(entries: [MedicationLogEntry], onSaved: @escaping () async -> Void, onRefresh: @escaping () async -> Void) {
        self.entries = entries
        self.onSaved = onSaved
        self.onRefresh = onRefresh
        self._selectedTiming = State(initialValue: entries.first?.timing.flatMap(MedicationTiming.init(rawValue:)) ?? .morning)
    }

    var body: some View {
        Form {
            Section {
                Picker("시간대", selection: $selectedTiming) {
                    ForEach(MedicationTiming.allCases) { timing in
                        Text(timing.label).tag(timing)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                if entries.count > 1 {
                    Text("이 시간대에 걸린 약 \(entries.count)개가 한 번에 새 시간대로 옮겨져요.")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Typography.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    Text("수정")
                }
            }
            .disabled(isSaving)
        }
        .navigationTitle("복용 시간대 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") { dismiss() }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true

        var succeededCount = 0
        var firstError: Error?
        for entry in entries {
            do {
                try await MedicationService.updateLog(id: entry.id, timing: selectedTiming)
                succeededCount += 1
            } catch {
                firstError = error
                break
            }
        }

        if let firstError {
            // 일부만 옮겨졌을 수 있으니, 시트는 그대로 열어두고 실패를 보여주되(재시도할 수 있게)
            // 뒤에 깔린 요약 화면은 실제로 옮겨진 만큼은 반영하도록 새로고침만 해 둔다 — 안 그러면
            // 이 폼은 실패했다고 하는데 요약 화면은 절반만 옮겨진 상태를 계속 옛날 값으로 보여준다.
            await onRefresh()
            errorMessage = entries.count > 1
                ? "\(succeededCount)/\(entries.count)개만 옮겨졌어요: \(firstError.localizedDescription)"
                : firstError.localizedDescription
        } else {
            await onSaved()
        }

        isSaving = false
    }
}
