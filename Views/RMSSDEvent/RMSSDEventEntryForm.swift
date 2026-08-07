import SwiftUI

// rMSSD 급격한 변화 알림을 탭하면 뜨는 전용 입력 화면 — 이 앱에서 처음 쓰는 fullScreenCover다.
// 어느 탭/화면을 보고 있었든 최상단에서 여는 것이라 캘린더 입력 폼처럼 .sheet로 반쯤 걸치는 대신
// 화면 전체를 확실히 전환한다.
struct RMSSDEventEntryForm: View {
    @Environment(AuthViewModel.self) private var authViewModel
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
                        Text(viewModel.pendingEvent.direction == .low ? "\(authViewModel.hrvTerm)가 급격히 낮아졌어요" : "\(authViewModel.hrvTerm)가 평소보다 크게 높아졌어요")
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
                // Form 안 버튼은 기본적으로 흰 배경의 행(row)으로 감싸진다 — 이 버튼은 색 자체가
                // 강조 배경이라 그 흰 배경이 테두리처럼 남아 어색해서 없앤다.
                .listRowBackground(Color.clear)
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(RMSSDEmotion.allCases) { emotion in
                emotionButton(for: emotion)
            }
        }
        .padding(.vertical, 4)
    }

    private func emotionButton(for emotion: RMSSDEmotion) -> some View {
        let isSelected = viewModel.selectedEmotion == emotion
        let color: Color = emotion.category == .positive ? Theme.systemGreen : Theme.systemRed
        // systemGreen은 글씨로 쓰기엔 너무 옅어서 잘 안 보인다 — 배경/테두리는 그대로 두고, 글씨
        // 색만 검정을 섞어 더 진하게 만든다.
        let textColor: Color = emotion.category == .positive ? color.mix(with: .black, by: 0.35) : color

        return Button {
            viewModel.selectedEmotion = emotion
        } label: {
            // aspectRatio를 Text에 직접 걸면 Text의 원래(한 줄 높이) 크기를 기준으로 정사각형을
            // 잡아서 버튼이 글씨 한 줄 높이만 한 작은 정사각형으로 쪼그라들고, 그 안에서 글씨가
            // 잘려 안 보였다 — 자체 크기가 없는 도형(RoundedRectangle)에 aspectRatio를 걸어야
            // 그리드 칸의 실제 너비(4등분, 25%)를 그대로 정사각형 한 변으로 쓴다.
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(isSelected ? 0.15 : 0.08))
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? color : Theme.systemGray5, lineWidth: isSelected ? 2 : 1)
                )
                .overlay(
                    Text(emotion.label)
                        .font(.footnote)
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 2)
                )
        }
        .buttonStyle(.plain)
        // Picker 대신 커스텀 버튼으로 바꾸면서 선택 상태가 테두리 색으로만 표현돼, VoiceOver는
        // 어느 칸이 선택됐는지 구분할 수 없었다 — 선택된 칸에 명시적으로 트레잇을 붙인다.
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
