import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }

            Tab("History", systemImage: "clock.fill") {
                HistoryView()
            }

            Tab("Children", systemImage: "person.2.fill") {
                ChildrenView()
            }
        }
    }
}
