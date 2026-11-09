// pilote radar … : Le Radar en ligne de commande (comptes suivis, relevés, classement par ratio, boîte à idées).
// Même base et mêmes calculs que l'app ; sorties en JSON comme les autres commandes.
import Foundation

let aideRadar = """
pilote radar : veille de comptes (KRYVA = concurrents, perso = créateurs). Ratio = vues ÷ médiane des AUTRES posts du compte.

  pilote radar [top] [--espace kryva|perso] [--fenetre 24|48|72] [--simulation]
                                       classement des posts de 6 h à 24/48/72 h (72 par défaut) + Top 3 des pistes (ratio > 1)
  pilote radar comptes [--espace …]    comptes suivis
  pilote radar compte-ajoute <espace> <instagram|tiktok> <identifiant> [--nom …] [--notes …]
  pilote radar compte-etat <id> actif|suspendu|retire
  pilote radar importe <fichier.json|.csv> | - [--espace …] [--releve-le 2026-10-29T10:07] [--source nom]
                                       relevé fait à la main, JSON :
                                       {"espace":"kryva","releve_le":"2026-10-29T08:00:00Z","source":"reseaux-lecture-publique","posts":[
                                       {"plateforme":"instagram","compte":"renovo","id":"…","lien":"…","legende":"…","age_h":20 | "date":"…",
                                       "vues":N,"likes":N,"commentaires":N}]}  ou tableau CSV (compte;lien;date;vues;likes;commentaires).
                                       Absent = inconnu ; date sans fuseau = heure de Paris ; date sans heure refusée ; relançable sans doublon.
  pilote radar scan --source <nom> --espace … [--compte <identifiant>] [--pages N] [--max-credits N] [--confirme]
                                       relevé automatique. factice : gratuit. scrapecreators : PAYANT AU CRÉDIT (1 par page, 2 pages par
                                       compte au plus, 30 crédits au plus par relevé) : sans --confirme, rien n'est appelé, le plan est affiché.
  pilote radar scans [n]               journal des relevés
  pilote radar idee <post_id> [--concept "…"]   enregistre le post dans la boîte à idées (source figée, un seul enregistrement par post)
  pilote radar idees [--espace …] [--statut a_ecrire|en_cours|pret]
  pilote radar idee-ecrit <id> '<json>' | -      {"revision":N,"brouillon":"…","statut":"…","concept":"…"} ; refuse si la révision a changé
  pilote radar purge-simulation        efface les relevés factices
"""

private func espaceOption(_ args: [String]) throws -> String? {
    guard let e = option("--espace", args) else { return nil }
    guard RadarVocabulaire.espaces.contains(e) else { throw ErreurRadar.invalide("espace inconnu « \(e) » (kryva ou perso)") }
    return e
}

func radarCommande(_ stock: Stockage, _ args: [String]) throws {
    // args : tout ce qui suit « radar »
    let sous = args.first.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "top"
    let reste = args.first.map { $0.hasPrefix("--") ? args : Array(args.dropFirst()) } ?? []
    switch sous {
    case "top":
        let h = option("--fenetre", reste).flatMap(Double.init) ?? RadarCalcul.fenetreParDefaut.upperBound
        guard [24.0, 48, 72].contains(h) else { throw ErreurRadar.invalide("--fenetre : 24, 48 ou 72") }
        let sim = reste.contains("--simulation")
        let fenetre = RadarCalcul.fenetreParDefaut.lowerBound...h
        let espaces = try espaceOption(reste).map { [$0] } ?? RadarVocabulaire.espaces
        sortir(try espaces.map { try stock.radarClassement(espace: $0, fenetre: fenetre, simulation: sim) })

    case "comptes":
        sortir(try stock.radarComptes(espace: try espaceOption(reste)))

    case "compte-ajoute":
        guard reste.count >= 3 else { throw ErreurRadar.invalide("pilote radar compte-ajoute <espace> <plateforme> <identifiant>") }
        sortir(try stock.radarAjouteCompte(espace: reste[0], plateforme: reste[1], identifiant: reste[2],
                                           nom: option("--nom", reste) ?? "", notes: option("--notes", reste) ?? ""))

    case "compte-etat":
        guard reste.count >= 2 else { throw ErreurRadar.invalide("pilote radar compte-etat <id> actif|suspendu|retire") }
        try stock.radarChangeEtatCompte(reste[0], etat: reste[1])
        sortir(try stock.radarCompte(reste[0]))

    case "importe":
        let arg = reste.first
        let data: Data
        if arg == nil || arg == "-" { data = FileHandle.standardInput.readDataToEndOfFile() }
        else if let a = arg, FileManager.default.fileExists(atPath: a) { data = try Data(contentsOf: URL(fileURLWithPath: a)) }
        else { data = Data(arg!.utf8) }
        let debut = Date()
        let espaceDefaut = try espaceOption(reste)
        let lot: SourceManuelle.Lot
        let premier = String(decoding: data.prefix(64), as: UTF8.self).first { !$0.isWhitespace }
        if premier == "{" || premier == "[" {
            lot = try SourceManuelle.lire(json: data, espaceParDefaut: espaceDefaut)
        } else {
            var releve = debut
            if let t = option("--releve-le", reste) {
                guard let d = RadarDates.lire(t) else { throw ErreurRadar.invalide("--releve-le illisible : \(t) (format 2026-10-29T10:07)") }
                releve = d
            }
            lot = try SourceManuelle.lire(csv: String(decoding: data, as: UTF8.self), espaceParDefaut: espaceDefaut, releveLe: releve, source: option("--source", reste))
        }
        var nouveaux = 0, dejaLa = 0
        var erreurs = lot.erreurs
        for o in lot.observations {
            do { if try stock.radarObserve(o, espace: lot.espace) { nouveaux += 1 } else { dejaLa += 1 } }
            catch { erreurs.append("\(o.compte) \(o.identifiantPost) : \(error)") }
        }
        let comptes = Set(lot.observations.map { "\($0.plateforme):\($0.compte)" }).count
        let scan = try stock.radarNoteScan(espace: lot.espace, source: lot.source, debut: debut, nbComptes: comptes, nbPosts: nouveaux + dejaLa, erreurs: erreurs)
        sortir(ResumeImport(scan: scan, espace: lot.espace, nouveauxReleves: nouveaux, dejaPresents: dejaLa, refuses: erreurs.count, erreurs: erreurs))

    case "scan":
        guard let nom = option("--source", reste), let espace = try espaceOption(reste) else {
            throw ErreurRadar.invalide("pilote radar scan --source <nom> --espace kryva|perso")
        }
        var source = try SourcesRadar.parNom(nom)
        var comptes = try stock.radarComptes(espace: espace, etat: "actif")
        if let seul = option("--compte", reste) {
            let cible = Stockage.radarNormaliseIdentifiant(seul)
            comptes = comptes.filter { $0.identifiant == cible }
            guard !comptes.isEmpty else { throw ErreurRadar.invalide("aucun compte actif « \(seul) » dans l'espace \(espace)") }
        }
        guard !comptes.isEmpty else { throw ErreurRadar.invalide("aucun compte actif dans l'espace \(espace)") }
        if var payant = source as? SourceScrapeCreators {
            if let n = option("--pages", reste).flatMap(Int.init), n >= 1 { payant.pagesMax = min(n, 5) }
            if let n = option("--max-credits", reste).flatMap(Int.init), n >= 1 { payant.plafondCredits = n }
            source = payant
            let cle = CleRadar.lire() != nil
            let max = SourceScrapeCreators.creditsMax(comptes: comptes.count, pagesMax: payant.pagesMax, plafond: payant.plafondCredits)
            guard reste.contains("--confirme") else {
                sortir(PlanScan(source: nom, espace: espace, comptes: comptes.map { "\($0.plateforme):\($0.identifiant)" },
                                pagesParCompteAuPlus: payant.pagesMax, creditsAuPlus: max, cleTrouvee: cle, appelFait: false,
                                suite: cle ? "Rien n'a été appelé. Relancer avec --confirme pour dépenser jusqu'à \(max) crédit(s)."
                                           : SourceScrapeCreators.messageSansCle))
                return
            }
        }
        let debut = Date()
        let lot = try source.releve(comptes: comptes, maintenant: debut)
        var nouveaux = 0
        var erreurs = lot.erreurs
        for o in lot.observations {
            do { if try stock.radarObserve(o, espace: espace) { nouveaux += 1 } }
            catch { erreurs.append("\(o.compte) \(o.identifiantPost) : \(error)") }
        }
        let scan = try stock.radarNoteScan(espace: espace, source: source.nom, debut: debut, nbComptes: comptes.count, nbPosts: nouveaux,
                                           erreurs: erreurs, credits: lot.creditsDepenses)
        sortir(ResumeImport(scan: scan, espace: espace, nouveauxReleves: nouveaux, dejaPresents: lot.observations.count - nouveaux, refuses: erreurs.count,
                            erreurs: erreurs, creditsDepenses: lot.creditsDepenses, creditsRestants: lot.creditsRestants))

    case "scans":
        sortir(try stock.radarScans(limite: reste.first.flatMap(Int.init) ?? 20))

    case "idee":
        guard let postId = reste.first, !postId.hasPrefix("--") else { throw ErreurRadar.invalide("pilote radar idee <post_id>") }
        guard let espace = try stock.radarEspaceDuPost(postId) else { throw ErreurRadar.introuvable("post « \(postId) » inconnu") }
        let sim = reste.contains("--simulation")
        let r = try stock.radarEnregistreIdee(postId: postId, espace: espace, concept: option("--concept", reste) ?? "", simulation: sim)
        sortir(ResultatIdee(nouvelle: r.nouvelle, idee: r.idee))

    case "idees":
        sortir(try stock.radarIdees(espace: try espaceOption(reste), statut: option("--statut", reste)))

    case "idee-ecrit":
        guard let id = reste.first, !id.hasPrefix("--") else { throw ErreurRadar.invalide("pilote radar idee-ecrit <id> '<json>'") }
        guard let champs = try lireJSON(reste.count > 1 ? reste[1] : nil) as? [String: Any] else { throw ErreurRadar.invalide("JSON attendu : un objet") }
        guard let rev = champs["revision"] as? Int else { throw ErreurRadar.invalide("« revision » obligatoire : la révision lue dans l'idée") }
        sortir(try stock.radarEcritIdee(id: id, brouillon: champs["brouillon"] as? String, concept: champs["concept"] as? String,
                                        statut: champs["statut"] as? String, revision: rev))

    case "purge-simulation":
        sortir(["releves_effaces": try stock.radarPurgeSimulation()])

    case "aide":
        print(aideRadar)

    default:
        throw ErreurRadar.invalide("sous-commande inconnue « \(sous) »\n\n\(aideRadar)")
    }
}

struct ResumeImport: Encodable {
    let scan: String
    let espace: String
    let nouveauxReleves: Int
    let dejaPresents: Int
    let refuses: Int
    let erreurs: [String]
    var creditsDepenses: Int? = nil
    var creditsRestants: Int? = nil
}

struct PlanScan: Encodable {
    let source: String
    let espace: String
    let comptes: [String]
    let pagesParCompteAuPlus: Int
    let creditsAuPlus: Int
    let cleTrouvee: Bool
    let appelFait: Bool
    let suite: String
}

struct ResultatIdee: Encodable {
    let nouvelle: Bool
    let idee: RadarIdee
}
