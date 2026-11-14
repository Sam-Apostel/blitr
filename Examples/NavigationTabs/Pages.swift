import SwiftUI

#Preview {
    TabView {
        Color.indigo.overlay(Text("Page 1").font(.largeTitle).foregroundStyle(.white))
        Color.teal.overlay(Text("Page 2"))
        Color.orange.overlay(Text("Page 3"))
    }
    .tabViewStyle(.page)
    .ignoresSafeArea()
}
