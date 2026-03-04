import SwiftUI

struct RootView: View {
    @Environment(WatchSessionManager.self) private var sessionManager

    var body: some View {
        NavigationStack {
            Group {
                if sessionManager.snapshots.isEmpty {
                    emptyState
                } else {
                    List(sessionManager.snapshots) { snapshot in
                        NavigationLink(destination: ChildDetailView(snapshot: snapshot)) {
                            ChildRow(snapshot: snapshot)
                        }
                    }
                }
            }
            .navigationTitle("KidDose")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open KidDose on iPhone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Child Row

private struct ChildRow: View {
    let snapshot: WidgetChildSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: snapshot.colorHex) ?? .accentColor)
                .frame(width: 10, height: 10)

            Text(snapshot.name)
                .font(.body)

            Spacer()

            doseBadge
        }
    }

    @ViewBuilder
    private var doseBadge: some View {
        let soonest = soonestDoseDate(snapshot: snapshot)
        if soonest == nil {
            Text("Ready")
                .font(.caption2.bold())
                .foregroundStyle(.green)
        } else if let date = soonest {
            Text(countdownString(until: date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Returns the soonest future next-dose date among the two medications,
    /// or nil if at least one is ready now.
    private func soonestDoseDate(snapshot: WidgetChildSnapshot) -> Date? {
        let dates = [snapshot.ibuprofenNextDate, snapshot.paracetamolNextDate]
            .compactMap { $0 }
            .filter { $0 > .now }

        // If any medication is ready (nil next date + has doses), show "Ready".
        let ibuprofenReady = snapshot.ibuprofenHasDoses && (snapshot.ibuprofenNextDate == nil || snapshot.ibuprofenNextDate! <= .now)
        let paracetamolReady = snapshot.paracetamolHasDoses && (snapshot.paracetamolNextDate == nil || snapshot.paracetamolNextDate! <= .now)
        if ibuprofenReady || paracetamolReady { return nil }

        return dates.min()
    }

    private func countdownString(until date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return "Ready" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Color from hex

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
