// Contrôle « envoyé depuis kryva.fr » (04/11, PILOTE, piste 2 de la règle « jamais de mail depuis kryva.fr »).
// Le capteur (qui a l'accès disque à Mail) relève dans les boîtes d'envoi de Mail.app les mails partis d'une adresse
// kryva.fr et les écrit dans `envois-kryva.json`. Le contrôle du matin (`pilote controle`, notification de 7 h) les affiche.
// Métadonnées seulement (date, destinataire, objet) : jamais le corps. On ne cherche pas QUI a cliqué : on signale.
import Foundation

struct EnvoiKryva: Codable, Equatable {
    var ts: Double              // secondes depuis 1970
    var expediteur: String      // adresse kryva.fr d'où le mail est parti
    var destinataire: String    // vide si inconnu
    var objet: String
}

struct EtatEnvoisKryva: Codable, Equatable {
    var verifieLe: Double       // dernière vérification réussie (secondes depuis 1970)
    var envois: [EnvoiKryva]
}

enum EnvoisKryva {
    static var fichier: URL { Base.dossier.appendingPathComponent("envois-kryva.json") }

    /// Une adresse d'un domaine interdit (reglages.json, `domaines_interdits`) ou d'un de ses sous-domaines : avec « exemple.fr »,
    /// « x@exemple.fr » et « x@mail.exemple.fr » oui ; « x@exemple.fr.evil.com » et « x@pasexemple.fr » non. Aucun domaine réglé : non.
    static func estInterdit(_ adresse: String, domaines: [String] = Reglages.courants.domainesInterdits ?? []) -> Bool {
        let a = adresse.trimmingCharacters(in: .whitespaces).lowercased()
        guard let arobase = a.lastIndex(of: "@") else { return false }
        let domaine = a[a.index(after: arobase)...]
        return domaines.contains { d in
            let d = d.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " @"))
            return !d.isEmpty && (domaine == d || domaine.hasSuffix("." + d))
        }
    }

    static func lire(_ f: URL = fichier) -> EtatEnvoisKryva? {
        guard let d = try? Data(contentsOf: f) else { return nil }
        return try? JSONDecoder().decode(EtatEnvoisKryva.self, from: d)
    }

    static func ecrire(_ e: EtatEnvoisKryva, _ f: URL = fichier) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(e) { try? d.write(to: f, options: .atomic) }
    }

    /// Lignes du contrôle : mails partis d'une adresse kryva.fr dans les dernières `heures` heures (48 par défaut : hier et aujourd'hui).
    static func lignes(_ etat: EtatEnvoisKryva?, maintenant: Date = Date(), heures: Double = 48) -> [Controle.Ligne] {
        guard let etat else { return [] }
        let limite = maintenant.timeIntervalSince1970 - heures * 3600
        return etat.envois.filter { $0.ts >= limite && estInterdit($0.expediteur) }.sorted { $0.ts > $1.ts }.map { e in
            let jour = Dates.jour.string(from: Date(timeIntervalSince1970: e.ts))
            let a = e.destinataire.isEmpty ? "destinataire inconnu" : e.destinataire
            return Controle.Ligne(contactId: "", nom: a, espace: "kryva",
                                  detail: "envoyé le \(jour) depuis \(e.expediteur) : « \(e.objet.prefix(60)) » (règle : jamais depuis un domaine interdit, Gmail perso seulement)")
        }
    }

    /// La vérification n'a pas tourné depuis longtemps (capteur arrêté, Mail illisible) : le contrôle le dit au lieu de se taire.
    static func perimee(_ etat: EtatEnvoisKryva?, maintenant: Date = Date(), heures: Double = 6) -> Bool {
        guard let etat else { return true }
        return maintenant.timeIntervalSince1970 - etat.verifieLe > heures * 3600
    }
}
