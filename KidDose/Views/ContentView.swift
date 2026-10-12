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
        .modifier(MinimizingTabBar())
        // Rounded type across the app: friendlier, and countdown digits read like a timer.
        .fontDesign(.rounded)
    }
}

/// On iOS 26 the Liquid Glass tab bar shrinks while scrolling down, giving content more room.
private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
