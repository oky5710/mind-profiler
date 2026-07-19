import Charts
import SwiftUI

private extension HealthKitService.SleepStage {
    var label: String {
        switch self {
        case .deep: "깊은 수면"
        case .rem: "렘(REM)"
        case .core: "코어"
        case .unspecified: "수면(단계 미상)"
        }
    }

    var donutColor: Color {
        switch self {
        case .deep: Theme.sleepStageDeep
        case .rem: Theme.sleepStageREM
        case .core: Theme.sleepStageCore
        case .unspecified: Theme.sleepStageUnspecified
        }
    }
}

// 수면 막대(오늘의 패턴 Gantt 차트, 보고서 막대그래프)를 탭했을 때 보여주는 상세 카드 — 추정 수면
// 점수, 총 수면 시간, 단계별(코어/깊은/렘/미상) 구성 도넛 차트를 보여준다. 두 화면이 그대로 공유해서 쓴다.
// 닫기 버튼도 이 컴포넌트에 포함돼 있어서, 쓰는 화면마다 따로 만들 필요 없이 onClose만 넘기면 된다.
struct SleepDetailPanel: View {
    let sleepRange: SleepRange
    let onClose: () -> Void

    private struct Slice: Identifiable {
        let id: String
        let label: String
        let duration: TimeInterval
        let color: Color
    }

    // 각성(수면 중 깬 시간)은 수면 단계가 아니라 "그 나머지"라서, 단계 색과 헷갈리지 않게 무채색으로 둔다.
    private var slices: [Slice] {
        var slices = SleepAnalysisService.stageDisplayOrder.compactMap { stage -> Slice? in
            guard let duration = sleepRange.stageDurations[stage], duration > 0 else { return nil }
            return Slice(id: stage.rawValue, label: stage.label, duration: duration, color: stage.donutColor)
        }
        let totalDuration = sleepRange.end.timeIntervalSince(sleepRange.start)
        let awakeDuration = max(0, totalDuration - sleepRange.stageDurations.values.reduce(0, +))
        if awakeDuration >= 60 {
            slices.append(Slice(id: "awake", label: "깨어있음", duration: awakeDuration, color: .gray))
        }
        return slices
    }

    var body: some View {
        let totalDuration = sleepRange.end.timeIntervalSince(sleepRange.start)

        VStack(alignment: .leading, spacing: 6) {
            // 애플 Health 앱이 보여주는 수면 점수는 HealthKit으로 못 받아와서, 애플이 공개한 가중치
            // 구성(수면시간+취침 일관성+각성)을 흉내 낸 추정치라는 걸 "추정"으로 명시한다.
            Text("추정 수면 점수 \(sleepRange.estimatedScore)점 · \(SleepAnalysisService.scoreLabel(sleepRange.estimatedScore))")
                .font(.subheadline.bold())
            Text(
                "\(HRVAnalysisView.monthDayFormatter.string(from: sleepRange.start)) · " +
                    "\(SleepAnalysisService.formattedDuration(totalDuration)) · " +
                    "\(HRVAnalysisView.hourMinuteFormatter.string(from: sleepRange.start)) ~ \(HRVAnalysisView.hourMinuteFormatter.string(from: sleepRange.end))"
            )
            .font(.caption2)

            HStack(alignment: .center, spacing: 16) {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("시간", slice.duration),
                        innerRadius: .ratio(0.6),
                        angularInset: 1.5
                    )
                    .foregroundStyle(slice.color)
                    .cornerRadius(3)
                }
                .frame(width: 84, height: 84)

                // 도넛은 비율을 한눈에 보여주고, 옆의 색점+숫자 목록이 정확한 분 단위 값과 범례를 겸한다.
                // 단계 이름 길이가 제각각이라("코어" vs "수면(단계 미상)") 한 Text로 합치면 시간
                // 값의 세로 정렬이 줄마다 어긋난다 — Grid로 이름/시간을 열로 나눠 시간을 맞춘다.
                Grid(alignment: .leading, horizontalSpacing: 5, verticalSpacing: 3) {
                    ForEach(slices) { slice in
                        GridRow {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(slice.color)
                                    .frame(width: 7, height: 7)
                                Text(slice.label)
                            }
                            Text(SleepAnalysisService.formattedDuration(slice.duration))
                        }
                        .font(.caption2)
                    }
                }
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 8))
        // 라이트 모드에서는 배경이 흰색에 가까워 테두리가 없으면 카드가 안 보일 수 있다.
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 20))
                    .foregroundStyle(.gray)
            }
            .padding(8)
        }
    }
}
