import SwiftUI

struct HomeView: View {
    @State private var viewModel = HomeViewModel()
    @State private var hearts: [HeartParticle] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    photoLayer

                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    ForEach(hearts) { heart in
                        FloatingHeart(startX: heart.x, startY: heart.y)
                    }
                }
                .ignoresSafeArea()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    spawnHearts(at: location)
                }

                Text("Track your mind.\nFind the patterns.")
                    .font(Typography.screenTitle)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)

                VStack(spacing: 12) {
                    Spacer()

                    if viewModel.hasCheckedMood && viewModel.todayMoodScore == nil {
                        moodPicker
                    }
                    if let moodErrorMessage = viewModel.moodErrorMessage {
                        Text(moodErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }

                    // 한 줄에 다 안 들어가면 버튼 내용을 줄이는 게 아니라 버튼째로 다음 줄로 내린다
                    // (ui-style.md "버튼 안에서는 줄바꿈하지 않는다").
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            coffeeButton
                            medicationButton(timing: .morning, icon: "🌅", isTaken: viewModel.hasMorningMedicationTaken)
                            medicationButton(timing: .bedtime, icon: "🌙", isTaken: viewModel.hasBedtimeMedicationTaken)
                        }
                        VStack(spacing: 8) {
                            coffeeButton
                            HStack(spacing: 12) {
                                medicationButton(timing: .morning, icon: "🌅", isTaken: viewModel.hasMorningMedicationTaken)
                                medicationButton(timing: .bedtime, icon: "🌙", isTaken: viewModel.hasBedtimeMedicationTaken)
                            }
                        }
                    }
                    if let coffeeErrorMessage = viewModel.coffeeErrorMessage {
                        Text(coffeeErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }
                    if let medicationErrorMessage = viewModel.medicationErrorMessage {
                        Text(medicationErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(radius: 4)
                            .frame(maxWidth: 280)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        // 홈 탭에 들어올 때마다(onAppear) 다시 확인한다 — .task였다면 이 뷰가 처음 나타났을 때 딱
        // 한 번만 실행되고, 그때 네트워크 오류 등으로 실패하면 그 뒤로는 탭을 오가도 다시 시도되지
        // 않는다. 각 IfNeeded 함수가 이미 "성공적으로 확인함" 상태를 스스로 추적하므로, 매번 다시
        // 불러도 실제로 이미 성공한 항목은 그냥 바로 반환된다.
        .onAppear {
            Task { await viewModel.loadPhoto() }
            Task { await viewModel.loadTodayMoodIfNeeded() }
            Task { await viewModel.loadTodayCoffeeCountIfNeeded() }
            Task { await viewModel.loadTodayMedicationLogsIfNeeded() }
        }
    }

    private var moodPicker: some View {
        HStack(spacing: 16) {
            ForEach(MoodService.options, id: \.score) { option in
                Button {
                    Task { await viewModel.logMood(score: option.score) }
                } label: {
                    Text(option.emoji)
                        .font(.system(size: 32))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.black.opacity(0.35), in: Capsule())
    }

    // 버튼 안 내용은 항상 한 줄(HStack) — ui-style.md "버튼 안에서는 줄바꿈하지 않는다".
    private var coffeeButton: some View {
        Button {
            Task { await viewModel.logCoffee() }
        } label: {
            HStack(spacing: 4) {
                Text("☕").font(.system(size: 16))
                Text("커피").font(.caption).foregroundStyle(.white)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(alignment: .topTrailing) {
                if viewModel.todayCoffeeCount > 0 {
                    Text("\(viewModel.todayCoffeeCount)")
                        .font(.system(size: 9).bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Color.red, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    private func medicationButton(timing: MedicationTiming, icon: String, isTaken: Bool) -> some View {
        Button {
            Task { await viewModel.logMedicationQuick(timing) }
        } label: {
            HStack(spacing: 4) {
                Text(icon).font(.system(size: 16))
                Text(timing.label).font(.caption).foregroundStyle(.white)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.black.opacity(0.35), in: Capsule())
            .overlay(alignment: .topTrailing) {
                if isTaken {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .background(.white, in: Circle())
                        .offset(x: 4, y: -4)
                }
            }
        }
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let photoURL = viewModel.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    fallbackPhoto
                default:
                    skeleton
                }
            }
        } else if viewModel.isLoading {
            skeleton
        } else {
            // Pixabay fetch가 실패했을 때(네트워크 오류 등) 빈 화면 대신 보여줄 번들 내장 사진.
            fallbackPhoto
        }
    }

    private var fallbackPhoto: some View {
        Image("FallbackCatPhoto")
            .resizable()
            .scaledToFill()
    }

    private var skeleton: some View {
        Color.gray.opacity(0.4)
    }

    private func spawnHearts(at location: CGPoint) {
        for index in 0..<5 {
            Task {
                try? await Task.sleep(for: .milliseconds(index * 120))
                let particle = HeartParticle(x: location.x, y: location.y)
                hearts.append(particle)
                try? await Task.sleep(for: .milliseconds(1100))
                hearts.removeAll { $0.id == particle.id }
            }
        }
    }
}

private struct HeartParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
}

private struct FloatingHeart: View {
    let startX: CGFloat
    let startY: CGFloat

    @State private var offsetY: CGFloat = 0
    @State private var opacity: Double = 1
    private let driftX = CGFloat.random(in: -30...30)

    var body: some View {
        Text("❤️")
            .font(.system(size: 28))
            .position(x: startX + driftX, y: startY + offsetY)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1.1)) {
                    offsetY = -140
                    opacity = 0
                }
            }
    }
}

#Preview {
    HomeView()
}
