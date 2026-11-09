// Notifications (03/11, Sacha : « chaque décision à prendre s'affiche dans Pilote obligatoirement… avec une notif qui me
// dit qu'une décision est à prendre ») : une notification par nouvelle décision (❓ ou question d'une session), groupées
// au-delà de deux d'un coup ; le nombre en attente sur l'icône du Dock. Un clic ouvre Pilote sur Aujourd'hui.
import AppKit
import UserNotifications

enum Notifs {
    struct Annonce: Hashable {
        let cle: String
        let titre: String
        let corps: String
    }

    private static let cleVues = "notifs.vues"
    private static var delegue: Delegue?

    static func demarrer(surClic: @escaping () -> Void) {
        if Demo.actif { return }
        guard delegue == nil else { return }
        let d = Delegue(surClic: surClic)
        delegue = d
        let c = UNUserNotificationCenter.current()
        c.delegate = d
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Notifie les décisions pas encore annoncées. La toute première fois, une seule notification pour le stock.
    static func signaler(_ annonces: [Annonce]) {
        if Demo.actif { return }
        NSApp.dockTile.badgeLabel = annonces.isEmpty ? nil : "\(annonces.count)"
        let defauts = UserDefaults.standard
        let premiere = defauts.array(forKey: cleVues) == nil
        var vues = defauts.stringArray(forKey: cleVues) ?? []
        let nouvelles = annonces.filter { !vues.contains($0.cle) }
        guard !nouvelles.isEmpty || premiere else { return }
        vues = Array((vues + nouvelles.map(\.cle)).suffix(300))
        defauts.set(vues, forKey: cleVues)
        if premiere {
            if !nouvelles.isEmpty {
                envoyer(titre: "Pilote", corps: nouvelles.count == 1 ? "1 décision à prendre" : "\(nouvelles.count) décisions à prendre",
                        id: "stock")
            }
        } else if nouvelles.count <= 2 {
            for a in nouvelles { envoyer(titre: a.titre, corps: a.corps, id: a.cle) }
        } else {
            envoyer(titre: "\(nouvelles.count) décisions à prendre",
                    corps: nouvelles.prefix(3).map(\.corps).joined(separator: " · "), id: "lot-\(Date().timeIntervalSince1970)")
        }
    }

    /// Une notification une seule fois par clé (le contrôle « Demain prêt ? » du soir), sans toucher au nombre du Dock.
    static func prevenir(cle: String, titre: String, corps: String) {
        if Demo.actif { return }
        let defauts = UserDefaults.standard
        let faites = defauts.stringArray(forKey: "notifs.demain") ?? []
        guard !faites.contains(cle) else { return }
        defauts.set(Array((faites + [cle]).suffix(30)), forKey: "notifs.demain")
        envoyer(titre: titre, corps: corps, id: cle)
    }

    private static func envoyer(titre: String, corps: String, id: String) {
        let c = UNMutableNotificationContent()
        c.title = titre
        c.body = corps
        c.sound = .default
        c.threadIdentifier = "decisions"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    private final class Delegue: NSObject, UNUserNotificationCenterDelegate {
        let surClic: () -> Void
        init(surClic: @escaping () -> Void) { self.surClic = surClic }

        // Pilote au premier plan : la bannière s'affiche quand même.
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list, .sound])
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                    withCompletionHandler completionHandler: @escaping () -> Void) {
            DispatchQueue.main.async { [surClic] in
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
                surClic()
            }
            completionHandler()
        }
    }
}
