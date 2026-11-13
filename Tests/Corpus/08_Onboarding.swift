import SwiftUI

// MARK: - Model

struct OnboardingFeature: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let title: String
    let detail: String
}

struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let colors: [Color]
    let symbol: String
    let features: [OnboardingFeature]
}

extension OnboardingPage {
    static let all: [OnboardingPage] = [
        OnboardingPage(
            id: 0, title: "Welcome to Orbit",
            subtitle: "Plan your days, track your habits and stay focused.",
            colors: [.indigo, .purple], symbol: "sparkles",
            features: [
                OnboardingFeature(symbol: "checkmark.circle.fill", color: .green, title: "Smart tasks", detail: "Capture to-dos in seconds and let Orbit sort them."),
                OnboardingFeature(symbol: "bell.badge.fill", color: .orange, title: "Gentle reminders", detail: "Nudges that arrive when they actually help."),
                OnboardingFeature(symbol: "icloud.fill", color: .blue, title: "Always in sync", detail: "Everything stays up to date on all your devices."),
            ]),
        OnboardingPage(
            id: 1, title: "Build better habits",
            subtitle: "Small streaks add up to big changes.",
            colors: [.orange, .pink], symbol: "flame.fill",
            features: [
                OnboardingFeature(symbol: "chart.bar.fill", color: .pink, title: "Insights", detail: "See trends across weeks and months."),
                OnboardingFeature(symbol: "trophy.fill", color: .yellow, title: "Milestones", detail: "Celebrate every streak you reach."),
            ]),
        OnboardingPage(
            id: 2, title: "You are in control",
            subtitle: "Your data stays on your device unless you say otherwise.",
            colors: [.teal, .green], symbol: "lock.shield.fill",
            features: [
                OnboardingFeature(symbol: "hand.raised.fill", color: .teal, title: "Private by design", detail: "No tracking, no ads, ever."),
                OnboardingFeature(symbol: "square.and.arrow.up", color: .green, title: "Export anytime", detail: "Take your data with you in one tap."),
            ]),
    ]
}

// MARK: - Subviews

struct OnboardingIllustration: View {
    let colors: [Color]
    let symbol: String
    @State private var floating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 200, height: 200)
                .shadow(color: colors[0].opacity(0.4), radius: 24, y: 12)
            Circle()
                .strokeBorder(.white.opacity(0.35), lineWidth: 2)
                .frame(width: 240, height: 240)
            Circle()
                .fill(colors[1].opacity(0.5))
                .frame(width: 36, height: 36)
                .offset(x: 100, y: -90)
            RoundedRectangle(cornerRadius: 6)
                .fill(colors[0].opacity(0.6))
                .frame(width: 22, height: 22)
                .rotationEffect(.degrees(20))
                .offset(x: -110, y: 70)
            Image(systemName: symbol)
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: floating ? -6 : 6)
        }
        .frame(height: 260)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { floating = true }
        }
        .accessibilityHidden(true)
    }
}

struct OnboardingFeatureRow: View {
    let feature: OnboardingFeature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.symbol)
                .font(.title2)
                .foregroundStyle(feature.color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.headline)
                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 22 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                OnboardingIllustration(colors: page.colors, symbol: page.symbol)
                    .padding(.top, 24)
                VStack(spacing: 8) {
                    Text(page.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text(page.subtitle).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(page.features) { OnboardingFeatureRow(feature: $0) }
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Screen

struct OnboardingScreen: View {
    @State private var index = 0
    private let pages = OnboardingPage.all

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { index = pages.count - 1 }
                    .opacity(index == pages.count - 1 ? 0 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            TabView(selection: $index) {
                ForEach(pages) { page in
                    OnboardingPageView(page: page).tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                OnboardingPageIndicator(count: pages.count, current: index)
                Button {
                    withAnimation { index = min(index + 1, pages.count - 1) }
                } label: {
                    Text(index == pages.count - 1 ? "Get Started" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .padding(.top, 12)
            .background(.background)
        }
    }
}

#Preview {
    OnboardingScreen()
}

#Preview("Dark") {
    OnboardingScreen().preferredColorScheme(.dark)
}
