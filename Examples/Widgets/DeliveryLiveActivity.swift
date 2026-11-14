import ActivityKit
import SwiftUI
import WidgetKit

// A delivery-tracking Live Activity: Lock Screen banner and every Dynamic Island region.

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Stage: String, Codable, Hashable { case preparing, onTheWay, arriving }
        var stage: Stage
        var courier: String
        var eta: Date
        var stopsAway: Int
    }

    var orderNumber: String
    var restaurant: String
    var placedAt: Date
}

extension DeliveryAttributes {
    static let preview = DeliveryAttributes(orderNumber: "A-1042", restaurant: "Green Bowl", placedAt: .now.addingTimeInterval(-15 * 60))
}

extension DeliveryAttributes.ContentState {
    static let onTheWay = Self(stage: .onTheWay, courier: "Maya", eta: .now.addingTimeInterval(12 * 60), stopsAway: 3)
    static let arriving = Self(stage: .arriving, courier: "Maya", eta: .now.addingTimeInterval(2 * 60), stopsAway: 0)
}

extension DeliveryAttributes.ContentState.Stage {
    var title: String {
        switch self {
        case .preparing: "Preparing your order"
        case .onTheWay: "On the way"
        case .arriving: "Arriving now"
        }
    }
    var step: Int {
        switch self {
        case .preparing: 0
        case .onTheWay: 1
        case .arriving: 2
        }
    }
}

struct DeliverySteps: View {
    let stage: DeliveryAttributes.ContentState.Stage
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= stage.step ? Color.green : Color.white.opacity(0.25))
                    .frame(height: 5)
            }
        }
    }
}

struct DeliveryLockScreenView: View {
    let context: ActivityViewContext<DeliveryAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "bag.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.stage.title)
                        .font(.headline)
                    Text("\(context.attributes.restaurant) · \(context.state.courier)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(timerInterval: Date.now...context.state.eta, countsDown: true)
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72, alignment: .trailing)
                    Text("min").font(.caption).foregroundStyle(.secondary)
                }
            }
            DeliverySteps(stage: context.state.stage)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryAttributes.self) { context in
            DeliveryLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.72))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.stopsAway)", systemImage: "bag.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...context.state.eta, countsDown: true)
                        .font(.headline)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.stage.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(context.state.courier) is \(context.state.stopsAway) stops away · order \(context.attributes.orderNumber)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DeliverySteps(stage: context.state.stage)
                    }
                }
            } compactLeading: {
                Image(systemName: "bag.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(timerInterval: Date.now...context.state.eta, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 40)
                    .font(.caption.weight(.semibold))
            } minimal: {
                Image(systemName: "bag.fill")
                    .foregroundStyle(.green)
            }
            .keylineTint(.green)
            .widgetURL(URL(string: "delivery://order"))
        }
    }
}

@main
struct DeliveryWidgets: WidgetBundle {
    var body: some Widget {
        DeliveryLiveActivity()
    }
}

#Preview("Lock Screen", as: .content, using: DeliveryAttributes.preview) {
    DeliveryLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.onTheWay
    DeliveryAttributes.ContentState.arriving
}

#Preview("Expanded", as: .dynamicIsland(.expanded), using: DeliveryAttributes.preview) {
    DeliveryLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.onTheWay
}

#Preview("Compact", as: .dynamicIsland(.compact), using: DeliveryAttributes.preview) {
    DeliveryLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.onTheWay
}

#Preview("Minimal", as: .dynamicIsland(.minimal), using: DeliveryAttributes.preview) {
    DeliveryLiveActivity()
} contentStates: {
    DeliveryAttributes.ContentState.onTheWay
}
