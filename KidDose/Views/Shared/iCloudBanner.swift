import SwiftUI

/// Shown at the top of the app when the user is not signed into iCloud.
struct iCloudBanner: View {
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed {
            HStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .foregroundStyle(.white)
                Text("Sign in to iCloud to enable sync and sharing with a partner.")
                    .font(.footnote)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation { isDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white.opacity(0.8))
                        .imageScale(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
