import SwiftUI

@Observable final class Store {
    var count = 3
    @ObservationIgnored var cache: [Int] = []
}
struct Row: View {
    @Bindable var store: Store
    var body: some View { Stepper("Count \(store.count)", value: $store.count) }
}
#Preview {
    @Previewable @State var store = Store()
    VStack { Text("n = \(store.count)"); Row(store: store) }.padding()
        .environment(store)
}
