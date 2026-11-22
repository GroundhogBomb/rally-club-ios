import SwiftUI

struct WelcomeView: View {
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = startedAt.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0
            GeometryReader { proxy in
                let width = min(proxy.size.width * 0.58, proxy.size.height * 0.62, 380)
                ZStack {
                    Color("RallyLaunchBackground").ignoresSafeArea()
                    Image("RallyLaunchBall")
                        .resizable()
                        .frame(width: width, height: width)
                        .layerEffect(
                            ShaderLibrary.rallyBallMotion(
                                .float2(Float(width), Float(width)),
                                .float(Float(elapsed))
                            ),
                            maxSampleOffset: CGSize(width: width * 0.12, height: width * 0.12),
                            isEnabled: !reduceMotion
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(reduceMotion ? 1 : 1 - min(1, max(0, (elapsed - 2.5) / 0.35)))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                startedAt = nil
                return
            }
            startedAt = Date()
            do {
                try await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 2850))
                guard !Task.isCancelled else { return }
                onFinished()
            } catch { /* Cancellation must not finish a removed launch view. */ }
        }
    }
}
