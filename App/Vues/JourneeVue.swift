// « Ma journée » (brief de 7 h) et « Séance du dimanche » : la logique est dans Shared/MaJournee.swift et
// Shared/SeanceDimanche.swift ; ici, ce que l'app a déjà lu, et les deux cartes d'Aujourd'hui.
import SwiftUI

extension Etat {
    /// La journée heure par heure, avec ce que l'app a déjà lu (Calendrier, Rappels, base, décisions).
    func journee(_ agenda: Agenda, maintenant: Date = Date()) -> [ElementJournee] {
        let rdv = agenda.rendezVous.map {
            EntreeJournee(titre: $0.titre, debut: $0.debut, fin: $0.fin, avecHeure: !$0.journee, source: $0.calendrier,
                          lien: $0.url?.absoluteString ?? "", cible: $0.id, fait: agenda.estFait($0))
        }
        // Les tâches faites restent dans la journée, en gris.
        let taches = agenda.taches.compactMap { t -> EntreeJournee? in
            guard let e = t.echeance else { return nil }
            return EntreeJournee(titre: t.titre, debut: e, avecHeure: t.avecHeure, source: t.liste, lien: t.lienNotion?.absoluteString ?? "",
                                 cible: t.id, fait: t.faite)
        }
        let messages = aEnvoyerAujourdhui
        return MaJournee.construire(
            aujourdhui: Dates.jour.string(from: maintenant), rendezVous: rdv, taches: taches, videos: videos,
            messagesKryva: messages.filter { $0.contact.espace == "kryva" }.count,
            messagesFreelance: messages.filter { $0.contact.espace == "freelance" }.count,
            decisions: agenda.rappels.filter { Decisions.estDecision($0.titre) }.count + questionsSessions.count)
    }
}

struct CarteJournee: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda

    @State private var aReporter: ElementJournee?
    @State private var date = Date()
    /// Afficher ou cacher ce qui est fait (04/11, Sacha : « comme dans le planning »).
    @AppStorage("journee.faits") private var montrerFaits = true

    var body: some View {
        let tout = etat.journee(agenda)
        let prevus = tout.filter { $0.genre != .cadre && !$0.fait }.count
        let faits = tout.filter(\.fait).count
        let e = montrerFaits ? tout : tout.filter { !$0.fait }
        Carte(titre: L("Ma journée"), detail: "\(DemainPret.libelleJour(Dates.aujourdhui())) · "
              + (prevus == 0 ? L("rien à faire en dehors du cadre") : L("\(prevus) choses à faire"))
              + (faits == 0 ? "" : " · " + L("\(faits) faites"))) {
            if faits > 0 {
                HStack {
                    Spacer()
                    Button { montrerFaits.toggle() } label: {
                        Label(montrerFaits ? "Cacher les faits (\(faits))" : "Afficher les faits (\(faits))",
                              systemImage: montrerFaits ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless).controlSize(.small).foregroundStyle(Color.texte2)
                    .help("Les tâches et étapes déjà faites : les montrer en gris ou les cacher")
                }
                .padding(.horizontal, 16).padding(.top, 6)
            }
            ForEach(Array(e.enumerated()), id: \.element.id) { i, el in
                LigneCarte(dernier: i == e.count - 1) { ligne(el) }
            }
            if let erreur = agenda.erreurPlanning { EtatErreur(texte: erreur).padding(.horizontal, 16).padding(.bottom, 8) }
            Text("Brief de \(MaJournee.heureBrief) h : notification du lundi au samedi (fenêtre Pilote ouverte). En gris : ce qui est fait, et la semaine type du CAP.")
                .font(.petit).foregroundStyle(Color.texte3)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .sheet(item: $aReporter) { el in feuilleReport(el) }
    }

    private func ligne(_ el: ElementJournee) -> some View {
        let gris = el.genre == .cadre || el.fait
        let agir = el.genre == .rendezVous || el.genre == .tache
        let cochable = agir || (el.genre == .video && el.cible.hasPrefix("video:"))
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(el.heure.isEmpty ? "—" : el.heure).font(.ligne.monospacedDigit())
                .foregroundStyle(gris ? Color.texte3 : Color.texte).frame(width: 46, alignment: .leading)
            if cochable {
                Button { basculer(el) } label: { Image(systemName: el.fait ? "checkmark.circle.fill" : "circle") }
                    .buttonStyle(.plain).foregroundStyle(el.fait ? Color.vert : Color.action).frame(width: 18)
                    .help(el.fait ? "Remettre à faire" : "Fait : la ligne passe en gris")
            } else {
                Image(systemName: icone(el.genre)).foregroundStyle(gris ? Color.texte3 : (el.genre == .decision ? Color.ambre : Color.action))
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(el.titre).font(el.genre == .cadre ? .secondaire : .ligne.weight(.semibold))
                    .foregroundStyle(gris ? Color.texte3 : Color.texte).strikethrough(el.fait).lineLimit(2)
                if !el.detail.isEmpty && el.genre != .cadre {
                    Text(el.detail).font(.secondaire).foregroundStyle(el.fait ? Color.texte3 : Color.texte2).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if agir && !el.fait {
                Menu {
                    ForEach(Report.allCases) { r in Button(r.libelle) { reporter(el, jour: r.jour(depuis: Date())) } }
                    Divider()
                    Button("Date précise…") { date = debut(el).map { Report.memeHeure($0, le: Report.demain.jour(depuis: Date())) } ?? Date(); aReporter = el }
                } label: { Label("Reporter", systemImage: "calendar.badge.clock") }
                .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
                .help("Reporter à un autre jour : la ligne quitte Ma journée")
            }
            if !el.lien.isEmpty {
                Button("Ouvrir") { etat.montrer(el.lien) }.controlSize(.small)
                    .help(el.lien)
            }
        }
    }

    private func feuilleReport(_ el: ElementJournee) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reporter « \(el.titre) »").font(.titreSection).foregroundStyle(Color.texte).lineLimit(2)
            DatePicker("Nouvelle date", selection: $date, in: Date()...,
                       displayedComponents: el.heure.isEmpty ? [.date] : [.date, .hourAndMinute])
                .datePickerStyle(.graphical).labelsHidden()
            HStack {
                Spacer()
                Button("Annuler") { aReporter = nil }.keyboardShortcut(.cancelAction)
                Button("Reporter") { reporter(el, precis: date); aReporter = nil }
                    .buttonStyle(.borderedProminent).tint(.action).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 340)
    }

    private func rendezVous(_ el: ElementJournee) -> RendezVous? { agenda.rendezVous.first { $0.id == el.cible } }
    private func tache(_ el: ElementJournee) -> Tache? { agenda.taches.first { $0.id == el.cible } }
    private func debut(_ el: ElementJournee) -> Date? { rendezVous(el)?.debut ?? tache(el)?.echeance }

    private func basculer(_ el: ElementJournee) {
        if el.genre == .rendezVous, let r = rendezVous(el) {
            agenda.estFait(r) ? agenda.rouvrir(r) : agenda.terminer(r)
        } else if el.genre == .tache {
            agenda.marquerFaite(el.cible, !el.fait)
        } else if el.genre == .video {
            let p = el.cible.split(separator: ":").map(String.init)      // video : jour : compte : action
            guard p.count == 4, p[0] == "video" else { return }
            etat.marquerVideoJournee(jour: p[1], compte: p[2], action: p[3], fait: !el.fait)
        }
    }

    /// Demain, après-demain, lundi : même heure, autre jour.
    private func reporter(_ el: ElementJournee, jour: Date) {
        if el.genre == .rendezVous, let r = rendezVous(el) {
            agenda.reporter(r, vers: r.journee ? Calendar.current.startOfDay(for: jour) : Report.memeHeure(r.debut, le: jour))
        } else if el.genre == .tache {
            agenda.deplacer(el.cible, vers: jour)
        }
    }

    /// Date (et heure) choisies dans la feuille.
    private func reporter(_ el: ElementJournee, precis: Date) {
        if el.genre == .rendezVous, let r = rendezVous(el) {
            agenda.reporter(r, vers: r.journee ? Calendar.current.startOfDay(for: precis) : precis)
        } else if el.genre == .tache, let t = tache(el) {
            agenda.changerEcheance(t.id, date: precis, avecHeure: t.avecHeure)
        }
    }

    private func icone(_ g: ElementJournee.Genre) -> String {
        switch g {
        case .decision: return "questionmark.circle.fill"
        case .rendezVous: return "calendar"
        case .tache: return "checklist"
        case .video: return "video.fill"
        case .prospects: return "paperplane.fill"
        case .cadre: return "clock"
        }
    }
}

/// Le samedi et le dimanche : les 10 sujets de la semaine qui vient et 1 de réserve par compte, choisis d'un clic.
struct CarteSeanceDimanche: View {
    @Environment(Etat.self) private var etat

    var body: some View {
        let aujourdhui = Dates.aujourdhui()
        let c = SeanceDimanche.creneaux(etat.videos, aujourdhui: aujourdhui)
        let faits = c.filter(\.choisi).count
        Carte(titre: L("Séance du dimanche"),
              detail: L("semaine du \(DemainPret.libelleJour(SeanceDimanche.semaine(aujourdhui).first ?? aujourdhui)) · \(faits) sur \(c.count) choisis")) {
            ForEach(Array(c.enumerated()), id: \.element.id) { i, creneau in
                LigneCarte(dernier: i == c.count - 1) { LigneSeance(creneau: creneau) }
            }
            Text("Le samedi, Réseaux propose 2 ou 3 sujets par créneau. Votre choix valide la vidéo tout de suite et part à Réseaux avec vos envois.")
                .font(.petit).foregroundStyle(Color.texte3)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        CarteIdees()
    }
}

/// La boîte à idées (IDEES.md), revue le dimanche : chaque idée part à PILOTE avec votre choix, puis ne s'affiche plus.
private struct CarteIdees: View {
    @Environment(Etat.self) private var etat
    @State private var traitees: Set<String> = []
    @State private var erreur: String?

    private var fichier: String { Identite.dossier.appendingPathComponent("IDEES.md").path }

    var body: some View {
        let toutes = SeanceDimanche.idees((try? String(contentsOfFile: fichier, encoding: .utf8)) ?? "")
        let reste = toutes.filter { !traitees.contains($0.ref) }
        Carte(titre: L("Boîte à idées"), detail: reste.isEmpty ? L("rien à trier") : L("\(reste.count) idées à trier")) {
            ForEach(Array(reste.enumerated()), id: \.element.ref) { i, idee in
                LigneCarte(dernier: i == reste.count - 1 && erreur == nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(idee.texte).font(.secondaire).foregroundStyle(Color.texte).lineLimit(4).textSelection(.enabled)
                        HStack(spacing: 8) {
                            ForEach(SeanceDimanche.choixIdee, id: \.self) { c in
                                Button(SeanceDimanche.libelleChoixIdee(c)) { trier(idee, c) }
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            if let erreur { EtatErreur(texte: erreur).padding(.horizontal, 16).padding(.bottom, 10) }
            Text("Votre choix part à PILOTE avec vos envois : il range l'idée dans la semaine, au parking du samedi, ou la retire.")
                .font(.petit).foregroundStyle(Color.texte3)
                .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .onAppear { traitees = Decisions.refsRepondues(prefixe: "idee:") }
    }

    private func trier(_ idee: (ref: String, texte: String), _ choix: String) {
        do {
            try Decisions.noter(question: "Idée : \(idee.texte)", choix: choix, ref: idee.ref, liste: "KRYVA", pour: "PILOTE")
            traitees.insert(idee.ref)
            erreur = nil
        } catch { erreur = L("Pas noté : \(error.localizedDescription)") }
        etat.relireDecisions()
    }
}

private struct LigneSeance: View {
    @Environment(Etat.self) private var etat
    let creneau: CreneauSeance
    @State private var autre = false
    @State private var texteAutre = ""
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: creneau.choisi ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(creneau.choisi ? Color.vert : Color.ambre)
                Text(creneau.libelle).font(.ligne.weight(.semibold)).foregroundStyle(Color.texte)
                if creneau.choisi, let v = creneau.video {
                    Text(v.statut == "annulee" ? L("Pas de vidéo") : v.sujet).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(2)
                } else if creneau.options.isEmpty {
                    Text("Pas encore de proposition de Réseaux").font(.secondaire).foregroundStyle(Color.texte3)
                }
                Spacer(minLength: 8)
            }
            if !creneau.choisi {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { boutons }
                    VStack(alignment: .leading, spacing: 6) { boutons }
                }
                .buttonStyle(.bordered).controlSize(.small)
                if autre {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Le sujet, en une ligne", text: $texteAutre).textFieldStyle(.roundedBorder).onSubmit(envoyerAutre)
                        Button("Valider", action: envoyerAutre).buttonStyle(.borderedProminent).tint(.action)
                            .disabled(texteAutre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            if let erreur { Text(erreur).font(.petit).foregroundStyle(Color.rouge) }
        }
    }

    @ViewBuilder
    private var boutons: some View {
        ForEach(Array(creneau.options.enumerated()), id: \.offset) { _, o in
            Button { choisir(o) } label: { Label(o, systemImage: "circle").lineLimit(2).multilineTextAlignment(.leading) }
        }
        Button { withAnimation(.snappy) { autre.toggle() } } label: { Label("Autre…", systemImage: "pencil") }
        if let f = creneau.video?.fiche, !f.isEmpty {
            Button { etat.montrer(f) } label: { Label("Fiche", systemImage: "doc.text") }
        }
    }

    private func envoyerAutre() {
        let t = texteAutre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        choisir(t)
    }

    private func choisir(_ sujet: String) {
        etat.enregistrer(video: SeanceDimanche.champs(creneau, sujet: sujet))
        do {
            try Decisions.noter(question: SeanceDimanche.question(creneau), choix: sujet, ref: "seance:\(creneau.id)", liste: "Contenu")
            erreur = nil
        } catch { erreur = L("Validé dans Pilote, mais pas noté pour Réseaux : \(error.localizedDescription)") }
        etat.relireDecisions()
    }
}
