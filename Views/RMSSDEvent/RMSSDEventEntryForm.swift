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
                    emotionGrid
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
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("저장")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
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

    // 4개씩 4줄(긍정 8개 먼저, 부정 8개 다음 — RMSSDEmotion.allCases 선언 순서 그대로) 정사각형
    // 버튼 그리드. 긍정은 초록, 부정은 빨강 계열로 색만 다르고 모양은 같다 — 선택된 칸만 그 색
    // outline을 두껍게 둘러서 표시한다.
    private var emotionGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(RMSSDEmotion.allCases) { emotion in
                emotionButton(for: emotion)
            }
        }
        .padding(.vertical, 4)
    }

    private func emotionButton(for emotion: RMSSDEmotion) -> some View {
        let isSelected = viewModel.selectedEmotion == emotion
        let color: Color = emotion.category == .positive ? Theme.systemGreen : Theme.systemRed

        return Button {
            viewModel.selectedEmotion = emotion
        } label: {
            Text(emotion.label)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .background(color.opacity(isSelected ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? color : Theme.systemGray5, lineWidth: isSelected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }
}
