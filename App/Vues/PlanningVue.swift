// Planning : la journée heure par heure (ouverte par défaut) ou la semaine du lundi au dimanche (docs/PLANNING-CONTRAT.md).
// Tâches = rappels, placés à leur échéance ; événements = Calendrier, de leur début à leur fin ; une couleur par liste ou calendrier,
// une ligne pour l'heure actuelle, les tâches finies cochées et grisées. Un clic ouvre le document ; « Terminé » coche le rappel
// et prévient PILOTE (entrants.jsonl). Le Calendrier n'est jamais modifié.
import SwiftUI

struct PlanningVue: View {
    @Environment(Agenda.self) private var agenda
    @Environment(Etat.self) private var etat
    @State private var mode: Mode = .jour
    /// Le jour choisi ; nil = aujourd'hui (suit le changement de jour si l'app reste ouverte).
    @State private var jourChoisi: Date?
    @AppStorage("planning.terminees") private var montrerTerminees = false

    enum Mode: String, CaseIterable, Identifiable {
        case jour = "Jour", semaine = "Semaine"
        var id: String { rawValue }
    }

    private var cal: Calendar { Semaine.calendrier() }

    /// Les questions « ❓ » vivent dans Aujourd'hui › À décider, pas dans la grille (03/11, Sacha : « c'est illisible »).
    private var decisions: [TachePlanning] { agenda.planning.filter { $0.genre == .tache && Decisions.estDecision($0.titre) } }
    private func faite(_ t: TachePlanning) -> Bool { t.faite || agenda.terminees[t.id] != nil }
    /// Ce que montre la grille : sans les questions, et sans ce qui est terminé (sauf si on le demande).
    private var aMontrer: [TachePlanning] {
        agenda.planning.filter { !Decisions.estDecision($0.titre) && (montrerTerminees || !faite($0)) }
    }

    var body: some View {
        TimelineView(.everyMinute) { contexte in
            let maintenant = contexte.date
            let jour = jourChoisi ?? cal.startOfDay(for: maintenant)
            let jours = mode == .jour ? [jour] : Semaine.jours(de: jour)
            let plage = DateInterval(start: jours[0], end: cal.date(byAdding: .day, value: 1, to: jours[jours.count - 1])!)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    EnTete(titre: "Planning", detail: libelle(jours, maintenant))
                    legende
                }
                commandes(maintenant)
                contenu(jours: jours, maintenant: maintenant)
            }
            .padding(28)
            .task(id: plage) { await agenda.chargerPlanning(plage) }
        }
    }

    // MARK: En-tête

    private func commandes(_ maintenant: Date) -> some View {
        HStack(spacing: 10) {
            Picker("Vue", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 200)
            Button { avancer(-1, maintenant) } label: { Image(systemName: "chevron.left") }
                .help(mode == .jour ? "Jour précédent" : "Semaine précédente")
            Button("Aujourd'hui") { jourChoisi = nil }
                .disabled(jourChoisi == nil)
            Button { avancer(1, maintenant) } label: { Image(systemName: "chevron.right") }
                .help(mode == .jour ? "Jour suivant" : "Semaine suivante")
            Spacer()
            let ouvertes = decisions.filter { !faite($0) }.count
            if ouvertes > 0 {
                Button { etat.ecran = .aujourdhui } label: {
                    Label("\(ouvertes) question\(ouvertes > 1 ? "s" : "") à trancher sur l'accueil", systemImage: "questionmark.circle.fill")
                }
                .buttonStyle(.bordered).tint(.ambre)
            }
            let finies = agenda.planning.filter { !Decisions.estDecision($0.titre) && faite($0) }.count
            if finies > 0 {
                Toggle("Montrer les \(finies) terminée\(finies > 1 ? "s" : "")", isOn: $montrerTerminees).toggleStyle(.checkbox)
                    .font(.secondaire)
            }
        }
    }

    private var legende: some View {
        HStack(spacing: 12) {
            ForEach(CalendriersPlanning.listesTaches, id: \.nom) { c in
                HStack(spacing: 4) {
                    Image(systemName: "circle").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: c.couleur))
                    Text(c.nom).font(.petit).foregroundStyle(Color.texte2)
                }
                .help("Tâches : liste « \(c.nom) » de Rappels")
            }
            ForEach(CalendriersPlanning.calendriersEvenements, id: \.nom) { c in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: c.couleur)).frame(width: 9, height: 9)
                    Text(c.nom).font(.petit).foregroundStyle(Color.texte2)
                }
                .help("Événements : calendrier « \(c.nom) »")
            }
        }
        .fixedSize()
    }

    private func avancer(_ sens: Int, _ maintenant: Date) {
        let aujourdhui = cal.startOfDay(for: maintenant)
        let base = jourChoisi ?? aujourdhui
        let nouveau = cal.date(byAdding: .day, value: sens * (mode == .jour ? 1 : 7), to: base) ?? base
        let revenu = mode == .jour ? cal.isDate(nouveau, inSameDayAs: aujourdhui)
                                   : Semaine.lundi(de: nouveau) == Semaine.lundi(de: aujourdhui)
        jourChoisi = revenu ? nil : nouveau
    }

    private func libelle(_ jours: [Date], _ maintenant: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        var texte: String
        if jours.count == 1 {
            f.dateFormat = "EEEE d MMMM"
            texte = f.string(from: jours[0]) + (cal.isDate(jours[0], inSameDayAs: maintenant) ? " · aujourd'hui" : "")
        } else {
            let premier = jours[0], dernier = jours[jours.count - 1]
            f.dateFormat = cal.isDate(premier, equalTo: dernier, toGranularity: .month) ? "d" : "d MMMM"
            let debut = f.string(from: premier)
            f.dateFormat = "d MMMM"
            texte = "Du \(debut) au \(f.string(from: dernier))"
        }
        let taches = agenda.planning.filter { $0.genre == .tache && !Decisions.estDecision($0.titre) }
        let faites = taches.filter { $0.faite || agenda.terminees[$0.id] != nil }.count
        if !taches.isEmpty { texte += " · tâches terminées : \(faites) sur \(taches.count)" }
        return texte
    }

    // MARK: Contenu

    @ViewBuilder
    private func contenu(jours: [Date], maintenant: Date) -> some View {
        switch agenda.accesCalendrier {
        case .refuse:
            Carte(titre: "Planning") {
                EtatErreur(texte: "Pilote n'a pas accès au Calendrier. Réglages Système › Confidentialité › Calendriers.")
            }
        case .inconnu:
            Carte(titre: "Planning") { EtatChargement(texte: "Lecture du Calendrier…") }
        case .coupe:
            Carte(titre: "Planning") { EtatVide(texte: "Calendrier et Rappels coupés : à activer dans reglages.json (rappels_calendrier).") }
        case .accorde:
            if let e = agenda.erreurPlanning {
                Carte(titre: "Planning") { EtatErreur(texte: e) }
            }
            if !agenda.planningLu {
                Carte(titre: "Planning") { EtatChargement(texte: "Lecture des Rappels et du Calendrier…") }
            } else if agenda.calendriersPlanning.isEmpty {
                Carte(titre: "Calendriers") {
                    EtatVide(texte: "Rien du planning sur ce Mac : ni listes de Rappels (Appels, KRYVA, Freelance, Contenu, Papiers), ni calendriers (Salle, Rendez-vous, Perso).")
                }
            }
            if agenda.planningLu {
                GrillePlanning(jours: jours, taches: aMontrer, terminees: agenda.terminees, maintenant: maintenant,
                               terminer: { agenda.terminer($0) },
                               choisirJour: { j in
                                   jourChoisi = cal.isDate(j, inSameDayAs: maintenant) ? nil : j
                                   mode = .jour
                               })
            }
        }
    }
}

// MARK: - Grille heure par heure (un jour ou sept)

struct GrillePlanning: View {
    let jours: [Date]
    let taches: [TachePlanning]
    let terminees: [String: String]
    let maintenant: Date
    let terminer: (TachePlanning) -> Void
    let choisirJour: (Date) -> Void

    private var cal: Calendar { Semaine.calendrier() }
    private var semaine: Bool { jours.count > 1 }
    private var hauteurHeure: CGFloat { semaine ? 48 : 72 }
    private let marge: CGFloat = 56
    private let haut: CGFloat = 8

    var body: some View {
        let heures = plageHeures
        VStack(spacing: 0) {
            if semaine { enTetesJours }
            if taches.contains(where: \.journee) { bandeJournee }
            GeometryReader { geo in
                let largeur = max((geo.size.width - marge - 8) / CGFloat(jours.count), 40)
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        ZStack(alignment: .topLeading) {
                            lignes(heures)
                            ForEach(Array(jours.enumerated()), id: \.offset) { i, jour in
                                colonne(jour, i, largeur, heures)
                            }
                            ligneMaintenant(largeur, heures)
                        }
                        .frame(height: haut * 2 + CGFloat(heures.count) * hauteurHeure, alignment: .top)
                    }
                    .overlay {
                        if !taches.contains(where: { t in jours.contains { tombe(t, $0) } }) {
                            Text(semaine ? "Rien de prévu cette semaine." : "Rien de prévu ce jour-là.")
                                .font(.ligne).foregroundStyle(Color.texte2)
                        }
                    }
                    .onAppear { proxy.scrollTo(heureDeDepart(heures), anchor: .top) }
                    .onChange(of: jours) { proxy.scrollTo(heureDeDepart(heures), anchor: .top) }
                }
            }
            .frame(minHeight: 320)
        }
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Repères

    private var enTetesJours: some View {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE"
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: marge)
                ForEach(jours, id: \.self) { j in
                    let auj = cal.isDate(j, inSameDayAs: maintenant)
                    Button { choisirJour(j) } label: {
                        HStack(spacing: 5) {
                            Text(f.string(from: j)).font(.secondaire).foregroundStyle(auj ? Color.rouge : Color.texte2)
                            Text("\(cal.component(.day, from: j))")
                                .font(.ligneForte.monospacedDigit())
                                .foregroundStyle(auj ? Color.white : Color.texte)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(auj ? Color.rouge : Color.clear, in: Capsule())
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Voir la journée")
                }
                Color.clear.frame(width: 8)
            }
            .padding(.vertical, 10)
            Rectangle().fill(Color.separateur).frame(height: 0.5)
        }
    }

    private var bandeJournee: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text("Sans heure").font(.petit).foregroundStyle(Color.texte3)
                    .frame(width: marge - 8, alignment: .trailing).padding(.trailing, 8).padding(.top, 6)
                ForEach(jours, id: \.self) { j in
                    VStack(spacing: 3) {
                        ForEach(taches.filter { $0.journee && tombe($0, j) }) { t in
                            BlocTache(tache: t, fait: (t.faite || terminees[t.id] != nil), compact: true, court: true, terminer: terminer)
                                .frame(height: 26)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top).padding(.horizontal, 2)
                }
                Color.clear.frame(width: 8)
            }
            .padding(.vertical, 6)
            Rectangle().fill(Color.separateur).frame(height: 0.5)
        }
    }

    private func lignes(_ heures: Range<Int>) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: haut)
            ForEach(heures, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(String(format: "%02d:00", h)).font(.petit.monospacedDigit()).foregroundStyle(Color.texte3)
                        .frame(width: marge - 8, alignment: .trailing).padding(.trailing, 8).offset(y: -7)
                    Rectangle().fill(Color.separateur).frame(height: 0.5)
                }
                .frame(height: hauteurHeure, alignment: .top)
                .id(h)
            }
        }
    }

    @ViewBuilder
    private func ligneMaintenant(_ largeur: CGFloat, _ heures: Range<Int>) -> some View {
        if let i = jours.firstIndex(where: { cal.isDate($0, inSameDayAs: maintenant) }) {
            let y = position(maintenant, jour: jours[i], heures)
            if y >= haut && y <= haut + CGFloat(heures.count) * hauteurHeure {
                ZStack(alignment: .topLeading) {
                    Text(Self.hhmm(maintenant)).font(.petit.weight(.semibold).monospacedDigit()).foregroundStyle(Color.rouge)
                        .padding(.horizontal, 3).background(Color.surface)
                        .frame(width: marge - 4, alignment: .trailing).offset(y: y - 8)
                    Circle().fill(Color.rouge).frame(width: 8, height: 8)
                        .offset(x: marge + CGFloat(i) * largeur - 4, y: y - 4)
                    Rectangle().fill(Color.rouge).frame(width: largeur, height: 1.5)
                        .offset(x: marge + CGFloat(i) * largeur, y: y - 0.75)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Tâches

    @ViewBuilder
    private func colonne(_ jour: Date, _ i: Int, _ largeur: CGFloat, _ heures: Range<Int>) -> some View {
        let finJour = cal.date(byAdding: .day, value: 1, to: jour)!
        let duJour = taches.filter { !$0.journee && tombe($0, jour) }
        let places = Disposition.colonnes(duJour.map { (debut: max($0.debut, jour), fin: min($0.fin, finJour)) })
        ForEach(Array(duJour.enumerated()), id: \.element.id) { k, t in
            let y = position(max(t.debut, jour), jour: jour, heures)
            let bas = position(min(t.fin, finJour), jour: jour, heures)
            let h = max(bas - y - 2, 20)
            let l = largeur / CGFloat(places[k].sur)
            BlocTache(tache: t, fait: (t.faite || terminees[t.id] != nil), compact: semaine, court: h < 50, terminer: terminer)
                .frame(width: max(l - 4, 20), height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(x: marge + CGFloat(i) * largeur + CGFloat(places[k].colonne) * l + 2, y: y + 1)
        }
    }

    /// La tâche a lieu (au moins en partie) ce jour-là.
    private func tombe(_ t: TachePlanning, _ jour: Date) -> Bool {
        let finJour = cal.date(byAdding: .day, value: 1, to: jour)!
        return t.debut < finJour && (t.fin > jour || (t.fin == t.debut && t.debut >= jour))
    }

    private func position(_ d: Date, jour: Date, _ heures: Range<Int>) -> CGFloat {
        let origine = cal.date(byAdding: .hour, value: heures.lowerBound, to: jour)!
        return haut + CGFloat(d.timeIntervalSince(origine) / 3600) * hauteurHeure
    }

    /// De 7 h à 21 h, élargi aux tâches qui commencent plus tôt ou finissent plus tard.
    private var plageHeures: Range<Int> {
        var debut = 7, fin = 21
        for jour in jours {
            let finJour = cal.date(byAdding: .day, value: 1, to: jour)!
            for t in taches where !t.journee && tombe(t, jour) {
                debut = min(debut, cal.component(.hour, from: max(t.debut, jour)))
                let f = min(t.fin, finJour)
                fin = max(fin, f >= finJour ? 24 : cal.component(.hour, from: f) + (cal.component(.minute, from: f) > 0 ? 1 : 0))
            }
        }
        return debut..<max(fin, debut + 1)
    }

    /// Aujourd'hui : une heure avant maintenant. Sinon : la première tâche.
    private func heureDeDepart(_ heures: Range<Int>) -> Int {
        let h: Int
        if jours.contains(where: { cal.isDate($0, inSameDayAs: maintenant) }) {
            h = cal.component(.hour, from: maintenant) - 1
        } else if let t = taches.first(where: { t in !t.journee && jours.contains { tombe(t, $0) } }) {
            h = cal.component(.hour, from: t.debut)
        } else {
            h = heures.lowerBound
        }
        return min(max(h, heures.lowerBound), heures.upperBound - 1)
    }

    /// Tâche : son heure (ou « sans heure »). Événement : de … à … (ou « toute la journée »).
    static func horaire(_ t: TachePlanning) -> String {
        switch (t.genre, t.journee) {
        case (.tache, true): return "sans heure"
        case (.tache, false): return hhmm(t.debut)
        case (.evenement, true): return "toute la journée"
        case (.evenement, false): return "\(hhmm(t.debut)) à \(hhmm(t.fin))"
        }
    }

    static func hhmm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

// MARK: - Une tâche

struct BlocTache: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    let tache: TachePlanning
    let fait: Bool
    /// Semaine et bande « journée » : titre (et heure) seulement, « Terminé » en icône.
    let compact: Bool
    /// Bloc bas : tout tient sur la ligne du titre.
    let court: Bool
    let terminer: (TachePlanning) -> Void
    @State private var detail = false
    @State private var aSupprimer = false

    private var couleur: Color { fait ? Color.texte3 : Color(hex: CalendriersPlanning.couleur(tache.calendrier)) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(couleur).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 5) {
                    if tache.genre == .tache { caseTache }
                    Text(tache.titre)
                        .font(compact ? .petit.weight(.semibold) : .secondaire.weight(.semibold))
                        .foregroundStyle(fait ? Color.texte3 : Color.texte)
                        .strikethrough(fait)
                        .lineLimit(compact && !court ? 2 : 1)
                    if !compact && !(tache.journee && tache.genre == .evenement) {
                        Text(horaire).font(.petit.monospacedDigit()).foregroundStyle(Color.texte2).lineLimit(1).layoutPriority(-1)
                    }
                    Spacer(minLength: 2)
                    boutons
                }
                if compact && !court && !tache.journee && tache.genre == .evenement {
                    Text(horaire).font(.petit.monospacedDigit()).foregroundStyle(Color.texte2).lineLimit(1)
                }
                if !compact { notes }
            }
            .padding(.horizontal, 6).padding(.vertical, compact ? 3 : 5)
        }
        // minHeight 0 : le bloc garde la hauteur de sa case même si les notes dépassent ; le titre reste en haut, visible.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(couleur.opacity(fait ? 0.10 : 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { ouvrir() }
        .pointerStyle(.link)
        .help(tache.document == nil ? "\(tache.titre) : voir le détail" : "\(tache.titre) : ouvrir le document")
        .popover(isPresented: $detail, arrowEdge: .trailing) {
            DetailTachePlanning(tache: tache, fait: fait, terminer: { terminer(tache) })
        }
        .contextMenu {
            if !fait {
                Button { terminer(tache) } label: { Label("Terminé", systemImage: "checkmark") }
            }
            if tache.genre == .tache {
                Button(role: .destructive) { aSupprimer = true } label: { Label("Supprimer…", systemImage: "trash") }
            }
        }
        .confirmationDialog("Supprimer « \(tache.titre) » ?", isPresented: $aSupprimer) {
            Button("Supprimer", role: .destructive) { agenda.supprimer(tache) }
        } message: {
            Text("Le rappel disparaît aussi de Rappels, sur le Mac et l'iPhone. PILOTE est prévenu.")
        }
    }

    private var aideTermine: String {
        tache.genre == .tache ? "Terminé : coche le rappel et prévient PILOTE"
            : "Terminé : il ne s'affiche plus dans Pilote (Calendrier n'est pas modifié), PILOTE est prévenu"
    }

    /// La case d'une tâche : cochée et verte si finie ; en semaine, c'est le bouton « Terminé ».
    @ViewBuilder private var caseTache: some View {
        if fait {
            Image(systemName: "checkmark.circle.fill").font(.petit).foregroundStyle(Color.vert)
        } else if compact {
            Button { terminer(tache) } label: { Image(systemName: "circle") }
                .buttonStyle(.plain).font(.petit).foregroundStyle(couleur).help("Terminé : coche le rappel et prévient PILOTE")
        } else {
            Image(systemName: "circle").font(.petit).foregroundStyle(couleur)
        }
    }

    @ViewBuilder private var boutons: some View {
        Button { detail = true } label: { Image(systemName: "info.circle") }
            .buttonStyle(.plain).foregroundStyle(Color.texte2).help("But, documents, fini quand")
        if !fait && !compact {
            Button { terminer(tache) } label: { Label("Terminé", systemImage: "checkmark") }
                .controlSize(.small).help(aideTermine)
        }
    }

    @ViewBuilder private var notes: some View {
        if let b = tache.notes.but {
            Text("But : " + b).font(.petit).foregroundStyle(fait ? Color.texte3 : Color.texte2).lineLimit(2)
        }
        if let f = tache.notes.finiQuand {
            Text("Fini quand : " + f).font(.petit).foregroundStyle(fait ? Color.texte3 : Color.texte2).lineLimit(2)
        }
        if !tache.notes.docs.isEmpty {
            HStack(spacing: 10) {
                ForEach(tache.notes.docs, id: \.self) { d in
                    Link(destination: d.url) { Label(d.libelle, systemImage: d.url.isFileURL ? "doc" : "link") }
                        .font(.petit).lineLimit(1)
                }
            }
        }
    }

    private var horaire: String { GrillePlanning.horaire(tache) }

    /// Un clic : le document (URL, sinon le premier lien de « Docs »). Sans document (ou s'il ne s'ouvre pas) : le détail.
    private func ouvrir() {
        if let url = tache.document, url.isFileURL { etat.montrer(url.path); return }
        if let url = tache.document, NSWorkspace.shared.open(url) { return }
        detail = true
    }
}

/// Le détail d'une tâche : but, documents, fini quand, et les deux gestes (ouvrir, terminé).
struct DetailTachePlanning: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    let tache: TachePlanning
    let fait: Bool
    let terminer: () -> Void
    @State private var aSupprimer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: CalendriersPlanning.couleur(tache.calendrier))).frame(width: 9, height: 9)
                Text(tache.genre == .tache ? "Tâche · \(tache.calendrier)" : "Événement · \(tache.calendrier)")
                    .font(.petit).foregroundStyle(Color.texte2)
                Text(GrillePlanning.horaire(tache)).font(.petit.monospacedDigit()).foregroundStyle(Color.texte2)
            }
            Text(tache.titre).font(.titreSection).foregroundStyle(Color.texte).fixedSize(horizontal: false, vertical: true)
            if let b = tache.notes.but { bloc("But", b) }
            if !tache.notes.docs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Docs").font(.petit.weight(.semibold)).foregroundStyle(Color.texte2)
                    ForEach(tache.notes.docs, id: \.self) { d in
                        Link(destination: d.url) { Label(d.libelle, systemImage: d.url.isFileURL ? "doc" : "link") }
                            .font(.secondaire)
                    }
                }
            }
            if let f = tache.notes.finiQuand { bloc("Fini quand", f) }
            if tache.notes.but == nil && tache.notes.docs.isEmpty && tache.notes.finiQuand == nil {
                Text("Pas de but, de document ni de « fini quand » dans l'événement.").font(.secondaire).foregroundStyle(Color.texte2)
            }
            HStack {
                if let url = tache.document {
                    Button("Ouvrir le document") { if url.isFileURL { etat.montrer(url.path) } else { NSWorkspace.shared.open(url) } }
                }
                if tache.genre == .tache {
                    Button(role: .destructive) { aSupprimer = true } label: { Label("Supprimer…", systemImage: "trash") }
                        .help("Supprime le rappel de Rappels (Mac et iPhone)")
                }
                Spacer()
                if fait {
                    Label("Terminé", systemImage: "checkmark.circle.fill").font(.secondaire).foregroundStyle(Color.vert)
                } else {
                    BoutonPrincipal(titre: "Terminé", symbole: "checkmark", action: terminer)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .confirmationDialog("Supprimer « \(tache.titre) » ?", isPresented: $aSupprimer) {
            Button("Supprimer", role: .destructive) { agenda.supprimer(tache) }
        } message: {
            Text("Le rappel disparaît aussi de Rappels, sur le Mac et l'iPhone. PILOTE est prévenu.")
        }
    }

    private func bloc(_ titre: String, _ texte: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.petit.weight(.semibold)).foregroundStyle(Color.texte2)
            Text(texte).font(.secondaire).foregroundStyle(Color.texte).fixedSize(horizontal: false, vertical: true)
        }
    }

}
