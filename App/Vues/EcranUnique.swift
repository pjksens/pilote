// L'écran unique (docs/ECRAN-UNIQUE.md, 09/11) : l'en-tête (date, loupe, ⌘K), « À toi » (les gestes de Sacha, triés par
// urgence, 3 visibles) et une ligne par domaine qui se déplie sur place. Rien n'est lu ici : tout vient de l'état et du
// tableau, déjà lus hors du fil principal.
import SwiftUI
import AppKit
import QuartzCore

// MARK: - Les gestes de Sacha (construits dans Shared/ATOI.swift)

extension SourcesATOI {
    /// Ce que « À toi » lit, pris dans l'état, l'agenda et le tableau (déjà lus hors du fil principal).
    @MainActor
    init(etat: Etat, agenda: Agenda, tableau: TableauDomaines, maintenant: Date = Date()) {
        self.init(maintenant: maintenant, aValider: etat.aValider, aEnvoyer: etat.aEnvoyer, candidatsFile: etat.candidatsFile,
                  questions: etat.questionsSessions.map { QuestionATOI(activite: $0, nom: etat.nomSession($0)) },
                  rappels: agenda.rappels, decisionsAVenir: agenda.decisionsAVenir, rappelsDemain: agenda.rappelsDemain,
                  dus: etat.dus, publications: tableau.publications, rendezVous: agenda.rendezVous, videos: etat.videos,
                  reponses: etat.decisionsEnvoyees.filter(\.enAttente) + Self.reponsesEssai)
    }

    /// Essai seulement (PILOTE_ESSAI_REPONSES=1 avec PILOTE_BASE) : 3 réponses factices pour voir « Tout envoyer » en capture.
    /// Rangs négatifs : aucune ligne réelle du Facteur ne leur correspond, rien ne peut partir.
    static let reponsesEssai: [Decisions.Envoyee] = {
        let env = ProcessInfo.processInfo.environment
        guard env["PILOTE_BASE"] != nil, env["PILOTE_ESSAI_REPONSES"] == "1" else { return [] }
        return [("Garder le prix à 29 € ?", "Oui", "KRYVA · Ventes"), ("Publier la vidéo demain 9 h ?", "Oui, 9 h", "KRYVA · Réseaux, image, événements"),
                ("Relancer Arthur par SMS ?", "Non, attendre jeudi", "FREELANCE")].enumerated().map { i, r in
            Decisions.Envoyee(id: -1 - i, question: r.0, choix: r.1, pour: r.2, heure: "14:\(30 + i)", transmise: false, enAttente: true)
        }
    }()
}

// MARK: - L'écran

struct EcranUnique: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    @Environment(TableauDomaines.self) private var tableau
    @Environment(\.accessibilityReduceMotion) private var sansMouvement

    @State private var deplie: Domaine?
    @State private var gesteOuvert: String?
    @State private var tousLesGestes = false
    /// Une pastille de domaine qui renvoie à sa ligne de « À toi » fait remonter l'écran (09/11).
    @State private var remonter = 0
    @State private var cibleDefilement = "atoi"
    @State private var ancreDefilement: UnitPoint = .top
    @State private var masques: Set<String> = []
    @State private var enAttente: Attente?
    @State private var erreurGeste: String?

    struct Attente: Equatable {
        let id: String
        let libelle: String
        let tache: Task<Void, Never>
        let faire: @MainActor () -> Void
        static func == (a: Attente, b: Attente) -> Bool { a.id == b.id }
    }

    private var ressort: Animation? { sansMouvement ? nil : .spring(response: 0.32, dampingFraction: 0.86) }

    var body: some View {
        ScrollView {
          ScrollViewReader { defile in
            VStack(alignment: .leading, spacing: 28) {
                enTete
                TimelineView(.everyMinute) { contexte in
                    let sources = SourcesATOI(etat: etat, agenda: agenda, tableau: tableau, maintenant: contexte.date)
                    let lignes = GesteSacha.grouper(GesteSacha.du(sources).filter { !masques.contains($0.id) })
                    let controle = alerteControle(sources, lignes)
                    VStack(alignment: .leading, spacing: 28) {
                        if !etat.arrets.isEmpty || etat.erreurBase != nil || etat.erreurSynchro != nil || !controle.isEmpty {
                            alertes(controle)
                        }
                        blocATOI(lignes).id("atoi")
                    }
                }
                blocDomaines
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 64)
            .frame(maxWidth: .infinity)
            .onChange(of: remonter) { _, _ in withAnimation(ressort) { defile.scrollTo(cibleDefilement, anchor: ancreDefilement) } }
          }
        }
        .background(Color.fond)
        .overlay(alignment: .bottom) { toast }
        .onAppear { tableau.demarrer() }
        .task { await essais() }
        .onChange(of: etat.agents, initial: true) { _, a in tableau.sessions(a) }
        .onChange(of: agenda.taches, initial: true) { _, _ in tableau.taches(papiersLisibles ? agenda.taches : nil) }
        .onChange(of: agenda.tachesLues) { _, _ in tableau.taches(papiersLisibles ? agenda.taches : nil) }
    }

    /// Essais seulement (jamais posés par l'app) : PILOTE_DEPLIER=ventes ouvre un domaine pour les captures, PILOTE_DEFILER=pilote y descend sans rien ouvrir, PILOTE_TOUT_VOIR=1 montre tout « À toi » ;
    /// PILOTE_MESURE_DEPLIAGE=1 déplie chaque domaine puis ouvre une page et revient, 4 fois, avec un intervalle
    /// os_signpost par geste (du changement d'état au rendu du cadre suivant), pour Instruments.
    private func essais() async {
        let env = ProcessInfo.processInfo.environment
        // Essais d'une copie seulement (PILOTE_BASE) : un vrai envoi « Écrire à » vers la session nommée (jamais sans son
        // accord), par le même chemin que le bouton. Capture en sombre : lancer avec `--args -apparence sombre` (domaine
        // des arguments, rien n'est écrit dans les réglages de Sacha) ; NSApp.appearance ne marche pas, preferredColorScheme
        // de PiloteApp l'écrase.
        if env["PILOTE_BASE"] != nil, let t = env["PILOTE_ESSAI_ECRIRE"], !t.isEmpty,
           let session = env["PILOTE_ESSAI_ECRIRE_SESSION"], session.hasPrefix("local_") {
            let fichier = env["PILOTE_DUMP_ATOI"].map { $0 + ".ecrire" }
            do {
                // Un essai ne signe jamais « Sacha » (09/11, Organisation) : il porte le nom de qui l'a lancé.
                let qui = env["PILOTE_ESSAI_ECRIRE_QUI"].flatMap { $0.isEmpty || $0 == "\(Moi.nom)" ? nil : $0 } ?? "Essai d'une session (pas \(Moi.nom))"
                try EcrireAgent.envoyer(etat, a: env["PILOTE_ESSAI_ECRIRE_NOM"] ?? "Organisation", session: session,
                                        sujet: env["PILOTE_ESSAI_ECRIRE_SUJET"], texte: t, qui: qui)
                if let f = fichier { try? "parti \(Date())\n".write(toFile: f, atomically: true, encoding: .utf8) }
            } catch {
                if let f = fichier { try? "erreur \(error)\n".write(toFile: f, atomically: true, encoding: .utf8) }
            }
        }
        if let d = env["PILOTE_DEPLIER"].flatMap(Domaine.depuis) {
            while !tableau.charge { try? await Task.sleep(for: .milliseconds(50)) }
            deplie = d
            try? await Task.sleep(for: .milliseconds(300))
            cibleDefilement = "domaine:\(d.rawValue)"; remonter += 1
        }
        // PILOTE_DEFILER=pilote : l'écran fermé, descendu jusqu'à ce domaine (en bas), pour une capture qui le montre.
        if let d = env["PILOTE_DEFILER"].flatMap(Domaine.depuis) {
            while !tableau.charge { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(600))
            ancreDefilement = .bottom
            cibleDefilement = "domaine:\(d.rawValue)"; remonter += 1
        }
        if env["PILOTE_TOUT_VOIR"] == "1" { tousLesGestes = true }
        if Demo.actif, let d = env["PILOTE_CAPTURES"], !d.isEmpty, let nom = env["PILOTE_SCENARIO"], !nom.isEmpty {
            while !tableau.charge || !etat.premiereLecture || !agenda.tachesLues { try? await Task.sleep(for: .milliseconds(100)) }
            Captures.preparer()
            try? await Task.sleep(for: .seconds(1))
            await Scenario.jouer(nom, etat: etat, dans: URL(fileURLWithPath: d))
            NSApp.terminate(nil)
            return
        }
        if Demo.actif, let d = env["PILOTE_CAPTURES"], !d.isEmpty {
            while !tableau.charge || !etat.premiereLecture || !agenda.tachesLues { try? await Task.sleep(for: .milliseconds(100)) }
            let dossier = URL(fileURLWithPath: d)
            try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
            Captures.preparer()
            let suffixe = env["PILOTE_CAPTURES_SUFFIXE"] ?? ""
            for (i, page) in Captures.pages(env).enumerated() {
                etat.ecran = page
                try? await Task.sleep(for: .seconds(2))
                let n = i + 1 < 10 ? "0\(i + 1)" : "\(i + 1)"
                Captures.photographier(vers: dossier.appendingPathComponent("\(n)-\(page.rawValue)\(suffixe).png"))
            }
            NSApp.terminate(nil)
        }
        if (env["PILOTE_BASE"] != nil || Demo.actif), let page = env["PILOTE_PAGE"].flatMap({ p in Ecran.allCases.first { "\($0)" == p } }) {
            while !tableau.charge { try? await Task.sleep(for: .milliseconds(50)) }
            etat.ecran = page
        }
        if let chemin = env["PILOTE_DUMP_ATOI"], !chemin.isEmpty, env["PILOTE_BASE"] != nil {
            while !tableau.charge || !etat.premiereLecture || !agenda.tachesLues { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .seconds(3))
            let s = SourcesATOI(etat: etat, agenda: agenda, tableau: tableau, maintenant: Date())
            let brut = GesteSacha.du(s)
            let lignes = GesteSacha.grouper(brut)
            var texte = "lignes \(lignes.count) · gestes \(lignes.reduce(0) { $0 + $1.gestes.count })\n"
            for g in brut {
                texte += "\(g.urgence)\t\(g.id)\t\(g.verbe) · \(g.objet)\t\(g.contexte)\t[\(g.bouton)]\(g.choix.isEmpty ? "" : " choix: " + g.choix.joined(separator: " | "))\n"
            }
            for r in s.rappelsDemain { texte += "demain\t\(r.liste)\t\(r.titre)\n" }
            // Les domaines tels qu'à l'écran : qui, pastille, bilan, sections et leurs lignes.
            for d in tableau.domaines {
                texte += "\n## \(d.domaine.titre) · \(d.qui)\n"
                texte += "pastille: " + d.pastilles.map { "\($0.texte) [\($0.ton)\($0.geste.map { " → " + $0 } ?? "")]" }.joined(separator: " | ") + "\n"
                texte += "bilan: \(d.bilanTexte)\n"
                for sec in d.sections {
                    texte += "### \(sec.titre) \(sec.elements.count)\n"
                    for el in sec.elements { texte += "- \(el.titre) — \(el.detail)\(el.geste.map { " → " + $0 } ?? "")\n" }
                }
            }
            let manque = ControleATOI.manquants(s, lignes: lignes, masques: [])
            texte += "manquants \(manque.count)\n" + manque.joined(separator: "\n") + "\n"
            if env["PILOTE_DUMP_RAPPELS"] == "1" {
                let f = DateFormatter(); f.dateFormat = "dd/MM HH:mm"
                for t in agenda.taches.sorted(by: { ($0.echeance ?? .distantFuture) < ($1.echeance ?? .distantFuture) }) {
                    texte += "tache\t\(t.id)\t\(t.liste)\t\(t.echeance.map(f.string) ?? "-")\t\(t.faite ? "faite \(t.faiteLe.map(f.string) ?? "")" : "à faire")\t\(t.titre.prefix(60))\n"
                    if t.liste == TravailAgents.liste {
                        let a = TravailAgents.lire(id: t.id, titre: t.titre, notes: t.notes, faite: t.faite, faiteLe: t.faiteLe)
                        texte += "agent\t\(a.domaine?.agent ?? "SANS DOMAINE")\t\(a.prevu.map(f.string) ?? "SANS HEURE")\t"
                            + (a.domaine == nil ? String(t.notes.suffix(110)).replacingOccurrences(of: "\n", with: " ") : "") + "\n"
                    }
                }
            }
            try? texte.write(toFile: chemin, atomically: true, encoding: .utf8)
        }
        guard env["PILOTE_MESURE_DEPLIAGE"] == "1" else { return }
        while !tableau.charge || !etat.premiereLecture { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .seconds(2))
        for _ in 0..<4 {
            for d in Domaine.allCases {
                await Self.mesurer("Dépliage") { deplie = d }
                try? await Task.sleep(for: .milliseconds(400))
            }
            await Self.mesurer("Dépliage") { deplie = nil }
            try? await Task.sleep(for: .milliseconds(400))
            await Self.mesurer("Ouvrir une page") { etat.ecran = .prospects }
            try? await Task.sleep(for: .milliseconds(600))
            await Self.mesurer("Retour à l'accueil") { etat.ecran = .aujourdhui }
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    /// Un intervalle « geste → cadre suivant affiché » : il se ferme quand la transaction Core Animation qui porte le
    /// changement est validée (sans animation, pour mesurer la réponse et pas la durée du ressort).
    private static func mesurer(_ nom: StaticString, _ geste: () -> Void) async {
        let id = Mesure.signposter.makeSignpostID()
        let etat = Mesure.signposter.beginInterval(nom, id: id)
        await withCheckedContinuation { (fin: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                Mesure.signposter.endInterval(nom, etat)
                fin.resume()
            }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t, geste)
            CATransaction.commit()
        }
    }

    private var papiersLisibles: Bool { agenda.accesRappels == .accorde && agenda.tachesLues }

    // MARK: En-tête

    private var enTete: some View {
        HStack(alignment: .center) {
            Text(Loc.date(Date(), "EEEEdMMMM").capitalizedPremiere)
                .font(.titrePage).kerning(-0.5).foregroundStyle(Color.texte)
            Spacer()
            if tableau.miseAJour || (etat.premiereLecture && !tableau.charge) {
                Text("Mise à jour…").font(.petit).foregroundStyle(Color.texte3)
            }
            Button { etat.rechercheOuverte = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Chercher")
                    Text("⌘K").font(.petit.weight(.medium)).foregroundStyle(Color.texte3)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.texte3.opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .font(.secondaire).foregroundStyle(Color.texte2)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.separateur, lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Chercher partout et ouvrir les autres pages : contacts, planning, publications, agents, stats")
        }
    }

    /// Le contrôle « aucun oubli » (09/11) : Rappels ou Calendrier pas accessibles, ou une chose attendue que « À toi » ne montre pas.
    private func alerteControle(_ s: SourcesATOI, _ lignes: [GesteSacha]) -> [String] {
        var a: [String] = []
        if agenda.accesRappels == .refuse {
            a.append(L("Pilote n'a pas accès à Rappels : tes tâches et décisions ne peuvent pas s'afficher. Réglages Système, Confidentialité, Rappels."))
        }
        if agenda.accesCalendrier == .refuse {
            a.append(L("Pilote n'a pas accès au Calendrier : tes rendez-vous ne peuvent pas s'afficher. Réglages Système, Confidentialité, Calendriers."))
        }
        guard etat.premiereLecture else { return a }
        if let e = ControleATOI.alerte(ControleATOI.manquants(s, lignes: lignes, masques: masques)) { a.append(e) }
        return a
    }

    private func alertes(_ controle: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(controle, id: \.self) { c in
                Label(c, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.rouge)
            }
            if let e = etat.erreurBase {
                Label(e, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.rouge)
            }
            if let e = etat.erreurSynchro {
                Label("Synchro avec l'admin KRYVA : \(e)", systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.rouge)
            }
            ForEach(etat.arrets, id: \.self) { a in
                Label(a, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.rouge)
            }
        }
        .font(.secondaire)
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rouge.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: À toi

    /// Lignes de « À toi » visibles sans clic.
    static let sansClic = 12

    private func blocATOI(_ tous: [GesteSacha]) -> some View {
        // 09/11 (Organisation) : jusqu'à 12 lignes, tout se voit sans clic ; « Voir tout » seulement au-delà.
        let replie = tous.count > Self.sansClic && !tousLesGestes
        let montres = replie ? Array(tous.prefix(3)) : tous
        // Le nombre = les gestes (un groupe « 5 messages » en compte 5 ; la ligne « Demain » aucun).
        let nombre = tous.reduce(0) { $0 + $1.gestes.count }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("À toi").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.texte)
                if nombre > 0 { Text("\(nombre)").font(.ligne).foregroundStyle(Color.texte2) }
            }
            VStack(spacing: 0) {
                if !etat.premiereLecture {
                    ForEach(0..<3, id: \.self) { i in LigneSquelette(dernier: i == 2) }
                } else if nombre == 0 && tous.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vert)
                        Text("Rien ne t'attend. Les domaines ci-dessous disent où en est chaque chose.")
                            .font(.secondaire).foregroundStyle(Color.texte2)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(montres.enumerated()), id: \.element.id) { i, g in
                        LigneGeste(geste: g, principal: i == 0, ouvert: gesteOuvert == g.id,
                                   dernier: i == montres.count - 1 && tous.count <= Self.sansClic,
                                   basculer: { withAnimation(ressort) { gesteOuvert = gesteOuvert == g.id ? nil : g.id } },
                                   agir: { agir(g) }, agirSur: { agir($0) }, choisir: { choisir(g, $0) })
                            .transition(.opacity)
                    }
                    if tous.count > Self.sansClic {
                        Button {
                            withAnimation(ressort) { tousLesGestes.toggle() }
                        } label: {
                            Text(tousLesGestes ? L("Voir moins") : L("Voir tout"))   // le nombre est déjà dans le titre (09/11)
                                .font(.secondaire.weight(.medium)).foregroundStyle(Color.actionTexte)
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let e = erreurGeste {
                EtatErreur(texte: e) { erreurGeste = nil }
            }
        }
    }

    /// Le geste du bouton, jusqu'au bout (09/11 : « que je puisse tout faire en un clic »). Ceux qui changent quelque chose
    /// partent après 5 s, sauf « Annuler » ; la ligne disparaît tout de suite. Seuls les choix libres déplient la ligne.
    private func agir(_ g: GesteSacha) {
        switch g.action {
        case .validerTexte(let m):
            differer(g, libelle: L("Texte validé pour \(m.contact.nomAffiche)")) { etat.valider(m, texte: m.evenement.texte) }
        case .mettreEnFile(let m):
            differer(g, libelle: L("Mail pour \(m.contact.nomAffiche) mis dans la file d'envoi")) {
                Task { if let e = await etat.mettreEnFile([m.id]) { echec(g, e) } }
            }
        case .marquerEnvoye(let m):
            differer(g, libelle: L("Marqué envoyé : \(m.contact.nomAffiche)")) {
                if let e = etat.marquer(m.id, statut: "envoye") { echec(g, e) }
            }
        case .cocherRappel(let r):
            differer(g, libelle: L("Fait : \(g.objet)")) {
                if let e = agenda.terminer(rappel: r) { echec(g, e) }
            }
        case .prospectFait(let c):
            differer(g, libelle: L("Fait : \(g.contexte)")) { etat.actionFaite(c) }
        case .tiktokPubliee(let p):
            differer(g, libelle: L("Publiée sur TikTok : \(g.objet)")) {
                guard let stock = etat.stock else { return echec(g, L("La base de Pilote n'est pas ouverte.")) }
                do { try Publications.marquerPubliee(stock, id: p.id, par: "\(Moi.nom) (app)") } catch { echec(g, "\(error)") }
            }
        case .validerPublication(let p):
            differer(g, libelle: L("Publication validée : \(g.objet)")) {
                guard let stock = etat.stock else { return echec(g, L("La base de Pilote n'est pas ouverte.")) }
                do { try Publications.valider(stock, id: p.id, empreinte: p.empreinte, par: "\(Moi.nom) (app)") } catch { echec(g, "\(error)") }
            }
        case .videoFaite(let v, let action):
            differer(g, libelle: action == "tourner" ? L("Tournée : \(v.sujet)") : L("Publiée : \(v.sujet)")) {
                etat.marquerVideoJournee(jour: v.jour, compte: v.compte, action: action, fait: true)
            }
        case .choisir(let o):
            choisir(g, o)
        case .ouvrir(let u):
            NSWorkspace.shared.open(u)
        case .envoyerReponses(let rangs):
            differer(g, libelle: L("\(rangs.count) réponses envoyées")) {
                etat.envoyerReponses(rangs.filter { $0 >= 0 })   // rangs < 0 : réponses factices d'essai, rien ne part
            }
        case .deplier:
            withAnimation(ressort) { gesteOuvert = gesteOuvert == g.id ? nil : g.id }
        case .aucune:
            break
        }
    }

    /// Un choix posé sur la ligne d'une décision ❓ ou d'une question de session : noté, puis transmis (comme sur la carte).
    private func choisir(_ g: GesteSacha, _ o: String) {
        switch g.genre {
        case .decision(let r):
            differer(g, libelle: L("Choix noté : \(Sessions.libelleChoix(o))")) {
                do {
                    try Decisions.noter(question: Decisions.question(r.titre), choix: o, ref: r.id, liste: r.liste,
                                        pour: Decisions.pour(liste: r.liste, notes: r.notes))
                } catch { return echec(g, L("Le choix n'a pas pu être transmis : \(error.localizedDescription)")) }
                etat.relireDecisions()
                agenda.trancher(r, choix: o)
            }
        case .question(let q):
            differer(g, libelle: L("Réponse notée pour \(q.nom) : \(Sessions.libelleChoix(o))")) {
                do {
                    try Decisions.noter(question: q.activite.question, choix: o, ref: q.activite.questionRef, liste: "Sessions",
                                        pour: q.nom, session: q.activite.sessionApp)
                } catch { return echec(g, L("Pas noté : \(error.localizedDescription)")) }
                etat.relireDecisions()
            }
        default:
            break
        }
    }

    /// Le geste n'a pas abouti : la ligne revient, avec l'erreur.
    private func echec(_ g: GesteSacha, _ e: String) {
        erreurGeste = e
        withAnimation(ressort) { _ = masques.remove(g.id) }
    }

    private func differer(_ g: GesteSacha, libelle: String, faire: @escaping @MainActor () -> Void) {
        if let avant = enAttente {     // un seul « Annuler » à la fois : le geste d'avant part tout de suite
            avant.tache.cancel()
            avant.faire()
        }
        erreurGeste = nil
        withAnimation(ressort) { _ = masques.insert(g.id); if gesteOuvert == g.id { gesteOuvert = nil } }
        let tache = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Scenario.annulation))   // 5 s ; 1,5 s pendant une démo animée
            guard !Task.isCancelled else { return }
            faire()
            if enAttente?.id == g.id { withAnimation(.easeOut(duration: 0.2)) { enAttente = nil } }
        }
        withAnimation(.easeOut(duration: 0.2)) { enAttente = Attente(id: g.id, libelle: libelle, tache: tache, faire: faire) }
    }

    private func annuler() {
        guard let a = enAttente else { return }
        a.tache.cancel()
        withAnimation(ressort) {
            masques.remove(a.id)
            enAttente = nil
        }
    }

    @ViewBuilder private var toast: some View {
        if let a = enAttente {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.vert)
                Text(a.libelle).font(.secondaire).foregroundStyle(Color.texte).lineLimit(1)
                Button("Annuler", action: annuler)
                    .buttonStyle(.plain).font(.secondaire.weight(.semibold)).foregroundStyle(Color.actionTexte)
                    .keyboardShortcut("z", modifiers: .command)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color.eleve, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.separateur, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .padding(.bottom, 24)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Domaines

    /// La pastille « Pour toi : … » ouvre la ligne qui porte ce geste (seule ou dans un groupe) et y remonte.
    private func ouvrirGeste(_ id: String) {
        let s = SourcesATOI(etat: etat, agenda: agenda, tableau: tableau, maintenant: Date())
        let lignes = GesteSacha.grouper(GesteSacha.du(s).filter { !masques.contains($0.id) })
        let cible = lignes.first { $0.id == id || $0.gestes.contains { $0.id == id } }
        withAnimation(ressort) {
            if let c = cible {
                gesteOuvert = c.id
                if let i = lignes.firstIndex(where: { $0.id == c.id }), i >= 3, lignes.count > Self.sansClic { tousLesGestes = true }
            }
        }
        ancreDefilement = .top
        cibleDefilement = "atoi"; remonter += 1
    }

    private var blocDomaines: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Où en est chaque domaine").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.texte)
            VStack(spacing: 0) {
                if let e = tableau.erreur, !tableau.charge {
                    EtatErreur(texte: L("Impossible de charger les domaines : \(e)")) { tableau.reessayer() }
                } else if !tableau.charge {
                    ForEach(Domaine.allCases) { d in LigneSquelette(titre: d.titre, dernier: d == .pilote) }
                } else {
                    ForEach(tableau.domaines) { d in
                        LigneDomaine(etat: d, deplie: deplie == d.domaine, dernier: d.domaine == tableau.domaines.last?.domaine,
                                     ouvrirGeste: ouvrirGeste) {
                            withAnimation(ressort) { deplie = deplie == d.domaine ? nil : d.domaine }
                        }
                        .id("domaine:\(d.domaine.rawValue)")
                    }
                }
            }
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Une ligne de « À toi »

struct LigneGeste: View {
    @Environment(Etat.self) private var etat
    let geste: GesteSacha
    let principal: Bool
    let ouvert: Bool
    let dernier: Bool
    let basculer: () -> Void
    let agir: () -> Void
    /// Le bouton d'un geste de la liste ouverte (ligne « 28 messages à envoyer »).
    var agirSur: (GesteSacha) -> Void = { _ in }
    /// Un choix posé sur la ligne (décision ❓, question d'une session).
    var choisir: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: geste.symbole)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.actionTexte)
                    .frame(width: 32, height: 32)
                    .background(Color.action.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    (Text(geste.verbe).foregroundStyle(geste.retard ? Color.rouge : Color.texte2) + Text(" · ").foregroundStyle(Color.texte3)
                        + Text(geste.objet.sansTiretLong).foregroundStyle(Color.texte))
                        .font(.ligneForte).lineLimit(1)
                    if !geste.contexte.isEmpty {
                        Text(geste.contexte.sansTiretLong).font(.secondaire)
                            .foregroundStyle(geste.bloque ? Color.rouge : Color.texte2).lineLimit(1)
                    }
                    if !geste.choix.isEmpty {
                        // Les choix sur la ligne : un clic tranche (5 s pour annuler) ; « Autre… » ouvre la carte entière.
                        HStack(spacing: 6) {
                            ForEach(Array(geste.choix.enumerated()), id: \.offset) { i, o in
                                Button { choisir(o) } label: {
                                    Text(Sessions.libelleChoix(o)).font(.secondaire.weight(.semibold)).lineLimit(1)
                                        .foregroundStyle(principal && i == 0 ? Color.white : Color.actionTexte)
                                        .padding(.horizontal, 12).padding(.vertical, 5)
                                        .background(principal && i == 0 ? Color.action : Color.action.opacity(0.10),
                                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain).help(Sessions.libelleChoix(o))
                                .repere("choix:\(o)")
                            }
                            Button("Autre…", action: basculer).buttonStyle(.plain)
                                .font(.secondaire).foregroundStyle(Color.texte2)
                                .help("Voir tout le contexte, ou écrire une autre réponse")
                        }
                        .padding(.top, 6)
                    }
                }
                Spacer(minLength: 12)
                if !geste.bouton.isEmpty {
                    Button(action: agir) {
                        Text(geste.bouton).font(.secondaire.weight(.semibold))
                            .foregroundStyle(principal ? Color.white : Color.actionTexte)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(principal ? Color.action : Color.action.opacity(0.10),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .repere("geste:\(geste.bouton)")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .onTapGesture(perform: basculer)
            if ouvert {
                Group {
                    if case .groupe(let liste) = geste.genre {
                        VStack(spacing: 0) {
                            ForEach(liste) { g in LigneSousGeste(geste: g, agir: { agirSur(g) }) }
                        }
                        .padding(.leading, 44)
                    } else {
                        DetailGeste(geste: geste)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
                .transition(.opacity)
            }
            if !dernier { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 60) }
        }
    }
}

/// Ce qui s'ouvre sous un geste : le texte à valider, le message à envoyer, la décision, la question.
struct DetailGeste: View {
    @Environment(Etat.self) private var etat
    let geste: GesteSacha

    var body: some View {
        switch geste.genre {
        case .texte(let m): CarteTexte(message: m)
        case .envoiMail(let m), .envoi(let m): LigneAEnvoyer(message: m)
        case .decision(let r): CarteDecision(rappel: r)
        case .question(let q): CarteQuestionSession(activite: q.activite, nom: q.nom)
        case .seance: CarteSeanceDimanche()
        case .demain(let l):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(l) { r in
                    HStack(spacing: 8) {
                        Text(r.avecHeure ? r.echeance.map(GesteSacha.heure) ?? "" : "")
                            .font(.petit.monospacedDigit()).foregroundStyle(Color.texte3).frame(width: 40, alignment: .leading)
                        Text(GesteSacha.sansSacha(r.titre).sansTiretLong).font(.secondaire).foregroundStyle(Color.texte).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(ATOI.domaine(r.liste)).font(.petit).foregroundStyle(Color.texte3)
                    }
                }
            }
            .padding(.leading, 44)
        case .tourner(let v):
            HStack(spacing: 8) {
                if !v.prompteur.isEmpty { Button("Ouvrir le prompteur") { etat.ouvrirChemin(v.prompteur) } }
                if !v.fiche.isEmpty { Button("Lire la fiche") { etat.ouvrirChemin(v.fiche) } }
            }
            .buttonStyle(.bordered).controlSize(.small).padding(.leading, 44)
        case .reponses(let l):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(l) { d in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(d.heure).font(.petit.monospacedDigit()).foregroundStyle(Color.texte3).frame(width: 40, alignment: .leading)
                        Text("\(d.question) → \(Sessions.libelleChoix(d.choix))").font(.secondaire).foregroundStyle(Color.texte).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("pour \(d.pour)").font(.petit).foregroundStyle(Color.texte3).fixedSize()
                        Button { etat.retirerReponse(d.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless).foregroundStyle(Color.texte3)
                            .help("Ne pas l'envoyer : \(d.pour) ne l'apprendra pas")
                    }
                    .help("\(d.question)\n→ \(Sessions.libelleChoix(d.choix))")
                }
            }
            .padding(.leading, 44)
        case .rappel(let r) where !r.notes.isEmpty:
            Text(r.notes.sansTiretLong).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(6)
                .textSelection(.enabled).padding(.leading, 44)
        default: EmptyView()
        }
    }
}

/// Un geste dans la liste ouverte d'un groupe : son nom, son contexte, son bouton ; un clic sur la ligne ouvre le détail.
struct LigneSousGeste: View {
    let geste: GesteSacha
    let agir: () -> Void
    @State private var ouvert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(geste.objet.sansTiretLong).font(.ligne).foregroundStyle(Color.texte).lineLimit(1)
                    if !geste.contexte.isEmpty {
                        Text(geste.contexte.sansTiretLong).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button(action: agir) {
                    Text(geste.bouton).font(.secondaire.weight(.semibold)).foregroundStyle(Color.actionTexte)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.action.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .contentShape(Rectangle())
            .onTapGesture { ouvert.toggle() }
            if ouvert { DetailGeste(geste: geste) }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Une ligne de domaine

struct LigneDomaine: View {
    @Environment(Etat.self) private var etat
    let etat_: EtatDomaine
    let deplie: Bool
    let dernier: Bool
    let basculer: () -> Void
    var ouvrirGeste: (String) -> Void = { _ in }
    /// Qui on relance : l'agent du domaine, ou PILOTE quand une carte l'attend (09/11) ; nil = rien d'ouvert.
    @State private var relancer: Domaine? = nil

    init(etat: EtatDomaine, deplie: Bool, dernier: Bool, ouvrirGeste: @escaping (String) -> Void = { _ in },
         basculer: @escaping () -> Void) {
        self.etat_ = etat; self.deplie = deplie; self.dernier = dernier; self.ouvrirGeste = ouvrirGeste; self.basculer = basculer
    }

    private var gris: Bool { etat_.rienDeNeuf && etat_.erreur == nil }

    private func basculerRelance(_ cible: Domaine) {
        withAnimation(.snappy) { relancer = relancer == cible ? nil : cible }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // 09/11 (Sacha : « est-ce que les agents sont au courant ? est-ce qu'ils travaillent ? ») : qui tient le domaine.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(etat_.domaine.titre).font(.titreSection)
                        .foregroundStyle(gris ? Color.texte2 : Color.texte)
                        .layoutPriority(1)
                        .repere("domaine:\(etat_.domaine.rawValue)")
                    if !etat_.qui.isEmpty {
                        HStack(spacing: 5) {
                            Circle().fill(PastilleDomaine.couleur(etat_.quiTon)).frame(width: 6, height: 6)
                            Text(etat_.qui.sansTiretLong).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .help(etat_.qui)
                    }
                    // 09/11 (Organisation) : du travail attend et l'agent ne travaille pas : le relancer, texte pré-rempli.
                    if etat_.relance != nil {
                        Button { basculerRelance(etat_.domaine) } label: {
                            Label("Relancer \(etat_.domaine.agent)", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Écrire à \(etat_.domaine.agent) avec un texte déjà rempli, à relire avant d'envoyer")
                    }
                    // 09/11 (Organisation) : une carte attend PILOTE : le relancer, lui.
                    if etat_.relancePilote != nil {
                        Button { basculerRelance(.pilote) } label: {
                            Label("Relancer PILOTE", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Écrire à PILOTE avec un texte déjà rempli, à relire avant d'envoyer")
                    }
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.texte3)
                        .rotationEffect(.degrees(deplie ? 90 : 0))
                }
                if etat_.erreur != nil {
                    PastilleDomaine(texte: L("lecture impossible"), ton: .rouge)
                } else {
                    // 09/11 : la pastille dit le geste de Sacha (ou « Rien à faire pour toi ») ; le bilan, le travail des agents,
                    // avec les mots et les nombres des sections dépliées.
                    Rangee(espace: 6) {
                        ForEach(etat_.pastilles, id: \.self) { p in
                            if let g = p.geste {
                                Button { ouvrirGeste(g) } label: { PastilleDomaine(texte: p.texte, ton: p.ton, lien: true) }
                                    .buttonStyle(.plain).help("Voir la ligne dans À toi")
                            } else {
                                PastilleDomaine(texte: p.texte, ton: p.ton)
                            }
                        }
                    }
                    if !etat_.bilan.isEmpty {
                        Self.bilan(etat_.bilan).font(.secondaire).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .onTapGesture(perform: basculer)
            if let cible = relancer, let r = cible == .pilote ? etat_.relancePilote : etat_.relance {
                EcrireAgent(domaine: cible, sujet: nil, enLigne: true, initial: r) { withAnimation(.snappy) { relancer = nil } }
                    .id(cible)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            if deplie {
                contenu.transition(.opacity)
            }
            if !dernier { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 16) }
        }
    }

    /// Le bilan en couleur : rouge pour un problème, vert pour ce qui avance ou est fait, gris pour le reste.
    static func bilan(_ l: [PastilleStatut]) -> Text {
        l.enumerated().reduce(Text("")) { t, e in
            let c: Color = e.element.ton == .rouge ? .rouge : (e.element.ton == .vert ? .vert : .texte2)
            return t + (e.offset == 0 ? Text("") : Text(" · ").foregroundStyle(Color.texte3)) + Text(e.element.texte).foregroundStyle(c)
        }
    }

    /// Dépliée (09/11) : Problème, Pour toi, En cours, À faire par X, Prêt…, Fait aujourd'hui, Fait ces 7 derniers jours ;
    /// les mêmes mots et les mêmes nombres que la ligne fermée, une chose par ligne.
    @ViewBuilder private var contenu: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let e = etat_.erreur {
                EtatErreur(texte: e)
            }
            EcrireAgent(domaine: etat_.domaine, sujet: nil)
            if etat_.total == 0 && etat_.erreur == nil {
                Text("Rien pour l'instant.").font(.secondaire).foregroundStyle(Color.texte2)
            }
            ForEach(etat_.sections) { sec in
                GroupeDeplie(titre: sec.titre, elements: sec.elements, domaine: etat_.domaine, ton: sec.ton, ouvrirGeste: ouvrirGeste)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 14).padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GroupeDeplie: View {
    let titre: String
    let elements: [ElementDomaine]
    let domaine: Domaine
    var ton: TonStatut = .gris
    var ouvrirGeste: (String) -> Void = { _ in }
    @State private var tout = false

    var body: some View {
        let montres = tout ? elements : Array(elements.prefix(5))
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(titre).font(.petit.weight(.semibold)).foregroundStyle(ton == .rouge ? Color.rouge : Color.texte2)
                Text("\(elements.count)").font(.petit).foregroundStyle(Color.texte3)
            }
            ForEach(montres) { e in
                LigneElement(element: e, domaine: domaine, ouvrirGeste: ouvrirGeste)
            }
            if elements.count > 5 {
                Button(tout ? L("Voir moins") : L("Voir tout (\(elements.count))")) { tout.toggle() }
                    .buttonStyle(.plain).font(.secondaire.weight(.medium)).foregroundStyle(Color.actionTexte)
                    .padding(.leading, 16).padding(.top, 2)
            }
        }
    }
}

/// « Écrire à App » : le texte part à la session du domaine par le Facteur (la veille sinon). Sur une ligne, il dit de quoi.
struct EcrireAgent: View {
    @Environment(Etat.self) private var etat
    let domaine: Domaine
    let sujet: String?
    /// Sous une ligne (09/11) : le champ est ouvert d'emblée, sans le bouton « Écrire à ».
    var enLigne = false
    /// Le texte de départ (bouton « Relancer X ») : Sacha le relit et l'envoie lui-même.
    var initial = ""
    var fini: () -> Void = {}
    @State private var ouvert = false
    @State private var texte = ""
    @State private var parti: String?
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if !enLigne {
                    Button { withAnimation(.snappy) { ouvert.toggle() } } label: {
                        Label("Écrire à \(domaine.agent)", systemImage: "paperplane")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Le message part à la session \(domaine.equipe) par le Facteur")
                    .repere("ecrire:\(domaine.rawValue)")
                }
                if let parti { Text(parti).font(.petit).foregroundStyle(Color.vert) }
            }
            if ouvert || (enLigne && parti == nil) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(sujet.map { L("À \(domaine.agent), à propos de « \(Domaines.court($0, 60)) »") } ?? L("Ton message à \(domaine.agent)"),
                              text: $texte, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...4)
                        .onSubmit(envoyer)
                        .onAppear { if texte.isEmpty && !initial.isEmpty { texte = initial } }
                        .repere("champ:\(domaine.rawValue)")
                    Button("Envoyer", action: envoyer)
                        .buttonStyle(.borderedProminent).tint(.action).controlSize(.small)
                        .disabled(texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .repere("envoyer:\(domaine.rawValue)")
                }
            }
            if let erreur { Text(erreur).font(.petit).foregroundStyle(Color.rouge) }
        }
    }

    private func envoyer() {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        do {
            try Self.envoyer(etat, a: domaine.equipe, sujet: sujet, texte: t, qui: "\(Moi.nom)")
            parti = L("Parti pour \(domaine.agent)")
            erreur = nil
            texte = ""
            withAnimation(.snappy) { ouvert = false }
            if enLigne { Task { try? await Task.sleep(for: .seconds(3)); fini() } }
        } catch is Demo.Refus {
            // Mode démo : rien ne part, mais le geste se voit en entier (GIF du README).
            parti = "Mode démo : rien ne part. En vrai, il part à \(domaine.agent)."
            erreur = nil
            texte = ""
            withAnimation(.snappy) { ouvert = false }
        } catch {
            erreur = L("Pas parti : \(error.localizedDescription)")
        }
    }
}

extension EcrireAgent {
    /// Le chemin du bouton (et de l'essai PILOTE_ESSAI_ECRIRE) : le texte, avec la ligne dont il parle, part par le Facteur.
    @MainActor
    static func envoyer(_ etat: Etat, a nom: String, session: String = "", sujet: String?, texte: String, qui: String) throws {
        if Demo.actif { throw Demo.Refus() }
        try etat.ecrire(a: nom, session: session, texte: sujet.map { "À propos de « \($0) » : \(texte)" } ?? texte, qui: qui)
    }
}

/// Des éléments posés en ligne, qui passent à la ligne quand la place manque.
struct Rangee: Layout {
    var espace: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > largeur { x = 0; y += ligne + espace; ligne = 0 }
            x += t.width + espace; ligne = max(ligne, t.height); maxX = max(maxX, x - espace)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + ligne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, ligne: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + t.width > bounds.maxX { x = bounds.minX; y += ligne + espace; ligne = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + espace; ligne = max(ligne, t.height)
        }
    }
}

struct LigneElement: View {
    @Environment(Etat.self) private var etat
    let element: ElementDomaine
    var domaine: Domaine? = nil
    var ouvrirGeste: (String) -> Void = { _ in }
    @State private var ecrire = false

    private var ouvrable: Bool { element.geste != nil || element.contactId != nil || !element.lien.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ligne
            // 09/11 : l'avion ouvre le champ sous la ligne ; le message dit de quelle ligne il parle.
            if ecrire, let d = domaine {
                EcrireAgent(domaine: d, sujet: element.titre, enLigne: true) { withAnimation(.snappy) { ecrire = false } }
                    .padding(.leading, 16)
            }
        }
    }

    private var ligne: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(PastilleDomaine.couleur(element.ton)).frame(width: 6, height: 6).offset(y: -2)
            VStack(alignment: .leading, spacing: 1) {
                Text(element.titre.sansTiretLong).font(.ligne).foregroundStyle(Color.texte).lineLimit(2)
                if !element.detail.isEmpty {
                    Text(element.detail.sansTiretLong).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if !element.agent.isEmpty, let d = domaine {
                Button { withAnimation(.snappy) { ecrire.toggle() } } label: { Image(systemName: "paperplane") }
                    .buttonStyle(.borderless).foregroundStyle(Color.actionTexte)
                    .help("Écrire à \(d.agent) à propos de cette ligne").accessibilityLabel("Écrire à \(d.agent)")
            }
            if ouvrable {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.texte3)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if let g = element.geste { ouvrirGeste(g) }
            else if let id = element.contactId { etat.fichePanneau = id }
            else if element.lien.hasPrefix("http"), let u = URL(string: element.lien) { NSWorkspace.shared.open(u) }
            else if !element.lien.isEmpty { etat.montrer(element.lien) }
        }
    }
}

/// Pastille de statut : 22 px de haut, point de 6 px, texte 12 semibold, fond teinté (charte).
struct PastilleDomaine: View {
    let texte: String
    let ton: TonStatut
    /// Renvoie à « À toi » : une flèche le dit.
    var lien = false

    static func couleur(_ t: TonStatut) -> Color {
        switch t {
        case .vert: return .vert
        case .ambre: return .ambre
        case .rouge: return .rouge
        case .gris: return .texte3
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Self.couleur(ton)).frame(width: 6, height: 6)
            Text(texte).font(.petit.weight(.semibold)).foregroundStyle(Self.couleur(ton))
            if lien { Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold)).foregroundStyle(Self.couleur(ton)) }
        }
        .padding(.horizontal, 8).frame(height: 22)
        .background(Self.couleur(ton).opacity(0.14), in: Capsule())
    }
}

/// Squelette sur l'arrivée (charte : jamais une roue seule, jamais un faux vide).
struct LigneSquelette: View {
    var titre: String? = nil
    var dernier = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let titre {
                    Text(titre).font(.titreSection).foregroundStyle(Color.texte3)
                    Spacer()
                    Capsule().fill(Color.texte3.opacity(0.14)).frame(width: 80, height: 22)
                } else {
                    Circle().fill(Color.texte3.opacity(0.14)).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.texte3.opacity(0.16)).frame(width: 220, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Color.texte3.opacity(0.10)).frame(width: 320, height: 10)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 52)
            if !dernier { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 16) }
        }
    }
}

extension String {
    var capitalizedPremiere: String { prefix(1).uppercased() + dropFirst() }
    /// Charte : pas de tiret long à l'écran, même quand il vient des données (noms de contacts, prochaines actions).
    var sansTiretLong: String { replacingOccurrences(of: " — ", with: " · ").replacingOccurrences(of: "—", with: "-") }
}
