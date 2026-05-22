import SwiftUI

struct LaunchSplashView: View {
    @Binding var isVisible: Bool

    @State private var markScale = 0.82
    @State private var ringScale = 0.76
    @State private var ringOpacity = 0.82
    @State private var titleOpacity = 0.0

    var body: some View {
        ZStack {
            CyberpunkTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .stroke(CyberpunkTheme.cyan.opacity(ringOpacity), lineWidth: 3)
                        .frame(width: 132, height: 132)
                        .scaleEffect(ringScale)
                        .shadow(color: CyberpunkTheme.cyan.opacity(0.7), radius: 22)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(CyberpunkTheme.elevated)
                        .frame(width: 92, height: 92)
                        .overlay(
                            Image("AppIcon")
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        )
                        .shadow(color: CyberpunkTheme.magenta.opacity(0.35), radius: 24)
                        .scaleEffect(markScale)
                }

                Text("Temirlan To Do")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(titleOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                markScale = 1
                titleOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.88)) {
                ringScale = 1.28
                ringOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                withAnimation(.easeInOut(duration: 0.28)) {
                    isVisible = false
                }
            }
        }
    }
}
