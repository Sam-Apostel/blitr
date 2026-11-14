import SwiftUI
import Observation

@Observable
final class Counter {
    var count = 7
    var name = "Observable"
}

extension EnvironmentValues {
    @Entry var accentLabel: String = "Entry default"
    @Entry var badge: Int? = nil
}

struct ContentView: View {
    @State private var model = Counter()
    @Environment(Counter.self) private var shared
    @Environment(\.accentLabel) private var label
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var phase
    @AppStorage("launches") private var launches = 3
    @ScaledMetric private var pad: CGFloat = 16
    @Namespace private var ns
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var shared = shared
        VStack(alignment: .leading, spacing: 10) {
            Text("\(model.name): \(model.count)").font(.title2.bold())
            Text("shared: \(shared.count)")
            Text(label)
            Text("launches \(launches), hSize \(String(describing: hSize)), phase \(String(describing: phase))")
            Text("screen \(Int(UIScreen.main.bounds.width))x\(Int(UIScreen.main.bounds.height)) @\(Int(UIScreen.main.scale))x")
            Text("idiom \(UIDevice.current.userInterfaceIdiom == .phone ? "phone" : "pad")")
            HStack {
                Color(.systemGray6).frame(width: 60, height: 40)
                Color(uiColor: .secondarySystemBackground).frame(width: 60, height: 40)
                Color(uiColor: UIColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)).frame(width: 60, height: 40)
                Color(UIColor.systemTeal.withAlphaComponent(0.5)).frame(width: 60, height: 40)
            }
            Text("Scaled pad \(Int(pad))").padding(pad).background(Color(.systemGray5))
            Text("Uses UIFont").font(Font(UIFont.systemFont(ofSize: 20, weight: .bold)))
            Counter2().frame(height: 60)
        }
        .padding()
    }
}

struct Counter2: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@main
struct MyApp: App {
    @StateObject private var store = Store()
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var shared = Counter()
    var body: some Scene {
        WindowGroup {
            ContentView().environment(shared)
        }
        .environment(\.accentLabel, "Overridden by app")
        .commands { CommandMenu("Tools") { Text("x") } }
    }
}

final class Store: ObservableObject { @Published var x = 1 }
final class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
}
