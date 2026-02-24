import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            ChildrenView()
                .tabItem {
                    Label("Children", systemImage: "person.2.fill")
                }
        }
    }
}
