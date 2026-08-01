import SwiftUI

struct OnboardingView: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                introduction
                section(
                    number: "2",
                    title: "이 앱이 하는 일",
                    body: "패턴을 찾는 앱입니다.",
                    items: ["하루의 변화 기록", "장기적인 추세 확인", "생활 습관과의 관계 탐색"],
                    footnote: "의학적 진단을 제공하지 않습니다."
                )
                interpretationSection
                closingSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 36)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            Button("시작하기", action: onStart)
                .font(Typography.button)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mind Profiler")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.primary)
            Text("당신의 하루를 숫자로 이해해 보세요.")
                .font(.title3.bold())
            Text("심박변이도(HRV), 수면, 운동 등의 데이터를 통해 나만의 패턴을 발견할 수 있습니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section(
        number: String,
        title: String,
        body: String,
        items: [String],
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(number). \(title)")
                .font(.title3.bold())
            Text(body)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
            .font(.subheadline)
            Text(footnote)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
        }
    }

    private var interpretationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. 해석할 때 주의할 점")
                .font(.title3.bold())
            Text("한 번의 측정보다 추세가 중요합니다.")
                .font(.body.bold())
            Text("HRV는 다음과 같은 영향을 받을 수 있습니다.")
            let factors = ["수면", "운동", "스트레스", "카페인", "음주", "측정 환경"]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 8) {
                ForEach(factors, id: \.self) { factor in
                    Text(factor)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.primary50, in: Capsule())
                }
            }
            Text("오늘 수치가 낮다고 해서 반드시 건강이 나쁘다는 의미는 아닙니다.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var closingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("4. 마지막")
                .font(.title3.bold())
            Text("당신의 데이터는 당신을 이해하기 위한 단서입니다.")
            Text("숫자는 정답이 아니라,\n스스로를 이해하기 위한 시작점입니다.")
                .font(.body.bold())
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    OnboardingView {}
}
