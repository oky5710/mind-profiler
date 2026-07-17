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

                    coffeeButton
                    if let coffeeErrorMessage = viewModel.coffeeErrorMessage {
                        Text(coffeeErrorMessage)
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
                    Text(viewModel.message)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(radius: 4)
                        .frame(maxWidth: 280)
                }
                .padding(.bottom, 16)
            }
        }
        .task {
            await viewModel.loadPhotoIfNeeded()
        }
        .task {
            await viewModel.loadTodayMoodIfNeeded()
        }
        .task {
            await viewModel.loadTodayCoffeeCountIfNeeded()
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

    private var coffeeButton: some View {
        Button {
            Task { await viewModel.logCoffee() }
        } label: {
            HStack(spacing: 6) {
                Text("☕").font(.system(size: 22))
                Text("커피").foregroundStyle(.white)
                if viewModel.todayCoffeeCount > 0 {
                    Text("\(viewModel.todayCoffeeCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.red, in: Circle())
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.black.opacity(0.35), in: Capsule())
        }
    }

    @ViewBuilder
    private var photoLayer: some View {
        if let photoURL = viewModel.photoURL {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    skeleton
                }
            }
        } else {
            skeleton
        }
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
