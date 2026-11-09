// Alerte « capteur ou veille arrêtés » (04/11, GO de PILOTE : seulement dans `pilote controle` et la notification de 7 h).
//
// Le capteur (launchd, 60 s) écrit entrants-etat.json à chaque passage ; la veille (tâche pilote-veille, toutes les 15 min,
// 7 h-23 h) réécrit veille-repere.json à chaque passage, même sans rien à dire. On lit la DATE DE DERNIÈRE ÉCRITURE de
// ces deux fichiers. Alerte si plus de 2 h de la plage 7 h-23 h se sont écoulées depuis : la nuit ne compte pas
// (le Mac dort, la veille ne tourne pas), donc pas de fausse alerte à 7 h.

// 05/11 (chantier C, T15 T33 T34 T39) : seuil du capteur 2 h → 30 min ; le Facteur (facteur.json) et le service des inscrits
// (inscrits-battement.json, réécrit chaque minute) sont surveillés pareil ; disque sous 10 Go ; WhatsApp sans message reçu
// depuis plus de 24 h ouvrées. La veille garde 2 h (cycle de 15 min, tâche Claude : s'arrête aussi si la limite d'usage
// hebdomadaire est atteinte). Les alertes sont aussi affichées en rouge dans l'app (Aujourd'hui).

import Foundation

enum AlerteArret {
    static let seuil: TimeInterval = 2 * 3600            // la veille
    static let seuilCourt: TimeInterval = 30 * 60        // capteur, Facteur, service des inscrits
    static let seuilDisque: Int64 = 10_000_000_000       // 10 Go
    static let seuilWhatsApp: TimeInterval = 24 * 3600   // heures ouvrées seulement
    static let heureDebut = 7
    static let heureFin = 23

    /// Secondes de la plage 7 h-23 h comprises entre `de` et `a` (heure locale). 0 si `a` ≤ `de`.
    static func secondesActives(de: Date, a: Date, calendrier: Calendar = .current) -> TimeInterval {
        guard a > de else { return 0 }
        let debut = max(de, a.addingTimeInterval(-30 * 86400))      // au-delà d'un mois, le chiffre exact n'apporte rien
        var jour = calendrier.startOfDay(for: debut)
        var total: TimeInterval = 0
        while jour <= a {
            if let ouvre = calendrier.date(bySettingHour: heureDebut, minute: 0, second: 0, of: jour),
               let ferme = calendrier.date(bySettingHour: heureFin, minute: 0, second: 0, of: jour) {
                total += max(0, min(a, ferme).timeIntervalSince(max(debut, ouvre)))
            }
            guard let suivant = calendrier.date(byAdding: .day, value: 1, to: jour) else { break }
            jour = suivant
        }
        return total
    }

    /// Les lignes d'alerte : une par composant arrêté. `nil` = fichier absent (jamais vu).
    static func lignes(capteur: Date?, veille: Date?, maintenant: Date, calendrier: Calendar = .current) -> [String] {
        func une(_ nom: String, _ derniere: Date?, _ limite: TimeInterval = seuilCourt) -> String? {
            guard let d = derniere else { return "\(nom) : aucune trace (fichier d'état absent)" }
            guard secondesActives(de: d, a: maintenant, calendrier: calendrier) > limite else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.timeZone = calendrier.timeZone
            f.dateFormat = "dd/MM 'à' HH:mm"
            return "\(nom) : rien écrit depuis le \(f.string(from: d)) (plus de \(limite >= 3600 ? "\(Int(limite / 3600)) h" : "\(Int(limite / 60)) min") dans la plage 7 h-23 h)"
        }
        return [une("Capteur d'entrants (launchd, 60 s)", capteur), une("Veille de PILOTE (tâche pilote-veille, 15 min)", veille, seuil)]
            .compactMap { $0 }
    }

    /// Secondes comprises entre `de` et `a` hors samedi et dimanche (heure locale).
    static func secondesOuvrees(de: Date, a: Date, calendrier: Calendar = .current) -> TimeInterval {
        guard a > de else { return 0 }
        var jour = calendrier.startOfDay(for: max(de, a.addingTimeInterval(-30 * 86400)))
        var total: TimeInterval = 0
        while jour <= a {
            guard let suivant = calendrier.date(byAdding: .day, value: 1, to: jour) else { break }
            let w = calendrier.component(.weekday, from: jour)          // 1 = dimanche, 7 = samedi
            if w != 1 && w != 7 { total += max(0, min(a, suivant).timeIntervalSince(max(de, jour))) }
            jour = suivant
        }
        return total
    }

    /// « il y a 5 h 20 » / « il y a 12 min » / « il y a 2 j 3 h ».
    static func ecoule(_ s: TimeInterval) -> String {
        let m = Int(max(0, s) / 60)
        if m < 60 { return "\(m) min" }
        if m < 48 * 60 { return "\(m / 60) h \(String(format: "%02d", m % 60))" }
        return "\(m / 1440) j \((m % 1440) / 60) h"
    }

    /// Les autres témoins : Facteur, service des inscrits (battement + statut de connexion), disque, WhatsApp.
    /// `inscritsStatut` / `inscritsDepuis` : dernier statut du canal Supabase et depuis quand il dure.
    static func lignesAnnexes(facteur: Date?, inscrits: Date?, inscritsStatut: String?, inscritsDepuis: Date?,
                              disqueLibre: Int64?, whatsapp: Date?, maintenant: Date, calendrier: Calendar = .current) -> [String] {
        var r: [String] = []
        func f(_ d: Date) -> String {
            let fm = DateFormatter(); fm.locale = Locale(identifier: "fr_FR"); fm.timeZone = calendrier.timeZone; fm.dateFormat = "dd/MM 'à' HH:mm"
            return fm.string(from: d)
        }
        r += lignes(nomsEtDates: [("Facteur (facteur.json, au moins toutes les 3 min)", facteur),
                                  ("Service des inscrits (inscrits-battement.json, chaque minute)", inscrits)],
                    maintenant: maintenant, calendrier: calendrier)
        if let st = inscritsStatut, st != "SUBSCRIBED", let dep = inscritsDepuis,
           secondesActives(de: dep, a: maintenant, calendrier: calendrier) > seuilCourt {
            r.append("Service des inscrits : connexion Supabase en échec (\(st)) depuis le \(f(dep)) : les inscriptions arrivent en retard")
        }
        if let d = disqueLibre, d < seuilDisque {
            r.append("Disque : \(String(format: "%.1f", Double(d) / 1e9).replacingOccurrences(of: ".", with: ",")) Go libres sur /System/Volumes/Data (seuil 10 Go)")
        }
        if let w = whatsapp, secondesOuvrees(de: w, a: maintenant, calendrier: calendrier) > seuilWhatsApp {
            r.append("WhatsApp : dernier message reçu il y a \(ecoule(maintenant.timeIntervalSince(w))) (plus de 24 h ouvrées) : WhatsApp Mac est peut-être fermé")
        }
        return r
    }

    private static func lignes(nomsEtDates: [(String, Date?)], maintenant: Date, calendrier: Calendar) -> [String] {
        nomsEtDates.compactMap { nom, d in
            guard let d else { return "\(nom) : aucune trace (fichier d'état absent)" }
            guard secondesActives(de: d, a: maintenant, calendrier: calendrier) > seuilCourt else { return nil }
            let fm = DateFormatter(); fm.locale = Locale(identifier: "fr_FR"); fm.timeZone = calendrier.timeZone; fm.dateFormat = "dd/MM 'à' HH:mm"
            return "\(nom) : rien écrit depuis le \(fm.string(from: d)) (plus de 30 min dans la plage 7 h-23 h)"
        }
    }

    /// Ligne d'information pour `pilote controle` : le dernier message WhatsApp reçu.
    static func ligneWhatsApp(_ w: Date?, maintenant: Date = Date()) -> String {
        guard let w else { return "WhatsApp : dernier message reçu illisible (pas encore relevé par le capteur)" }
        return "WhatsApp : dernier message reçu il y a \(ecoule(maintenant.timeIntervalSince(w)))"
    }

    /// Espace libre de /System/Volumes/Data (octets), ou nil.
    static func disqueLibre(chemin: String = "/System/Volumes/Data") -> Int64? {
        var st = statfs()
        guard statfs(chemin, &st) == 0 else { return nil }
        return Int64(st.f_bavail) * Int64(st.f_bsize)
    }

    /// Date du dernier message WhatsApp REÇU, relevée par le capteur dans entrants-etat.json (clé whatsappRecu). Le capteur seul a
    /// l'accès au disque : ouvrir ChatStorage.sqlite depuis l'app ou `pilote controle` peut bloquer sur une demande d'autorisation macOS.
    static func dernierWhatsApp(dossier: URL = TachesTerminees.dossierParDefaut) -> Date? {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent("entrants-etat.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = o["whatsappRecu"] as? String else { return nil }
        return TachesTerminees.iso.date(from: t)
    }

    /// Statut de connexion et sa date, lus dans inscrits-battement.json.
    static func lireBattement(dossier: URL) -> (statut: String?, depuis: Date?) {
        guard let d = try? Data(contentsOf: dossier.appendingPathComponent("inscrits-battement.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, nil) }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        let dep = (o["statut_depuis"] as? String).flatMap { iso.date(from: $0) ?? iso2.date(from: $0) }
        return (o["statut"] as? String, dep)
    }

    /// Heure du dernier réveil complet du Mac aujourd'hui (pmset -g log, ~10 s : à appeler hors du fil principal). nil si introuvable.
    static func reveilDuJour(maintenant: Date = Date()) -> Date? {
        if Demo.actif { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "/usr/bin/pmset -g log | /usr/bin/grep -E ' Wake  ' | /usr/bin/tail -3"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let sortie = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        let fm = DateFormatter(); fm.locale = Locale(identifier: "en_US_POSIX"); fm.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let dates = sortie.split(separator: "\n").compactMap { fm.date(from: String($0.prefix(25))) }
        guard let d = dates.last, Calendar.current.isDate(d, inSameDayAs: maintenant) else { return nil }
        return d
    }

    /// Lit la date de dernière écriture des deux fichiers d'état (PILOTE_ENTRANTS_DIR pour les essais, comme le capteur).
    static func lire(maintenant: Date = Date(), dossier: URL = TachesTerminees.dossierParDefaut, annexes: Bool = true) -> [String] {
        func ecrit(_ nom: String) -> Date? {
            let f = dossier.appendingPathComponent(nom)
            return (try? FileManager.default.attributesOfItem(atPath: f.path))?[.modificationDate] as? Date
        }
        let base = lignes(capteur: ecrit("entrants-etat.json"), veille: ecrit("veille-repere.json"), maintenant: maintenant)
        guard annexes else { return base }
        let b = lireBattement(dossier: dossier)
        return base
            + lignesAnnexes(facteur: ecrit("facteur.json"), inscrits: ecrit("inscrits-battement.json"), inscritsStatut: b.statut, inscritsDepuis: b.depuis,
                            disqueLibre: disqueLibre(), whatsapp: dernierWhatsApp(dossier: dossier), maintenant: maintenant)
    }
}
