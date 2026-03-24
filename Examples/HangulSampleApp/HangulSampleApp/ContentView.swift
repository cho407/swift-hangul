import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CoreDemoView()
                .tabItem {
                    Label("Core", systemImage: "character.book.closed")
                }

            SearchDemoView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
        }
    }
}

#Preview {
    ContentView()
}
