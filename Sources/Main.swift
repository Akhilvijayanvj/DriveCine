import SwiftUI
import AppKit

@main
struct DriveCineApp: App {
    init() {
        // Configure dark appearance by default for media editor workflow
        NSApp?.appearance = NSAppearance(named: .darkAqua)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 920, minHeight: 620)
                .background(ProTheme.bgDarkest)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Transfer...") {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenNewTransferSheet"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
