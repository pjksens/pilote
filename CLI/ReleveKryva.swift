// Relevé « envoyé depuis kryva.fr » : lit l'Envelope Index de Mail.app (lecture seule, métadonnées seulement) et note
// les mails des boîtes d'ENVOI dont l'expéditeur est une adresse kryva.fr. Écrit `envois-kryva.json` (voir Shared/EnvoisKryva.swift).
import Foundation
import SQLite3

enum ReleveKryva {
    /// Le relevé est refait au plus toutes les 5 minutes (le capteur passe chaque minute).
    static let pause: Double = 300
    static let jours = 3

    /// Mails des boîtes d'envoi dont l'expéditeur est kryva.fr, sur les `jours` derniers jours.
    static func lire(chemin: String, depuis: Date) throws -> [EnvoiKryva] {
        let b = try EntLecture(chemin)
        let colonnes = Set(try b.lignes("PRAGMA table_info(messages)").map { $0.entS("name") })
        for requise in ["ROWID", "sender", "subject", "mailbox"] where !colonnes.contains(requise) {
            throw EntErreur(description: "schéma Mail inconnu, colonne absente : \(requise)")
        }
        let dateCol = colonnes.contains("date_sent") ? "CASE WHEN m.date_sent > 0 THEN m.date_sent ELSE m.date_received END" : "m.date_received"
        var filtre = "\(dateCol) >= ?"
        if colonnes.contains("deleted") { filtre += " AND m.deleted = 0" }
        let lignes = try b.lignes("""
            SELECT \(dateCol) AS d, a.address AS exp, s.subject AS subj, m.ROWID AS rid
            FROM messages m
            LEFT JOIN addresses a ON a.ROWID = m.sender
            LEFT JOIN subjects s ON s.ROWID = m.subject
            JOIN mailboxes mb ON mb.ROWID = m.mailbox AND (lower(mb.url) LIKE '%/sent%' OR lower(mb.url) LIKE '%envoy%')
            WHERE \(filtre) ORDER BY m.ROWID DESC LIMIT 500
            """, [Int(depuis.timeIntervalSince1970)])
        var sortie: [EnvoiKryva] = []
        for r in lignes {
            let exp = r.entS("exp").lowercased()
            guard EnvoisKryva.estInterdit(exp) else { continue }
            var secondes = r.entD("d")
            if secondes < 1_000_000_000 { secondes += 978307200 }
            let rid = r.entI("rid")
            sortie.append(EnvoiKryva(ts: secondes, expediteur: exp, destinataire: destinataire(b, rid), objet: r.entS("subj")))
        }
        return sortie
    }

    /// Premier destinataire, au mieux : le nom des colonnes de la table « recipients » n'a pas pu être vérifié ici (accès à ~/Library/Mail
    /// refusé à la session de code), donc on les lit dans le schéma ; vide si elles diffèrent. Le contrôle écrit alors « destinataire inconnu ».
    private static func destinataire(_ b: EntLecture, _ rowid: Int) -> String {
        guard let cols = try? b.lignes("PRAGMA table_info(recipients)").map({ $0.entS("name") }), !cols.isEmpty else { return "" }
        let msg = ["message_id", "message"].first(where: cols.contains)
        let adr = ["address_id", "address"].first(where: cols.contains)
        guard let msg, let adr else { return "" }
        let tri = cols.contains("position") ? "r.position" : "r.ROWID"
        let l = try? b.lignes("""
            SELECT a.address AS addr FROM recipients r JOIN addresses a ON a.ROWID = r.\(adr)
            WHERE r.\(msg) = ? ORDER BY \(tri) LIMIT 1
            """, [rowid])
        return l?.first?.entS("addr").lowercased() ?? ""
    }

    /// Une passe : à appeler depuis le capteur. Renvoie le nombre d'envois kryva.fr des 48 dernières heures (nil = pas relevé).
    @discardableResult
    static func passe(maintenant: Date = Date(), fichier: URL = EnvoisKryva.fichier, chemin: String? = EntSource.cheminMail()) -> Int? {
        guard Reglages.courants.mail == true, !(Reglages.courants.domainesInterdits ?? []).isEmpty else { return nil }
        if let e = EnvoisKryva.lire(fichier), maintenant.timeIntervalSince1970 - e.verifieLe < pause { return nil }
        guard let chemin else { return nil }
        let depuis = maintenant.addingTimeInterval(-Double(jours) * 86400)
        guard let envois = try? lire(chemin: chemin, depuis: depuis) else { return nil }   // échec : le fichier garde sa date, le contrôle dira « pas à jour »
        EnvoisKryva.ecrire(EtatEnvoisKryva(verifieLe: maintenant.timeIntervalSince1970, envois: envois), fichier)
        return EnvoisKryva.lignes(EtatEnvoisKryva(verifieLe: maintenant.timeIntervalSince1970, envois: envois), maintenant: maintenant).count
    }
}
