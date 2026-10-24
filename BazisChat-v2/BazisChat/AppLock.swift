import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID / kód zár. Háttérbe küldés után az app újra zárolódik.
final class AppLock: ObservableObject {
    /// Ha nem kell zár, állítsd false-ra.
    static let isEnabled = true

    @Published var isLocked = AppLock.isEnabled
    private var isAuthenticating = false

    func lock() {
        guard AppLock.isEnabled else { return }
        isLocked = true
    }

    func unlock() {
        guard AppLock.isEnabled, isLocked, !isAuthenticating else { return }

        let context = LAContext()
        var error: NSError?

        // Ha nincs beállítva kód vagy biometria a telefonon, nem zárjuk ki a felhasználót.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }

        isAuthenticating = true
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Feloldás a Bázis Chat használatához"
        ) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.isAuthenticating = false
                if success {
                    self?.isLocked = false
                }
            }
        }
    }
}
