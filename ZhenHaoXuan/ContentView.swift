import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("首页")
                }
                .tag(0)

            NavigationStack {
                SettingsView()
            }
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("设置")
                }
                .tag(1)
        }
        .tint(AppPalette.brandBlue)
    }
}

enum AppPalette {
    static let brandBlue = Color(red: 0.20, green: 0.49, blue: 0.93)
    static let brandBlueDeep = Color(red: 0.12, green: 0.33, blue: 0.74)
    static let brandSky = Color(red: 0.52, green: 0.82, blue: 0.98)
    static let brandOrange = Color(red: 0.98, green: 0.61, blue: 0.24)
    static let brandOrangeDeep = Color(red: 0.93, green: 0.40, blue: 0.17)
    static let surface = Color(.secondarySystemBackground)
    static let elevatedSurface = Color(.systemBackground)
    static let line = Color.black.opacity(0.07)
    static let softText = Color.secondary
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    AppPalette.brandBlue.opacity(0.08),
                    AppPalette.brandOrange.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppPalette.brandSky.opacity(0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 150, y: -280)

            Circle()
                .fill(AppPalette.brandOrange.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: -140, y: 260)
        }
        .ignoresSafeArea()
    }
}

struct AppCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppPalette.elevatedSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, y: 8)
    }
}

extension View {
    func appCard(cornerRadius: CGFloat = 24, padding: CGFloat = 18) -> some View {
        modifier(AppCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct AppPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)

            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

// MARK: - View Extension for Page Animation

extension View {
    func withPageAnimation(delay: Double = 0) -> some View {
        modifier(PageAnimationModifier(delay: delay))
    }
}

struct PageAnimationModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false
    @State private var hasAnimated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 60)
            .onAppear {
                guard !hasAnimated else { return }
                hasAnimated = true
                appeared = false

                let duration: Double = reduceMotion ? 0.01 : 0.6
                let animDelay: Double = reduceMotion ? 0 : delay

                DispatchQueue.main.asyncAfter(deadline: .now() + animDelay) {
                    withAnimation(.smooth(duration: duration, extraBounce: 0.1)) {
                        appeared = true
                    }
                }
            }
    }
}
#Preview{
    ContentView()
}
