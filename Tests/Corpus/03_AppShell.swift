import SwiftUI
import Observation

// MARK: - Model

enum ShellTab: Hashable {
    case home, explore, inbox, account
}

struct ShellMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let symbol: String
    let color: Color
}

struct ShellActivity: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

@Observable
final class ShellDashboardModel {
    var metrics: [ShellMetric] = []
    var activity: [ShellActivity] = []
    var unread = 0

    func load() {
        metrics = [
            ShellMetric(title: "Revenue", value: "$12.4k", symbol: "dollarsign.circle.fill", color: .green),
            ShellMetric(title: "Orders", value: "318", symbol: "shippingbox.fill", color: .blue),
            ShellMetric(title: "Visitors", value: "9,204", symbol: "person.2.fill", color: .orange),
        ]
        activity = [
            ShellActivity(title: "New order #4821", detail: "2 items, paid with card", symbol: "cart.fill"),
            ShellActivity(title: "Refund issued", detail: "Order #4790", symbol: "arrow.uturn.backward.circle.fill"),
            ShellActivity(title: "Product low on stock", detail: "Canvas Tote has 4 left", symbol: "exclamationmark.triangle.fill"),
            ShellActivity(title: "New review", detail: "5 stars from Jordan", symbol: "star.fill"),
        ]
        unread = 3
    }
}

// MARK: - Subviews

struct ShellMetricCard: View {
    let metric: ShellMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.symbol)
                .font(.title2)
                .foregroundStyle(metric.color)
            Text(metric.value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(metric.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ShellHomeTab: View {
    var model: ShellDashboardModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        ForEach(model.metrics) { ShellMetricCard(metric: $0) }
                    }
                    Text("Recent activity").font(.headline)
                    VStack(spacing: 0) {
                        ForEach(model.activity) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.symbol)
                                    .frame(width: 32, height: 32)
                                    .background(.tint.opacity(0.15), in: Circle())
                                VStack(alignment: .leading) {
                                    Text(item.title).font(.subheadline.weight(.medium))
                                    Text(item.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(12)
                            if item.id != model.activity.last?.id { Divider().padding(.leading, 56) }
                        }
                    }
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(16)
            }
            .navigationTitle("Dashboard")
        }
    }
}

struct ShellPlaceholderTab: View {
    let title: String
    let symbol: String
    let rows: [String]

    var body: some View {
        NavigationStack {
            List(rows, id: \.self) { row in
                Label(row, systemImage: symbol)
            }
            .navigationTitle(title)
        }
    }
}

// MARK: - Screen

struct AppShellScreen: View {
    @State private var selection: ShellTab = .home
    @State private var model = ShellDashboardModel()

    var body: some View {
        TabView(selection: $selection) {
            ShellHomeTab(model: model)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(ShellTab.home)

            ShellPlaceholderTab(title: "Explore", symbol: "sparkles",
                                rows: ["Trending products", "New arrivals", "Staff picks", "Collections"])
                .tabItem { Label("Explore", systemImage: "safari.fill") }
                .tag(ShellTab.explore)

            ShellPlaceholderTab(title: "Inbox", symbol: "envelope",
                                rows: ["Welcome to the team", "Your weekly summary", "Invoice available"])
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
                .badge(model.unread)
                .tag(ShellTab.inbox)

            ShellPlaceholderTab(title: "Account", symbol: "person.crop.circle",
                                rows: ["Profile", "Billing", "Team members", "Sign out"])
                .tabItem { Label("Account", systemImage: "person.fill") }
                .tag(ShellTab.account)
        }
        .onAppear { model.load() }
    }
}

#Preview {
    AppShellScreen()
}

#Preview("Dark") {
    AppShellScreen()
        .preferredColorScheme(.dark)
}
