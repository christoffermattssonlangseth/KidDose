import Foundation

/// Widget-extension twin of the app's `LockScreenDoseRouter`.
///
/// `GiveDoseButtonIntent` is a `LiveActivityIntent`, so iOS performs it in the app's process,
/// which has the real implementation. This copy only exists so the shared intent compiles here.
enum LockScreenDoseRouter {
    static func handleTap(childID: String, medication: String) async {}
}
