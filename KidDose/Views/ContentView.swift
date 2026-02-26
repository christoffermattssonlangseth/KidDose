import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "pills.fill")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            ChildrenView()
                .tabItem {
                    Label("Settings", systemImage: "figure.2.and.child.holdinghands")
                }
        }
    }
}
