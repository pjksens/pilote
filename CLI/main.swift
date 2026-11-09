// pilote : l'outil en ligne de commande de Pilote (pour Claude et les scripts). Sorties en JSON.
import Foundation

let aide = """
pilote : contacts et fil de Pilote (même base que l'app)

  pilote jour                         actions dues aujourd'hui + messages à envoyer
  pilote jour --pour sacha|ventes|freelance|pilote   sacha : ses gestes ; un agent : sa liste du jour (dus, sans date, consigne)
  pilote suivi-agents [--jour AAAA-MM-JJ]            par agent : fiches de la liste du jour traitées / restantes
  pilote contacts [--espace kryva|freelance|autre] [--etape …] [--type …]
  pilote cherche <texte>              nom, entreprise, ville, e-mail, téléphone, LinkedIn
  pilote fiche <id>                   le contact et tout son fil
  pilote enregistre '<json>' | -      crée ou met à jour (par id, sinon source + source_ref)
  pilote evenement <id> '<json>' | -  ajoute au fil : canal, sens, type, texte, statut, par, le
  pilote evenement-maj <id_ev> '<json>' corrige un événement : texte, objet, reponse_a, canal, type, le
  pilote envoye <id_evenement> [--malgre-condition]   un message préparé a été envoyé par \(Moi.tiers) (refusé si sa condition
                                      n'est pas cochée, sauf --malgre-condition : déjà parti, le fil le note)
  pilote condition-remplie <id_evenement> [--par <qui>]   la condition d'un message préparé est vérifiée : l'envoi se débloque
  pilote a-envoyer [--mail]           les messages « prepare » : id court, contact, canal, objet, début du texte, condition et
                                      son état, jour, envoyable (pilote envoie l'accepterait) et sinon pourquoi
  pilote envoie <id> [--essai] [--empreinte <e>]   envoie CE mail préparé depuis le Gmail de \(Moi.tiers), comme le bouton
                                      « Envoyer depuis Gmail » de l'app, puis le marque envoyé (seulement sur « envoie » de \(Moi.tiers)).
                                      --essai : montre exactement ce qui partirait (de, à, objet, fil, texte, empreinte), rien
                                      envoyé ni écrit. --empreinte : celle de l'essai montré ; si le mail a changé, refus.
                                      Refus (rien ne part) : statut ≠ prepare ou déjà envoyé, canal ≠ mail, objet vide, condition
                                      pas cochée, « ne plus contacter », kryva.fr (expéditeur ou destinataire), Gmail non connecté.
                                      Essais : PILOTE_BASE=<copie> PILOTE_ENVOI_FAUX=<fichier> (rien ne part, voir Shared/EnvoiPilote.swift)
  pilote file-envoi [--candidats | --passe | --arreter]   la file d'envoi des mails validés (bouton « Envoyer les mails
                                      validés » de l'app : un mail toutes les 5 min, depuis le Gmail de \(Moi.tiers), chemin de
                                      pilote envoie). Sans option : la file du jour. --candidats : ce que le bouton propose.
                                      --passe : l'agent launchd (toutes les 30 s) envoie ce qui est dû. --arreter : annule ce
                                      qui attend. --mettre <id>… : copie de la base seulement (essais, voir Shared/FileEnvoi.swift)
  pilote publication [liste]           publication programmée (YouTube @sachaprljk @kryva_app, Instagram @sachaprljk @kryva.fr,
                                      TikTok perso et KRYVA en brouillon dans la boîte TikTok, publié par \(Moi.tiers) depuis l'app) :
                                      comptes et publications avec leur statut. Voir Shared/Publication.swift.
  pilote publication programmer --compte yt-perso[,ig-kryva,tt-perso] --fichier VIDEO --le "AAAA-MM-JJ HH:MM" [--titre T]
                                      [--texte T | --texte-fichier F] [--ia] [--par NOM]   PROPOSE (à valider) : rien ne part
  pilote publication valider <id> --empreinte E   après le « oui » explicite de \(Moi.tiers) au bloc exact (programmer le rend)
  pilote publication annuler <id> | comptes | acces | connecter <compte>   (connecter : YouTube = page Google ;
                                      Instagram = jeton copié dans le tableau de bord Meta, lu dans le presse-papiers ;
                                      TikTok = page TikTok, avec le compte connecté dans le navigateur)
  pilote publication client-tiktok --cle <Client key> [--port N]   range le client TikTok (secret lu dans le presse-papiers)
  pilote publication --passe          l'agent launchd io.github.pjksens.pilote.publication (toutes les minutes)
  pilote publication verifier   lecture seule : chaque jeton tombe-t-il sur le bon compte ?
  pilote publication essai-youtube --fichier V --accord-sacha [--garder] | essai-instagram --compte ig-… --fichier V --accord-sacha
                    | essai-tiktok --compte tt-… --fichier V --accord-sacha   essais d'envoi (accord de \(Moi.tiers) exigé)
  pilote gmail-acces [--verifier]     sur le Mac, une fois : autorise l'outil à lire le mot de passe Gmail rangé par l'app
                                      (fenêtre du trousseau : « Toujours autoriser ») ; --verifier : connexion à Gmail, aucun mail
  pilote echec <id_evenement>
  pilote import <fichier.json> [--mettre-a-jour]
                                      [{"contact": {…}, "evenements": [{…}]}], relançable sans doublon ;
                                      un contact déjà présent n'est pas modifié, sauf avec --mettre-a-jour
  pilote videos [--du AAAA-MM-JJ --au AAAA-MM-JJ] [--reserve]
                                      les vidéos de la semaine (lun.-ven.) et le mot affiché à \(Moi.tiers)
  pilote video '<json>' | -           crée ou modifie une vidéo (par id, sinon jour + compte) :
                                      jour, compte kryva|perso, sujet, statut, heure, prompteur, fiche, notes
  pilote carte [--espace …]           tous les projets : dossier, dépôt, site, documents clés
  pilote projet '<json>' | -          crée ou modifie un projet de la carte (id, espace, nom, dossier…)
  pilote ou-est <texte>               cherche partout : projets, journal, contacts, fichiers (Spotlight)
  pilote agents                       ce que font les sessions Claude Code en ce moment
  pilote pyramide                     l'équipe en arbre : PILOTE, sessions de domaine, chantiers (EQUIPE.md + sessions vivantes)
\(CarteDomaineCommande.aide)
  pilote journal [n] [--projet id]    les dernières entrées du journal des agents
  pilote note-journal '<json>' | -    note un livrable : texte, fichiers [chemins], type (livrable|note), dossier
  pilote journal-crochet              (crochet « Stop » de Claude Code : note la fin de chaque réponse)
  pilote relais-fin [--essai]        (crochet « Stop » : au-delà de 130 k, passation puis remise à zéro ; --essai : décision et motif, rien d'écrit ; trace : relais.log)
  pilote relances [--ajoute]         relances après remise à zéro (--ajoute : la session note la sienne et lit l'heure du fireAt)
  pilote reprise                     rend à la session qui l'appelle sa passation et ses derniers tours
  pilote relais-depart               (crochet « SessionStart » : rend la passation après une remise à zéro)
  pilote entrants --suivre | --capter | --etat | --lire | --installer   capteur de messages entrants (lecture seule ; aide : pilote entrants)
  pilote import-carte <fichier.json>  [{projet}, …], relançable (met à jour par id)
  pilote controle [--json]            le contrôle du matin : dus sans texte, envoyés encore dus, étapes sans fait, dates sans source, sans date, mails partis d'un domaine interdit, capteur ou veille arrêtés (signale, ne corrige rien)
  pilote repare-suites [--appliquer]  fiches dont un envoi du jour n'a pas posé la suite J+5 (sans --appliquer : liste seulement ; sauvegarder d'abord)
  pilote sauvegarde                   copie du jour dans iCloud Drive/Pilote
  pilote synchro                      échange les contacts et le fil d'un espace avec les tables distantes (reglages.json, synchro)
  pilote reglages                     ce qui est actif ou coupé (reglages.json), et où est le fichier
  pilote radar …                      Le Radar : comptes suivis, ratio des posts, Top 3, boîte à idées (pilote radar aide)
  pilote video-stats [--compte <compte_id|kryva|perso>] [--ref <ref>] [--sans-verdict] [--archivees]
  pilote video-stats --dus [--tout]   comme video-dus
                                      stats de chaque vidéo postée (lues dans reseaux-stats/stats.sqlite, lecture seule) : relevés 48 h et 7 j, rétention, conversions, verdict
  pilote video-dus [--tout]           les relevés à faire maintenant (48 h / 7 j) et les verdicts à écrire ; --tout : aussi manqués, en retard, à venir
  pilote video-verdict '<json>' | -   écrit le verdict d'une vidéo pour un relevé : compte_id, ref, palier (48h|7j), verdict (marche|moyen|rate|trop_tot), pourquoi, lecon, analyse, decrochage_s, decrochage_note, base_releve_le, par
  pilote export                       toute la base en JSON
  pilote mcp                          serveur MCP pour Claude Code (claude mcp add --scope user pilote -- <chemin>/pilote mcp)

Champs d'un contact : espace, type, nom, entreprise, ville, departement, telephone, email, linkedin,
facebook, site, etape (a_contacter|contacte|repondu|rdv|gagne|perdu), prochaine_action, prochaine_date
(AAAA-MM-JJ), priorite (1-3), ne_plus_contacter, org_id, source, source_ref, notes.
Champs d'un événement : canal, sens, type, texte, statut, par, le, objet (mails), reponse_a (Message-ID, mails en réponse),
condition (message prepare : à vérifier avant l'envoi), rappel_id (rappel lié : identifiant ou titre exact).
Statuts d'un événement : a_valider (brouillon à valider par \(Moi.tiers) dans l'app), a_refaire (renvoyé avec une consigne),
prepare (texte validé, à envoyer par \(Moi.tiers)), envoye, echec, annule, fait.
"""

func sortir(_ valeur: Encodable) {
    let enc = JSONEncoder()
    enc.keyEncodingStrategy = .convertToSnakeCase
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try! enc.encode(AnyEncodable(valeur))
    print(String(data: data, encoding: .utf8)!)
}

struct RapportSuites: Encodable {
    let appliquees: Bool
    let nombre: Int
    let contacts: [SuiteARetablir]
}

struct AnyEncodable: Encodable {
    let valeur: Encodable
    init(_ v: Encodable) { valeur = v }
    func encode(to encoder: Encoder) throws { try valeur.encode(to: encoder) }
}

struct Fiche: Encodable { let contact: Contact; let evenements: [Evenement] }
struct AEnvoyer: Encodable { let evenement: Evenement; let contact: Contact }
struct Jour: Encodable { let date: String; let dus: [Contact]; let aEnvoyer: [AEnvoyer] }
struct VideoAffichee: Encodable { let video: Video; let affichage: String; let tournage: String }

/// Les vidéos d'une plage (défaut : lundi à vendredi de la semaine en cours), avec le mot montré à Sacha.
func videosAffichees(_ stock: Stockage, du: String?, au: String?, reserve: Bool) throws -> [VideoAffichee] {
    let aujourdhui = Dates.aujourdhui()
    let semaine = VideoCalcul.semaine(de: aujourdhui)
    return try stock.videos(du: du ?? semaine.first ?? aujourdhui, au: au ?? semaine.last ?? aujourdhui, reserve: reserve).map { v in
        VideoAffichee(video: v, affichage: v.jour.isEmpty ? "Réserve" : VideoCalcul.affichage(v, jour: v.jour, aujourdhui: aujourdhui).texte,
                      tournage: v.jour.isEmpty ? "" : VideoCalcul.veilleOuvree(v.jour))
    }
}

struct FicheProjet: Encodable { let projet: Projet; let etat: String; let journal: [EntreeJournal]? }

func lireJSON(_ arg: String?) throws -> Any {
    let data: Data
    if arg == nil || arg == "-" {
        data = FileHandle.standardInput.readDataToEndOfFile()
    } else if let a = arg, FileManager.default.fileExists(atPath: a) {
        data = try Data(contentsOf: URL(fileURLWithPath: a))
    } else {
        data = Data(arg!.utf8)
    }
    return try JSONSerialization.jsonObject(with: data)
}

func echouer(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func option(_ nom: String, _ args: [String]) -> String? {
    guard let i = args.firstIndex(of: nom), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let commande = args.first else { print(aide); exit(0) }

if commande == "journal-crochet", (try? Base()) == nil { exit(0) }
if commande == "relais-fin" { Relais.fin(essai: args.contains("--essai")); exit(0) }
if commande == "relais-depart" { Relais.depart((try? Base()).map { Stockage(base: $0) }); exit(0) }
if commande == "relances" { Relais.relances(ajoute: args.contains("--ajoute")); exit(0) }
if commande == "reprise" { Relais.repriseDemandee((try? Base()).map { Stockage(base: $0) }); exit(0) }
if commande == "entrants" { Entrants.lancer(Array(args.dropFirst())); exit(0) }

// Essais de bout en bout (PILOTE_ENVOI_FAUX) : refusés AVANT d'ouvrir une base si PILOTE_BASE ne vise pas une copie.
if ProcessInfo.processInfo.environment["PILOTE_ENVOI_FAUX"] != nil {
    do { _ = try OutilsEnvoi.selonEnvironnement() } catch { echouer("\(error)") }
}

do {
    let stock = Stockage(base: try Base())
    switch commande {
    case "suivi-agents":
        sortir(try stock.journeesAgents(au: option("--jour", args) ?? Dates.aujourdhui()))
    case "jour":
        let pour = option("--pour", args) ?? ""
        if let r = Responsable(rawValue: pour), r != .sacha {
            let l = try stock.listeAgent(r)
            try stock.noterListe(l)   // gardée pour le suivi « Les agents aujourd'hui »
            sortir(l); break
        }
        let a = try stock.aEnvoyer().map { AEnvoyer(evenement: $0.0, contact: $0.1) }
        sortir(Jour(date: Dates.aujourdhui(), dus: try pour == "sacha" ? stock.dusSacha() : stock.dus(), aEnvoyer: a))

    case "contacts":
        var liste = try stock.contacts()
        if let e = option("--espace", args) { liste = liste.filter { $0.espace == e } }
        if let e = option("--etape", args) { liste = liste.filter { $0.etape == e } }
        if let t = option("--type", args) { liste = liste.filter { $0.type == t } }
        sortir(liste)

    case "cherche":
        guard args.count > 1 else { echouer("Usage : pilote cherche <texte>") }
        sortir(try stock.chercher(args[1...].joined(separator: " ")))

    case "fiche":
        guard args.count > 1, let c = try stock.contact(args[1]) else { echouer("Contact introuvable") }
        sortir(Fiche(contact: c, evenements: try stock.evenements(c.id)))

    case "enregistre":
        guard let champs = try lireJSON(args.count > 1 ? args[1] : nil) as? [String: Any] else { echouer("JSON attendu : un objet") }
        sortir(try stock.enregistrer(champs))

    case "evenement", "note":
        guard args.count > 1 else { echouer("Usage : pilote evenement <id_contact> '<json>'") }
        guard let champs = try lireJSON(args.count > 2 ? args[2] : nil) as? [String: Any] else { echouer("JSON attendu : un objet") }
        sortir(try stock.ajouterEvenement(contactId: args[1], champs))

    case "evenement-maj":
        guard args.count > 1, let champs = try lireJSON(args.count > 2 ? args[2] : nil) as? [String: Any] else { echouer("Usage : pilote evenement-maj <id_evenement> '<json>'") }
        try stock.modifierEvenement(args[1], champs)
        guard let e = try stock.evenement(args[1]) else { echouer("Événement introuvable") }
        sortir(e)

    case "envoye", "echec":
        guard args.count > 1 else { echouer("Usage : pilote \(commande) <id_evenement> [--malgre-condition]") }
        try stock.marquer(evenementId: args[1], statut: commande, malgreCondition: args.contains("--malgre-condition"))
        print("{\"ok\": true}")

    case "a-envoyer":
        var lignes = try EnvoiPilote.aEnvoyer(stock, outils: try OutilsEnvoi.selonEnvironnement())
        if args.contains("--mail") { lignes = lignes.filter { $0.canal == "mail" } }
        sortir(lignes)

    case "envoie":
        guard args.count > 1, !args[1].hasPrefix("--") else { echouer("Usage : pilote envoie <id> [--essai] [--empreinte <e>]") }
        do {
            let r = try EnvoiPilote.envoyer(args[1], stock: stock, outils: try OutilsEnvoi.selonEnvironnement(),
                                            essai: args.contains("--essai"), empreinte: option("--empreinte", args))
            sortir(r)
        } catch {
            echouer(EnvoiPilote.messageErreur(error))
        }

    case "file-envoi":
        do { try FileEnvoiCommande.lancer(stock, Array(args.dropFirst())) } catch { echouer(EnvoiPilote.messageErreur(error)) }

    case "publication":
        do { try PublicationCommande.lancer(stock, Array(args.dropFirst())) }
        catch let e as RefusPublication { echouer(e.description) }
        catch let e as ErreurPlateforme { echouer("Plateforme : \(e.description)") }
        catch { echouer("\(error)") }

    case "gmail-acces":
        guard let adresse = Gmail.adresse, !adresse.isEmpty else { echouer("Gmail n'est pas connecté : « Connecter Gmail » dans l'app d'abord.") }
        switch Gmail.lireMotDePasse(adresse, interactif: true) {
        case .present(let mdp):
            if args.contains("--verifier") {
                do { try Gmail.verifier(adresse: adresse, motDePasse: mdp) }   // jamais connecter() : il réécrirait l'élément du trousseau
                catch { echouer("Mot de passe lu, mais Gmail le refuse : \((error as? LocalizedError)?.errorDescription ?? "\(error)")") }
            }
            sortir(["ok": "true", "adresse": adresse,
                    "detail": args.contains("--verifier") ? "l'outil lit le mot de passe et Gmail l'accepte (aucun mail envoyé)"
                                                          : "l'outil peut lire le mot de passe (Gmail non contacté)"])
        case .absent: echouer("Aucun mot de passe d'application rangé pour \(adresse) : « Connecter Gmail » dans l'app.")
        case .autorisationRequise: echouer("Autorisation refusée dans la fenêtre du trousseau : relancer et cliquer « Toujours autoriser ».")
        case .erreur(let code): echouer("Trousseau illisible (code \(code)).")
        }

    case "condition-remplie":
        guard args.count > 1 else { echouer("Usage : pilote condition-remplie <id_evenement> [--par <qui>]") }
        let par = args.firstIndex(of: "--par").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } ?? "Claude"
        let note = try stock.conditionRemplie(evenementId: args[1], par: par)
        sortir(["ok": "true", "note": note.isEmpty ? "aucune condition en attente" : note])

    case "import":
        guard args.count > 1, let lot = try lireJSON(args[1]) as? [[String: Any]] else { echouer("Fichier attendu : un tableau JSON") }
        let ecraser = args.contains("--mettre-a-jour")
        var crees = 0, maj = 0, gardes = 0, evts = 0
        try stock.base.transaction {
            for item in lot {
                guard let champs = item["contact"] as? [String: Any] else { continue }
                let c: Contact
                if let deja = try stock.existant(champs) {
                    if ecraser { c = try stock.enregistrer(champs.merging(["id": deja.id]) { _, n in n }); maj += 1 } else { c = deja; gardes += 1 }
                } else {
                    c = try stock.enregistrer(champs); crees += 1
                }
                for e in item["evenements"] as? [[String: Any]] ?? [] {
                    _ = try stock.ajouterEvenement(contactId: c.id, e)
                    evts += 1
                }
            }
        }
        print("{\"crees\": \(crees), \"mis_a_jour\": \(maj), \"deja_presents_gardes\": \(gardes), \"evenements_traites\": \(evts)}")

    case "carte":
        var liste = try stock.projets()
        if let e = option("--espace", args) { liste = liste.filter { $0.espace == e } }
        sortir(liste.map { FicheProjet(projet: $0, etat: $0.lireEtat() ?? "", journal: nil) })

    case "projet":
        guard let champs = try lireJSON(args.count > 1 ? args[1] : nil) as? [String: Any] else { echouer("JSON attendu : un objet") }
        sortir(try stock.enregistrerProjet(champs))

    case "import-carte":
        guard args.count > 1, let lot = try lireJSON(args[1]) as? [[String: Any]] else { echouer("Fichier attendu : un tableau JSON") }
        try stock.base.transaction { for p in lot { try stock.enregistrerProjet(p) } }
        print("{\"projets\": \(lot.count)}")

    case "ou-est":
        guard args.count > 1 else { echouer("Usage : pilote ou-est <texte>") }
        sortir(try stock.chercherPartout(args[1...].joined(separator: " ")))

    case "agents":
        sortir(Sessions.vivantes())

    case "pyramide":
        print(Equipe.texte(Equipe.pyramide()))

    case "carte-domaine":
        CarteDomaineCommande.lancer(stock, args)

    case "journal":
        let n = args.count > 1 ? Int(args[1]) ?? 30 : 30
        sortir(try stock.journal(limite: n, projetId: option("--projet", args)))

    case "note-journal":
        guard let champs = try lireJSON(args.count > 1 ? args[1] : nil) as? [String: Any] else { echouer("JSON attendu : un objet") }
        sortir(try noterAuJournal(stock, champs))

    case "journal-crochet":
        journalDepuisCrochet(stock)
        exit(0)

    case "controle":
        var c = try stock.controle(envoisKryva: EnvoisKryva.lire(), verifierKryva: true, arrets: AlerteArret.lire())
        c.infos = [AlerteArret.ligneWhatsApp(AlerteArret.dernierWhatsApp())]
        if args.contains("--json") { sortir(c) } else { print(c.texte()) }

    case "fil-supprime":
        // pilote fil-supprime <id d'événement> : retire UNE entrée du fil (doublon) par le chemin de l'app (Stockage.supprimerEvenement).
        guard args.count >= 2, let e = try stock.evenement(args[1]) else { echouer("événement introuvable : pilote fil-supprime <id>") }
        try stock.supprimerEvenement(e.id)
        sortir(["supprime": e.id, "contact": e.contactId, "le": e.le, "par": e.par, "debut": String(e.texte.prefix(80))])

    case "repare-suites":
        let liste = try stock.suitesARetablir()
        let appliquer = args.contains("--appliquer")
        if appliquer { try stock.retablirSuites(liste) }
        sortir(RapportSuites(appliquees: appliquer, nombre: liste.count, contacts: liste))

    case "sauvegarde":
        if let f = try stock.sauvegardeDuJour() { print("{\"fichier\": \"\(f.path)\"}") } else { echouer("iCloud Drive introuvable") }

    case "reglages":
        var lignes = ["Fichier : \(Reglages.fichier.path)"
                      + (FileManager.default.fileExists(atPath: Reglages.fichier.path) ? "" : " (absent : tout est coupé)")]
        if let e = Reglages.erreur { lignes.append(e) }
        lignes.append("Prénom : \(Reglages.courants.prenomAffiche)")
        for b in Reglages.courants.bilan { lignes.append((b.actif ? "actif   " : "coupé   ") + b.nom + (b.actif ? "" : "  (\(b.detail))")) }
        print(lignes.joined(separator: "\n"))

    case "synchro":
        sortir(try Synchro(base: stock.base).lancer())

    case "export":
        print(String(data: try stock.exporter(), encoding: .utf8)!)

    case "radar":
        try radarCommande(stock, Array(args.dropFirst()))

    case "videos":
        sortir(try videosAffichees(stock, du: option("--du", args), au: option("--au", args), reserve: args.contains("--reserve")))

    case "video":
        guard let champs = try lireJSON(args.count > 1 ? args[1] : nil) as? [String: Any] else { echouer("JSON attendu : un objet") }
        sortir(try stock.enregistrerVideo(champs))

    case "video-stats":
        if args.contains("--dus") { sortir(try SuiviVideo.dus(stock: stock, tout: args.contains("--tout"))); break }   // même chose que video-dus
        sortir(try SuiviVideo.liste(stock: stock, compte: option("--compte", args), ref: option("--ref", args),
                                    sansVerdict: args.contains("--sans-verdict"), archivees: args.contains("--archivees")))

    case "video-dus":
        sortir(try SuiviVideo.dus(stock: stock, tout: args.contains("--tout")))

    case "video-verdict":
        guard let champs = try lireJSON(args.count > 1 ? args[1] : nil) as? [String: Any] else { echouer("JSON attendu : un objet") }
        sortir(try stock.enregistrerVerdict(champs))

    case "mcp":
        serveurMCP(stock)

    case "aide", "-h", "--help":
        print(aide)

    default:
        echouer("Commande inconnue : \(commande)\n\n\(aide)")
    }
} catch {
    echouer("Erreur : \(error)")
}
