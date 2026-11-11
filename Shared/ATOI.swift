// « À toi » (écran unique, 09/11) : tout ce qui attend un geste de Sacha, construit ici à partir de valeurs simples pour être
// testé (Tests/ATOITests.swift). L'app remplit SourcesATOI depuis l'état, l'agenda et le tableau (App/Vues/EcranUnique.swift).
// ControleATOI recompte la même chose directement dans les sources, par des règles écrites à part : un écart = un oubli,
// dit en rouge en haut de l'écran (demande de Sacha du 09/11 13:04 : « il faut qu'il n'y ait aucun oubli »).
import Foundation

// MARK: - Ce que l'écran lit

struct Rappel: Identifiable, Hashable {
    let id: String
    let titre: String
    let notes: String
    let liste: String
    let echeance: Date?
    let enRetard: Bool
    let priorite: Int
    /// L'échéance porte une heure (sinon : la journée entière).
    var avecHeure = false
}

struct RendezVous: Identifiable, Hashable {
    let id: String
    let titre: String
    let debut: Date
    let fin: Date
    let calendrier: String
    let journee: Bool
    let lieu: String
    let url: URL?
    /// Identifiant iCloud (le même que dans le planning) : la clé de « Fait » dans Ma journée.
    var ref = ""
}

struct MessageAEnvoyer: Identifiable, Hashable {
    let evenement: Evenement
    let contact: Contact
    var id: String { evenement.id }
    /// Le jour où il part : celui écrit en tête du message, sinon la date de la fiche.
    /// Un message prêt depuis un jour précédent part aujourd'hui, même si la fiche porte une date plus loin (04/11, Sacha :
    /// 2 mails prêts n'apparaissaient pas) ; règle dans Libelles.jourDuMessage.
    /// 09/11 : calculé une fois à la lecture (hors du fil principal), plus à chaque comparaison d'un tri (expression régulière).
    let jour: String

    init(evenement: Evenement, contact: Contact, aujourdhui: String = Dates.aujourdhui()) {
        self.evenement = evenement
        self.contact = contact
        jour = Libelles.jourDuMessage(texte: evenement.texte, le: evenement.le, dateFiche: contact.prochaineDate,
                                      aujourdhui: aujourdhui, condition: evenement.conditionPourJour,
                                      reponseA: evenement.reponseA)
    }
}

/// La question de fin de tour d'une session, avec le nom d'équipe de la session.
struct QuestionATOI: Hashable {
    let activite: ActiviteSession
    let nom: String
}

struct SourcesATOI {
    var maintenant = Date()
    var aValider: [MessageAEnvoyer] = []
    var aEnvoyer: [MessageAEnvoyer] = []
    var candidatsFile: [CandidatFile] = []
    var questions: [QuestionATOI] = []
    /// Rappels à faire dont l'échéance est aujourd'hui ou avant (toutes listes).
    var rappels: [Rappel] = []
    /// Décisions ❓ à faire dont l'échéance est après aujourd'hui (ou sans date).
    var decisionsAVenir: [Rappel] = []
    /// Rappels à faire dont l'échéance est demain.
    var rappelsDemain: [Rappel] = []
    var dus: [Contact] = []
    var publications: [Publication] = []
    var rendezVous: [RendezVous] = []
    var videos: [Video] = []
    /// Les réponses de Sacha notées mais pas encore envoyées (elles attendent son clic, puis le Facteur ou la veille).
    var reponses: [Decisions.Envoyee] = []
}

enum ATOI {
    /// Les listes de Rappels de Sacha (le planning, docs/PLANNING-CONTRAT.md). Les autres listes (Agents…) ne sont pas
    /// à lui : seules leurs décisions ❓ viennent dans « À toi ».
    static func listeDeSacha(_ liste: String) -> Bool { CalendriersPlanning.tache(liste) }

    /// Un rappel qui attend Sacha : une décision ❓ (toute liste), ou une tâche d'une de ses listes.
    static func pourSacha(_ r: Rappel) -> Bool { Decisions.estDecision(r.titre) || listeDeSacha(r.liste) }

    /// Le domaine d'une liste, dit comme sur l'écran.
    static func domaine(_ liste: String) -> String {
        switch liste {
        case "Appels": return L("Ventes")
        case "Contenu": return L("Réseaux")
        default: return liste
        }
    }

    /// Le nom d'une vidéo à publier, jamais « Vidéo sans titre » (09/11) : son titre, sinon le sujet de la vidéo du jour,
    /// sinon le début de la légende, sinon le nom du fichier.
    static func titre(_ p: Publication, videos: [Video]) -> String {
        let t = p.titre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let jour = p.prevu.map({ Dates.jour.string(from: $0) }),
           let v = videos.first(where: { $0.jour == jour && !$0.sujet.isEmpty && p.compte.hasSuffix($0.compte) }) {
            return v.sujet
        }
        let legende = p.texte.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if !legende.isEmpty { return legende.count > 70 ? String(legende.prefix(70)) + "…" : legende }
        let chemin = p.source.isEmpty ? p.fichier : p.source
        let nom = ((chemin as NSString).lastPathComponent as NSString).deletingPathExtension
        if !nom.isEmpty { return nom }
        return L("Vidéo \(Domaines.nomCompte(p.compte))")
    }
}

// MARK: - Les gestes de Sacha

struct GesteSacha: Identifiable {
    enum Genre {
        case texte(MessageAEnvoyer)
        case envoiMail(MessageAEnvoyer)
        /// Un message à envoyer à la main (SMS, DM…), ou un mail que Pilote ne peut pas envoyer (raison dans le contexte).
        case envoi(MessageAEnvoyer)
        case decision(Rappel)
        case question(QuestionATOI)
        case publication(Publication)
        case rendezVous(RendezVous)
        case tourner(Video)
        case publier(Video)
        case seance
        /// Un geste de Sacha écrit dans la fiche d'une personne (« Sacha : visio avec Arthur… »), dû aujourd'hui ou avant.
        case prospect(Contact)
        /// Un brouillon arrivé dans la boîte TikTok : c'est Sacha qui publie dans l'app.
        case tiktok(Publication)
        /// Une tâche de ses listes (KRYVA, Appels, Freelance, Contenu, Papiers), due aujourd'hui ou en retard.
        case rappel(Rappel)
        /// Les tâches de demain, en une ligne repliée (pas comptées dans « À toi »).
        case demain([Rappel])
        /// Ses réponses en attente d'envoi : un seul bouton les envoie toutes au Facteur (09/11, « j'envoie tout en un bouton »).
        case reponses([Decisions.Envoyee])
        /// Plusieurs gestes du même genre en une ligne (« 28 messages à envoyer ») ; un clic ouvre la liste.
        case groupe([GesteSacha])
    }

    let id: String
    let genre: Genre
    let verbe: String
    let objet: String
    let contexte: String
    /// Le bouton qui fait le geste jusqu'au bout. Vide : pas de bouton (les choix sont sur la ligne, ou rien à faire ici).
    let bouton: String
    let symbole: String
    /// Plus petit = plus urgent.
    let urgence: Int
    let quand: Date?
    /// Les choix d'une décision, posés directement sur la ligne (3 au plus, courts) : un clic tranche.
    var choix: [String] = []
    /// Le contexte est un blocage (en rouge) : le message ne peut pas partir de Pilote.
    var bloque = false
    /// En retard (09/11, Organisation : une heure passée doit se voir) : le verbe s'écrit en rouge.
    var retard = false
    /// Une décision sans options : le bouton « C'est réglé » la ferme (le code lit ce champ, jamais le texte du bouton, qui se traduit).
    var reglable = false

    /// Ce que la ligne compte dans « À toi » : ses gestes (un groupe compte chacun des siens ; demain ne compte pas).
    var gestes: [GesteSacha] {
        switch genre {
        case .groupe(let l): return l.flatMap(\.gestes)
        case .demain: return []
        default: return [self]
        }
    }

    static let choixCourt = 40

    /// Les gestes du moment, tous domaines confondus, du plus urgent au moins urgent (la ligne « Demain » en dernier).
    static func du(_ s: SourcesATOI) -> [GesteSacha] {
        let maintenant = s.maintenant
        var g: [GesteSacha] = []
        let aujourdhui = Dates.jour.string(from: maintenant)
        let candidats = Dictionary(s.candidatsFile.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for m in s.aValider {
            g.append(GesteSacha(id: "texte:\(m.id)", genre: .texte(m), verbe: L("Valider le texte"), objet: m.contact.nomAffiche,
                                contexte: Self.debut(m.evenement.texte), bouton: L("Valider"), symbole: "text.bubble",
                                urgence: 30, quand: Dates.iso.date(from: m.evenement.le)))
        }
        for m in s.aEnvoyer where (m.jour.isEmpty || m.jour <= aujourdhui) && !m.evenement.conditionEnAttente {
            let canal = Libelles.canal(m.evenement.canal)
            let resume = m.evenement.objet.isEmpty ? Self.debut(m.evenement.texte) : m.evenement.objet
            if m.evenement.canal == "mail" {
                if let c = candidats[m.id], c.envoyable {
                    g.append(GesteSacha(id: "envoi:\(m.id)", genre: .envoiMail(m), verbe: L("Envoyer"), objet: m.contact.nomAffiche,
                                        contexte: "\(canal) · \(resume)", bouton: L("Envoyer"), symbole: "paperplane",
                                        urgence: 40, quand: nil))
                } else {
                    // 09/11 : un mail prêt que Pilote ne peut pas envoyer ne disparaît plus (Gmail pas connecté, objet vide…).
                    let raison = candidats[m.id]?.refus.first ?? L("pas encore vérifié par Pilote")
                    g.append(GesteSacha(id: "envoi:\(m.id)", genre: .envoi(m), verbe: L("Envoyer à la main"), objet: m.contact.nomAffiche,
                                        contexte: L("Pilote ne peut pas l'envoyer : \(raison)"), bouton: L("Envoyé"),
                                        symbole: "paperplane", urgence: 40, quand: nil, bloque: true))
                }
            } else {
                g.append(GesteSacha(id: "envoi:\(m.id)", genre: .envoi(m), verbe: L("Envoyer"), objet: m.contact.nomAffiche,
                                    contexte: "\(canal) · \(Self.debut(m.evenement.texte))", bouton: L("Envoyé"),
                                    symbole: "paperplane", urgence: 40, quand: nil))
            }
        }
        for q in s.questions {
            let a = q.activite
            let choix = Self.choixSurLaLigne(a.choix)
            g.append(GesteSacha(id: "question:\(a.questionRef)", genre: .question(q), verbe: L("Répondre"), objet: q.nom,
                                contexte: a.question, bouton: choix.isEmpty ? L("Répondre") : "", symbole: "questionmark.bubble",
                                urgence: 10, quand: a.depuis, choix: choix))
        }
        // Une décision ❓ attend Sacha dès qu'elle est posée : celles dont l'échéance est plus tard viennent aussi, avec leur date.
        let aVenir = Set(s.decisionsAVenir.map(\.id))
        for r in s.rappels + s.decisionsAVenir where Decisions.estDecision(r.titre) {
            let options = Decisions.options(r.notes)
            let choix = Self.choixSurLaLigne(options)
            let detail = Decisions.contexte(r.notes).components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            let pour = aVenir.contains(r.id) ? r.echeance.map { L("Pour \(Libelles.quand($0, maintenant: maintenant))") } : nil
            g.append(GesteSacha(id: "decision:\(r.id)", genre: .decision(r), verbe: L("Décider"), objet: Decisions.question(r.titre),
                                contexte: [pour, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                bouton: options.isEmpty ? L("C'est réglé") : (choix.isEmpty ? L("Répondre") : ""),
                                symbole: "questionmark.circle",
                                urgence: Domaines.urgenceDecision(echeance: r.echeance, enRetard: r.enRetard, maintenant: maintenant),
                                quand: r.echeance, choix: choix, retard: r.enRetard, reglable: options.isEmpty))
        }
        for r in s.rappels where !Decisions.estDecision(r.titre) && ATOI.listeDeSacha(r.liste) {
            g.append(Self.tache(r, maintenant: maintenant))
        }
        if !s.reponses.isEmpty {
            g.append(Self.reponses(s.reponses))
        }
        for c in s.dus {
            let r = ResumeContact(id: c.id, nom: c.nom, entreprise: c.entreprise, espace: c.espace, etape: c.etape,
                                  prochaineAction: c.prochaineAction, prochaineDate: c.prochaineDate)
            guard let geste = Domaines.gesteSacha(r) else { continue }
            let nom = c.nom.isEmpty ? c.entreprise : Domaines.nomEtEntreprise(c.nom, c.entreprise)
            let retard = c.prochaineDate < aujourdhui
            g.append(GesteSacha(id: "prospect:\(c.id)", genre: .prospect(c), verbe: retard ? L("En retard") : L("Aujourd'hui"), objet: nom,
                                contexte: geste, bouton: L("Fait"), symbole: "person.crop.circle",
                                urgence: retard ? 20 : 45, quand: Dates.jour.date(from: c.prochaineDate), retard: retard))
        }
        for p in s.publications where Domaines.estDansBoiteTikTok(p) {
            g.append(GesteSacha(id: "tiktok:\(p.id)", genre: .tiktok(p), verbe: L("Publier sur TikTok"),
                                objet: ATOI.titre(p, videos: s.videos),
                                contexte: L("Publie le brouillon dans l'app TikTok, puis clique Publiée")
                                    + (p.prevu.map { " · " + L("prévue \(Libelles.quand($0, maintenant: maintenant))") } ?? ""),
                                bouton: L("Publiée"), symbole: "arrow.up.circle", urgence: 45, quand: p.prevu))
        }
        for p in s.publications where p.etat == "a_valider" {
            g.append(GesteSacha(id: "publication:\(p.id)", genre: .publication(p), verbe: L("Valider la publication"),
                                objet: ATOI.titre(p, videos: s.videos),
                                contexte: Domaines.nomCompte(p.compte) + (p.prevu.map { " · \(Libelles.jourHeure($0))" } ?? ""),
                                bouton: L("Valider"), symbole: "play.rectangle", urgence: 35, quand: p.prevu))
        }
        // Un rendez-vous commencé sort de « À toi » (09/11 : « Salle 11:00 » restait en tête à 12:40).
        for r in s.rendezVous where !r.journee && r.debut > maintenant {
            let bientot = r.debut.timeIntervalSince(maintenant) < 2 * 3600
            let bouton = r.url != nil ? L("Rejoindre") : (r.lieu.isEmpty ? "" : L("Itinéraire"))
            g.append(GesteSacha(id: "rdv:\(r.id):\(Int(r.debut.timeIntervalSince1970))", genre: .rendezVous(r), verbe: L("Rendez-vous"),
                                objet: r.titre, contexte: L("à \(Self.heure(r.debut))") + (r.lieu.isEmpty ? "" : " · \(Self.uneLigne(r.lieu))"),
                                bouton: bouton, symbole: "calendar", urgence: bientot ? 0 : 60, quand: r.debut))
        }
        if VideoCalcul.estOuvre(aujourdhui) {
            let demain = VideoCalcul.lendemainOuvre(aujourdhui)
            for v in s.videos where v.jour == demain && v.statut == "valide" {
                g.append(GesteSacha(id: "tourner:\(v.id)", genre: .tourner(v), verbe: L("Tourner"), objet: v.sujet,
                                    contexte: L("Vidéo \(VideoVocabulaire.compte(v.compte)) pour le \(Dates.court(demain))")
                                        + (v.prompteur.isEmpty ? "" : " · " + L("prompteur prêt")),
                                    bouton: L("Tournée"), symbole: "video", urgence: 70, quand: nil))
            }
            for v in s.videos where v.jour == aujourdhui && v.statut == "prete" {
                let programmee = s.publications.contains {
                    $0.etat != "annule" && $0.prevuLe.hasPrefix(aujourdhui) && $0.compte.hasSuffix(v.compte)
                }
                if programmee { continue }
                g.append(GesteSacha(id: "publier:\(v.id)", genre: .publier(v), verbe: L("Publier"), objet: v.sujet,
                                    contexte: L("Vidéo \(VideoVocabulaire.compte(v.compte)) prête, pas programmée : publie-la, puis clique Publiée"),
                                    bouton: L("Publiée"), symbole: "arrow.up.circle", urgence: 45, quand: nil))
            }
        }
        if SeanceDimanche.affichee(aujourdhui) {
            let c = SeanceDimanche.creneaux(s.videos, aujourdhui: aujourdhui)
            let reste = c.filter { !$0.choisi }.count
            if reste > 0 {
                g.append(GesteSacha(id: "seance:\(aujourdhui)", genre: .seance, verbe: L("Choisir les sujets"),
                                    objet: L("semaine du \(DemainPret.libelleJour(SeanceDimanche.semaine(aujourdhui).first ?? aujourdhui))"),
                                    contexte: L("\(c.count - reste) sur \(c.count) choisis"), bouton: L("Choisir"), symbole: "list.bullet.rectangle",
                                    urgence: 55, quand: nil))
            }
        }
        g.sort { a, b in
            a.urgence != b.urgence ? a.urgence < b.urgence : (a.quand ?? .distantFuture) < (b.quand ?? .distantFuture)
        }
        let demain = s.rappelsDemain.filter { !Decisions.estDecision($0.titre) && ATOI.listeDeSacha($0.liste) }
            .sorted { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }
        if !demain.isEmpty {
            let noms = demain.prefix(2).map(\.titre).joined(separator: ", ")
            g.append(GesteSacha(id: "demain:\(aujourdhui)", genre: .demain(demain), verbe: L("Demain"),
                                objet: demain.count == 1 ? L("1 tâche") : L("\(demain.count) tâches"),
                                contexte: demain.count > 2 ? noms + " " + L("et \(demain.count - 2) autres") : noms,
                                bouton: L("Voir"), symbole: "sunrise", urgence: Int.max, quand: nil))
        }
        return g
    }

    /// Une tâche de Rappels : en retard, à son heure, ou dans la journée ; le bouton « Fait » la coche.
    /// La ligne « Tes réponses » : un bouton les envoie toutes. Son id porte les rangs, pour qu'une nouvelle réponse
    /// arrivée après un envoi refasse une ligne (l'ancienne reste masquée).
    static func reponses(_ r: [Decisions.Envoyee]) -> GesteSacha {
        let n = r.count
        let pour = r.map(\.pour).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let premiere = r.first.map { "\($0.question) → \($0.choix)" } ?? ""
        return GesteSacha(id: idReponses(r), genre: .reponses(r), verbe: L("Envoyer"),
                          objet: n == 1 ? L("ta réponse") : L("tes \(n) réponses"),
                          contexte: ([L("pour \(pour.joined(separator: ", "))")] + (n == 1 ? [premiere] : [])).joined(separator: " · "),
                          bouton: n == 1 ? L("Envoyer") : L("Tout envoyer (\(n))"), symbole: "paperplane.fill",
                          urgence: 8, quand: nil)
    }
    static func idReponses(_ r: [Decisions.Envoyee]) -> String { "reponses:" + r.map { String($0.id) }.joined(separator: ",") }

    static func tache(_ r: Rappel, maintenant: Date) -> GesteSacha {
        let debutJour = Calendar.current.startOfDay(for: maintenant)
        let echeance = r.echeance ?? maintenant
        // 09/11 : une tâche à heure dont l'heure est passée est en retard (13:30 vue à 13:47 ne disait rien).
        let retard = r.enRetard || echeance < debutJour || (r.avecHeure && echeance < maintenant)
        let (verbe, urgence): (String, Int)
        if retard {
            (verbe, urgence) = (L("En retard"), 20)
        } else if r.avecHeure {
            let ecart = echeance.timeIntervalSince(maintenant)
            (verbe, urgence) = (L("À \(heure(echeance))"), ecart <= 0 ? 22 : (ecart < 2 * 3600 ? 25 : 48))
        } else {
            (verbe, urgence) = (L("Aujourd'hui"), 46)
        }
        let but = NotesPlanning.lire(r.notes).but ?? ""
        let depuis = retard ? L("prévu \(Libelles.quand(echeance, maintenant: maintenant))") : ""
        let contexte = [ATOI.domaine(r.liste), depuis, but].filter { !$0.isEmpty }.joined(separator: " · ")
        return GesteSacha(id: "rappel:\(r.id)", genre: .rappel(r), verbe: verbe, objet: Self.sansSacha(r.titre),
                          contexte: contexte, bouton: L("Fait"), symbole: "checkmark.circle", urgence: urgence, quand: r.echeance,
                          retard: retard)
    }

    /// Les choix posés sur la ligne : 1 à 3, chacun assez court pour un bouton ; sinon la ligne se déplie (« Répondre »).
    static func choixSurLaLigne(_ options: [String]) -> [String] {
        (1...3).contains(options.count) && options.allSatisfy({ $0.count <= choixCourt }) ? options : []
    }

    /// Quand il y en a trop (plus de `plafond` gestes), au-delà de 3 gestes du même genre (textes à valider, messages à envoyer,
    /// publications à valider, tâches d'une même liste), une seule ligne « 28 messages à envoyer » à la place du premier ; un clic
    /// ouvre la liste, chaque geste y garde son bouton. Sinon chaque geste garde sa ligne (09/11 : 5 tâches Réseaux à des heures
    /// différentes en une ligne cachaient celle de 13:30). Le plus urgent n'est jamais dans un groupe.
    static let plafond = 12
    /// En dessous (en retard, à l'heure passée, dans les 2 h, questions, rendez-vous proches), un geste n'est jamais groupé.
    static let urgenceGroupable = 30
    static func grouper(_ gestes: [GesteSacha]) -> [GesteSacha] {
        guard gestes.reduce(0, { $0 + $1.gestes.count }) > plafond else { return gestes }
        func famille(_ g: GesteSacha) -> String? {
            guard g.urgence >= urgenceGroupable else { return nil }   // en retard, ou dans les 2 h : toujours sa ligne
            switch g.genre {
            case .texte: return "texte"
            case .envoiMail, .envoi: return "envoi"
            case .publication: return "publication"
            case .rappel(let r): return "rappel:\(r.liste)"
            default: return nil
            }
        }
        var parFamille: [String: [GesteSacha]] = [:]
        for g in gestes { if let f = famille(g) { parFamille[f, default: []].append(g) } }
        var res: [GesteSacha] = []
        var places: Set<String> = []
        for g in gestes {
            guard let f = famille(g), let tous = parFamille[f], tous.count > 3 else { res.append(g); continue }
            guard !places.contains(f) else { continue }
            places.insert(f)
            let n = tous.count
            let (verbe, objet): (String, String)
            switch f {
            case "texte": (verbe, objet) = (L("Valider"), L("\(n) textes"))
            case "envoi": (verbe, objet) = (L("Envoyer"), L("\(n) messages"))
            case "publication": (verbe, objet) = (L("Valider"), L("\(n) publications"))
            default:
                let liste = f.replacingOccurrences(of: "rappel:", with: "")
                (verbe, objet) = (L("Faire"), L("\(n) tâches \(ATOI.domaine(liste))"))
            }
            let noms = tous.prefix(3).map(\.objet).joined(separator: ", ")
            res.append(GesteSacha(id: "groupe:\(f)", genre: .groupe(tous), verbe: verbe, objet: objet,
                                  contexte: n > 3 ? noms + " " + L("et \(n - 3) autres") : noms, bouton: L("Voir la liste"),
                                  symbole: g.symbole, urgence: g.urgence, quand: g.quand))
        }
        return res
    }

    /// Une adresse sur plusieurs lignes, dite sur une seule.
    static func uneLigne(_ t: String) -> String {
        t.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func debut(_ texte: String) -> String {
        let une = texte.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return une.count > 90 ? String(une.prefix(90)) + "…" : une
    }

    /// « Sacha : taper push… » → « Taper push… » : la ligne est déjà à lui.
    static func sansSacha(_ titre: String) -> String {
        var t = titre.trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: #"^sacha\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) { t.removeSubrange(r) }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private static let formatHeure: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"; return f
    }()
    static func heure(_ d: Date) -> String { formatHeure.string(from: d) }
}

// MARK: - Ce que fait le bouton

/// Ce que fait le bouton principal d'une ligne : le geste jusqu'au bout (texte validé, mail en file, tâche cochée…),
/// ou déplier quand il faut choisir parmi plusieurs choses (liste groupée, séance du dimanche, choix trop longs pour la ligne).
/// L'écran exécute exactement ceci : une seule source pour l'app et pour les tests.
enum ActionGeste: Equatable {
    case validerTexte(MessageAEnvoyer)
    case mettreEnFile(MessageAEnvoyer)
    case marquerEnvoye(MessageAEnvoyer)
    case cocherRappel(Rappel)
    case prospectFait(Contact)
    case tiktokPubliee(Publication)
    case validerPublication(Publication)
    /// Les rangs des réponses à envoyer (Facteur.noter … .pret, comme « Tout envoyer » de la Journée en détail).
    case envoyerReponses([Int])
    /// action : « tourner » ou « publier » (comme marquerVideoJournee).
    case videoFaite(Video, action: String)
    /// Le choix noté pour une décision ❓ (« réglé » quand elle n'a pas d'options).
    case choisir(String)
    case ouvrir(URL)
    case deplier
    case aucune
}

extension GesteSacha {
    var action: ActionGeste {
        guard !bouton.isEmpty else { return .aucune }
        switch genre {
        case .texte(let m): return .validerTexte(m)
        case .envoiMail(let m): return .mettreEnFile(m)
        case .envoi(let m): return .marquerEnvoye(m)
        case .rappel(let r): return .cocherRappel(r)
        case .prospect(let c): return .prospectFait(c)
        case .tiktok(let p): return .tiktokPubliee(p)
        case .publication(let p): return .validerPublication(p)
        case .tourner(let v): return .videoFaite(v, action: "tourner")
        case .publier(let v): return .videoFaite(v, action: "publier")
        case .decision: return reglable ? .choisir("réglé") : .deplier
        case .rendezVous(let r):
            if let u = r.url { return .ouvrir(u) }
            guard let q = r.lieu.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let u = URL(string: "maps://?daddr=\(q)") else { return .aucune }
            return .ouvrir(u)
        case .reponses(let r): return .envoyerReponses(r.map(\.id))
        case .question, .seance, .groupe, .demain: return .deplier
        }
    }
}

// MARK: - Le contrôle « aucun oubli »

enum ControleATOI {
    /// Ce qui attend Sacha, compté directement dans les sources (id du geste → ce qu'on dirait de lui), par des règles
    /// écrites ici sans passer par GesteSacha.du : les rappels de ses listes dus aujourd'hui ou en retard, les décisions ❓,
    /// les questions des sessions, les textes à valider, les messages prêts du jour, les gestes écrits dans les fiches, les
    /// publications à valider ou à finir dans TikTok, les rendez-vous du jour pas commencés, les vidéos à tourner ou à publier.
    static func attendus(_ s: SourcesATOI) -> [String: String] {
        var a: [String: String] = [:]
        let aujourdhui = Dates.jour.string(from: s.maintenant)
        for r in s.rappels + s.decisionsAVenir {
            if r.titre.trimmingCharacters(in: .whitespaces).hasPrefix("❓") { a["decision:\(r.id)"] = L("décision « \(r.titre) »") }
            else if CalendriersPlanning.listesTaches.contains(where: { $0.nom == r.liste }) { a["rappel:\(r.id)"] = L("tâche « \(r.titre) »") }
        }
        for q in s.questions { a["question:\(q.activite.questionRef)"] = L("question de \(q.nom)") }
        for m in s.aValider { a["texte:\(m.id)"] = L("texte pour \(m.contact.nomAffiche)") }
        for m in s.aEnvoyer {
            let du = m.jour.isEmpty || m.jour <= aujourdhui
            let conditionOuverte = !m.evenement.condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && m.evenement.conditionOkLe.isEmpty
            if du && !conditionOuverte { a["envoi:\(m.id)"] = L("message pour \(m.contact.nomAffiche)") }
        }
        for c in s.dus {
            let r = ResumeContact(id: c.id, nom: c.nom, entreprise: c.entreprise, espace: c.espace, etape: c.etape,
                                  prochaineAction: c.prochaineAction, prochaineDate: c.prochaineDate)
            if Domaines.gesteSacha(r) != nil { a["prospect:\(c.id)"] = L("geste pour \(c.nom.isEmpty ? c.entreprise : c.nom)") }
        }
        if !s.reponses.isEmpty { a[GesteSacha.idReponses(s.reponses)] = s.reponses.count == 1 ? L("1 réponse à envoyer") : L("\(s.reponses.count) réponses à envoyer") }
        for p in s.publications {
            if p.etat == "a_valider" { a["publication:\(p.id)"] = L("publication à valider") }
            if p.compte.hasPrefix("tt") && p.etat == "envoye" && p.phase == "boite" { a["tiktok:\(p.id)"] = L("brouillon TikTok à publier") }
        }
        for r in s.rendezVous where !r.journee && r.debut > s.maintenant {
            a["rdv:\(r.id):\(Int(r.debut.timeIntervalSince1970))"] = L("rendez-vous « \(r.titre) »")
        }
        return a
    }

    /// Les ids montrés par « À toi » (chaque geste d'un groupe compte ; la ligne « Demain » ne compte pas).
    static func montres(_ lignes: [GesteSacha]) -> Set<String> { Set(lignes.flatMap(\.gestes).map(\.id)) }

    /// Ce qui manque à l'écran (attendu, pas montré). Les vidéos et la séance du dimanche ne sont pas recomptées : elles
    /// dépendent du calendrier des vidéos, pas d'une chose posée pour Sacha. `masques` : les gestes en train de partir (5 s).
    static func manquants(_ s: SourcesATOI, lignes: [GesteSacha], masques: Set<String> = []) -> [String] {
        let vus = montres(lignes)
        return attendus(s).filter { !vus.contains($0.key) && !masques.contains($0.key) }.map(\.value).sorted()
    }

    /// La ligne rouge de l'écran, ou nil si tout est là.
    static func alerte(_ manquants: [String]) -> String? {
        guard !manquants.isEmpty else { return nil }
        let n = manquants.count
        let liste = manquants.prefix(3).joined(separator: ", ") + (n > 3 ? " " + L("et \(n - 3) autres") : "")
        return n == 1 ? L("À toi : 1 chose ne s'affiche pas (\(liste)). PILOTE est à prévenir.")
            : L("À toi : \(n) choses ne s'affichent pas (\(liste)). PILOTE est à prévenir.")
    }
}
