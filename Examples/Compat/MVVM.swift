import SwiftUI

struct Item: Identifiable {
    let id: Int
    let title: String
    let price: Double
}

final class CartStore: ObservableObject {
    @Published var count = 0
}

final class CatalogViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var query = ""
    @Published var isLoading = true
    @Published private(set) var visible: [Item] = []
    private var cancellables = Set<AnyCancellable>()

    init() {
        Publishers.CombineLatest($items, $query)
            .map { items, query in
                query.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(query) }
            }
            .removeDuplicates { $0.count == $1.count }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.visible = $0 }
            .store(in: &cancellables)
    }

    var total: Double { visible.reduce(0) { $0 + $1.price } }

    func load() {
        items = [Item(id: 1, title: "Espresso", price: 3.2), Item(id: 2, title: "Flat white", price: 4.1),
                 Item(id: 3, title: "Croissant", price: 2.8)]
        isLoading = false
    }
}

struct Row: View {
    @ObservedObject var vm: CatalogViewModel
    let item: Item
    var body: some View {
        HStack {
            Text(item.title).font(.headline)
            Spacer()
            Text(item.price, format: .currency(code: "EUR")).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct Header: View {
    @EnvironmentObject var cart: CartStore
    @EnvironmentObject var vm: CatalogViewModel
    var body: some View {
        HStack {
            Text("Catalog").font(.largeTitle).bold()
            Spacer()
            HStack(spacing: 4) { Image(systemName: "cart"); Text("\(cart.count)") }
                .padding(8)
                .background(Color.blue.opacity(0.15), in: Capsule())
            Text("\(vm.visible.count) items").font(.caption)
        }
    }
}

struct CatalogScreen: View {
    @StateObject private var vm = CatalogViewModel()
    @StateObject private var cart = CartStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header()
            if vm.isLoading {
                Text("Loading...").foregroundStyle(.secondary)
            } else {
                ForEach(vm.visible) { item in
                    Row(vm: vm, item: item)
                }
                Text("Total: \(vm.total, specifier: "%.2f")").font(.footnote.bold())
            }
            Spacer()
        }
        .padding()
        .environmentObject(vm)
        .environmentObject(cart)
        .onAppear { vm.load(); cart.count = 2 }
    }
}

#Preview { CatalogScreen() }
