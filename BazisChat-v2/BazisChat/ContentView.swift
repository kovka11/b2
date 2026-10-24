import SwiftUI

/// Az app által betöltött oldal. Ha változik a cím, csak ezt kell átírni.
let startURL = URL(string: "https://bazischat.eu")!

struct ContentView: View {
    @EnvironmentObject private var appLock: AppLock
    @StateObject private var web = WebState()
    @StateObject private var network = NetworkMonitor()

    var body: some View {
        ZStack {
            // Az állapotsor mögötti szín az oldal témaszínét követi
            (web.themeColor ?? Color(.systemBackground))
                .ignoresSafeArea()

            WebView(state: web)
                .ignoresSafeArea(edges: .bottom)

            if web.progress < 1 && !web.loadFailed {
                VStack {
                    ProgressView(value: web.progress)
                        .progressViewStyle(.linear)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            if web.loadFailed {
                OfflineView(isOnline: network.isOnline) {
                    web.reload()
                }
            }

            if appLock.isLocked {
                LockView {
                    appLock.unlock()
                }
            }
        }
        .onChange(of: network.isOnline) { online in
            if online && web.loadFailed {
                web.reload()
            }
        }
    }
}

struct OfflineView: View {
    let isOnline: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isOnline ? "exclamationmark.triangle" : "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(isOnline ? "Az oldal most nem érhető el" : "Nincs internetkapcsolat")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Ellenőrizd a kapcsolatot, majd próbáld újra.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Újrapróbálás", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                Text("Bázis Chat")
                    .font(.title2.bold())
                Button(action: unlock) {
                    Label("Feloldás", systemImage: "faceid")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
