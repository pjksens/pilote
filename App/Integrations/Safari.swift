// Safari : LinkedIn s'ouvre là, où Sacha est connecté, quel que soit le navigateur par défaut.
import AppKit

enum Safari {
    /// Ouvre l'adresse dans Safari ; sans Safari, dans le navigateur par défaut.
    static func ouvrir(_ url: URL) {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
    }
}
