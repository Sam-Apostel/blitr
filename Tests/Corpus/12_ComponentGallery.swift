import SwiftUI

// MARK: - Helpers

struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GalleryBadge: View {
    let symbol: String
    let count: Int

    var body: some View {
        Image(systemName: symbol)
            .font(.title)
            .padding(8)
            .overlay(alignment: .topTrailing) {
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color.red, in: Capsule())
                    .offset(x: 6, y: -2)
            }
            .accessibilityLabel("\(symbol), \(count) new")
    }
}

struct GalleryCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Screen

struct ComponentGalleryScreen: View {
    @State private var spin = false

    private let swatches: [(String, Color)] = [
        ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green), ("mint", .mint),
        ("teal", .teal), ("cyan", .cyan), ("blue", .blue), ("indigo", .indigo), ("purple", .purple),
        ("pink", .pink), ("brown", .brown), ("gray", .gray),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    GallerySection(title: "Text styles") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Large Title").font(.largeTitle)
                            Text("Title").font(.title)
                            Text("Title 2").font(.title2)
                            Text("Title 3").font(.title3)
                            Text("Headline").font(.headline)
                            Text("Subheadline").font(.subheadline)
                            Text("Body").font(.body)
                            Text("Callout").font(.callout)
                            Text("Footnote").font(.footnote)
                            Text("Caption").font(.caption)
                            Text("Caption 2").font(.caption2)
                        }
                    }

                    GallerySection(title: "Weights and designs") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ultra Light").fontWeight(.ultraLight)
                            Text("Regular").fontWeight(.regular)
                            Text("Bold").fontWeight(.bold)
                            Text("Black").fontWeight(.black)
                            Text("Rounded design").font(.system(.title3, design: .rounded))
                            Text("Serif design").font(.system(.title3, design: .serif))
                            Text("Monospaced 0123456789").font(.system(.title3, design: .monospaced))
                            Text("Italic and underline").italic().underline()
                            Text("Strikethrough").strikethrough()
                        }
                    }

                    GallerySection(title: "System colors") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(swatches, id: \.0) { item in
                                    VStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(item.1)
                                            .frame(width: 48, height: 48)
                                        Text(item.0).font(.caption2)
                                    }
                                }
                            }
                        }
                    }

                    GallerySection(title: "Shapes") {
                        HStack(spacing: 12) {
                            Circle().stroke(Color.blue, lineWidth: 4).frame(width: 56, height: 56)
                            Rectangle().stroke(Color.green, style: StrokeStyle(lineWidth: 3, dash: [6, 4])).frame(width: 56, height: 56)
                            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange, lineWidth: 5).frame(width: 56, height: 56)
                            Capsule().fill(LinearGradient(colors: [.pink, .purple], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 80, height: 40)
                            Ellipse().fill(RadialGradient(colors: [.yellow, .red], center: .center, startRadius: 2, endRadius: 30))
                                .frame(width: 70, height: 50)
                        }
                    }

                    GallerySection(title: "Shadows and materials") {
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 12).fill(.white)
                                .frame(width: 70, height: 70)
                                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                            RoundedRectangle(cornerRadius: 12).fill(.blue)
                                .frame(width: 70, height: 70)
                                .shadow(color: .blue.opacity(0.5), radius: 14, y: 8)
                        }
                        .padding(.vertical, 8)
                        ZStack {
                            LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            HStack(spacing: 8) {
                                Text("Ultra thin").padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                                Text("Regular").padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                                Text("Thick").padding(10).background(.thickMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .font(.footnote)
                        }
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    GallerySection(title: "Overlay, background, mask, clip") {
                        HStack(spacing: 16) {
                            Text("Hi").font(.title.bold()).padding(16)
                                .background(Color.yellow.opacity(0.4), in: Circle())
                                .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                            LinearGradient(colors: [.blue, .green], startPoint: .top, endPoint: .bottom)
                                .frame(width: 70, height: 70)
                                .mask(Image(systemName: "star.fill").resizable().scaledToFit())
                            Color.indigo.frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            Color.teal.frame(width: 70, height: 70).clipShape(Circle())
                        }
                    }

                    GallerySection(title: "Label styles") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Automatic", systemImage: "star")
                            Label("Title only", systemImage: "star").labelStyle(.titleOnly)
                            Label("Icon only", systemImage: "star").labelStyle(.iconOnly)
                            Label("Title and icon", systemImage: "star").labelStyle(.titleAndIcon)
                        }
                    }

                    GallerySection(title: "Buttons") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button("Automatic") { }
                                Button("Bordered") { }.buttonStyle(.bordered)
                                Button("Prominent") { }.buttonStyle(.borderedProminent)
                            }
                            HStack {
                                Button("Borderless") { }.buttonStyle(.borderless)
                                Button("Plain") { }.buttonStyle(.plain)
                                Button("Delete", role: .destructive) { }.buttonStyle(.bordered)
                            }
                            HStack {
                                Button("Mini") { }.controlSize(.mini)
                                Button("Small") { }.controlSize(.small)
                                Button("Regular") { }.controlSize(.regular)
                                Button("Large") { }.controlSize(.large)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    GallerySection(title: "Badges") {
                        HStack(spacing: 24) {
                            GalleryBadge(symbol: "bell.fill", count: 3)
                            GalleryBadge(symbol: "envelope.fill", count: 12)
                            Text("NEW").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.green, in: Capsule()).foregroundStyle(.white)
                        }
                    }

                    GallerySection(title: "Transforms and effects") {
                        HStack(spacing: 24) {
                            Image(systemName: "airplane").font(.largeTitle).rotationEffect(.degrees(-45))
                            Image(systemName: "airplane").font(.largeTitle).scaleEffect(1.6)
                            Image(systemName: "airplane").font(.largeTitle).opacity(0.3)
                            Image(systemName: "airplane").font(.largeTitle).blur(radius: 3)
                            Image(systemName: "arrow.triangle.2.circlepath").font(.largeTitle)
                                .rotationEffect(.degrees(spin ? 360 : 0))
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.8)) { spin.toggle() }
                                }
                        }
                        .padding(.vertical, 16)
                        .modifier(GalleryCardModifier())
                    }
                }
                .padding(16)
            }
            .navigationTitle("Gallery")
        }
    }
}

#Preview {
    ComponentGalleryScreen()
}

#Preview("Dark") {
    ComponentGalleryScreen().preferredColorScheme(.dark)
}
