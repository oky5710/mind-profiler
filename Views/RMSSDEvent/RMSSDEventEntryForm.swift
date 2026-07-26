import SwiftUI

// rMSSD 급격한 변화 알림을 탭하면 뜨는 전용 입력 화면 — 이 앱에서 처음 쓰는 fullScreenCover다.
// 어느 탭/화면을 보고 있었든 최상단에서 여는 것이라 캘린더 입력 폼처럼 .sheet로 반쯤 걸치는 대신
// 화면 전체를 확실히 전환한다.
struct RMSSDEventEntryForm: View {
    @State private var viewModel: RMSSDEventEntryViewModel
    var onDone: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 HH:mm"
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    init(pendingEvent: RMSSDThresholdAlertCenter.PendingEvent, onDone: @escaping () -> Void) {
        self._viewModel = State(initialValue: RMSSDEventEntryViewModel(pendingEvent: pendingEvent))
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.pendingEvent.direction == .low ? "rMSSD가 급격히 낮아졌어요" : "rMSSD가 평소보다 크게 높아졌어요")
                            .font(.headline)
                        Text("\(Self.timeFormatter.string(from: viewModel.pendingEvent.occurredAt)) · \(Int(viewModel.pendingEvent.rmssdValue))ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("지금 기분") {
                    Picker("지금 기분", selection: $viewModel.selectedEmotion) {
                        ForEach(RMSSDEmotion.allCases) { emotion in
                            Text(emotion.label).tag(emotion)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("상세 내용") {
                    TextField("자세한 내용을 입력해주세요 (선택)", text: $viewModel.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    Task {
                        if await viewModel.save() {
                            onDone()
                        }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Text("저장")
                    }
                }
                .disabled(viewModel.isSaving)
            }
            .navigationTitle("기분 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { onDone() }
                }
            }
        }
    }
}
