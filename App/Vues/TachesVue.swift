// Tâches : un tableau en colonnes (aujourd'hui, demain, cette semaine, plus tard, fait).
// Les cartes sont tes rappels (toutes listes) et les relances de tes contacts. On glisse une carte pour changer son jour,
// on la pose dans « Fait » pour la cocher. Rappels reste la source : la synchro de 6 h 30 reporte tout dans Notion.
import SwiftUI

enum Colonne: String, CaseIterable, Identifiable {
    case aujourdhui, demain, semaine, plusTard, fait
    var id: String { rawValue }
    var titre: String {
        switch self {
        case .aujourdhui: return "Aujourd'hui"
        case .demain: return "Demain"
        case .semaine: return "Cette semaine"
        case .plusTard: return "Plus tard"
        case .fait: return "Fait"
        }
    }
}

/// Une carte : un rappel ou la prochaine action d'un contact.
enum CarteTache: Identifiable, Hashable {
    case rappel(Tache)
    case contact(Contact)

    var id: String {
        switch self {
        case .rappel(let t): return "r:\(t.id)"
        case .contact(let c): return "c:\(c.id)"
        }
    }

    var echeance: Date? {
        switch self {
        case .rappel(let t): return t.echeance
        case .contact(let c): return Dates.jour.date(from: c.prochaineDate)
        }
    }
}

enum Jours {
    static var cal: Calendar { Calendar.current }
    static var aujourdhui: Date { cal.startOfDay(for: Date()) }
    static var demain: Date { cal.date(byAdding: .day, value: 1, to: aujourdhui)! }
    static var apresDemain: Date { cal.date(byAdding: .day, value: 2, to: aujourdhui)! }
    /// Dimanche de la semaine en cours.
    static var finSemaine: Date {
        let jour = cal.component(.weekday, from: aujourdhui) // 1 = dimanche
        return cal.date(byAdding: .day, value: jour == 1 ? 0 : 8 - jour, to: aujourdhui)!
    }
    static var lundiProchain: Date { cal.date(byAdding: .day, value: 1, to: finSemaine)! }
    static var semaineVide: Bool { apresDemain > finSemaine }
    static var hier: Date { cal.date(byAdding: .day, value: -1, to: aujourdhui)! }

    static func heure(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    static func colonne(_ d: Date?) -> Colonne {
        guard let d else { return .plusTard }
        let j = cal.startOfDay(for: d)
        if j <= aujourdhui { return .aujourdhui }
        if j == demain { return .demain }
        if j <= finSemaine { return .semaine }
        return .plusTard
    }

    /// Le jour donné à une carte posée dans une colonne (on garde son jour s'il y appartient déjà).
    static func jour(pour colonne: Colonne, actuel: Date?) -> Date? {
        if let actuel, Self.colonne(actuel) == colonne, colonne != .aujourdhui { return actuel }
        switch colonne {
        case .aujourdhui: return aujourdhui
        case .demain: return demain
        case .semaine: return apresDemain
        case .plusTard: return lundiProchain
        case .fait: return actuel
        }
    }
}

struct TachesVue: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    @AppStorage("taches.liste") private var liste = "tout"
    @State private var feuille = false

    private var cartes: [CarteTache] {
        var toutes: [CarteTache] = []
        if liste != "contacts" {
            toutes += agenda.taches.filter { liste == "tout" || $0.liste == liste }.map { .rappel($0) }
        }
        if liste == "tout" || liste == "contacts" {
            toutes += etat.contacts
                .filter { !$0.prochaineDate.isEmpty && !$0.nePlusContacter && $0.etape != "perdu" }   // « gagné » suivi (05/11, T3)
                .map { .contact($0) }
        }
        return toutes
    }

    private func cartes(_ colonne: Colonne) -> [CarteTache] {
        cartes.filter { carte in
            switch carte {
            case .rappel(let t):
                if t.faite { return colonne == .fait && (t.faiteLe ?? .distantPast) >= Jours.hier }
                return Jours.colonne(t.echeance) == colonne
            case .contact(let c): return colonne != .fait && Jours.colonne(Dates.jour.date(from: c.prochaineDate)) == colonne
            }
        }
        .sorted { a, b in
            if colonne == .fait, case .rappel(let x) = a, case .rappel(let y) = b {
                return (x.faiteLe ?? .distantPast) > (y.faiteLe ?? .distantPast)
            }
            return (a.echeance ?? .distantFuture) < (b.echeance ?? .distantFuture)
        }
    }

    private var colonnes: [Colonne] { Colonne.allCases.filter { !($0 == .semaine && Jours.semaineVide) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                EnTete(titre: "Tâches", detail: "Glissez une carte pour changer son jour, ou clic droit. Le rond la coche.")
                if let erreur = agenda.erreur { EtatErreur(texte: erreur).background(Color.surface, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)
            switch agenda.accesRappels {
            case .refuse:
                EtatErreur(texte: "Pilote n'a pas accès à Rappels. Réglages Système › Confidentialité › Rappels.").padding(.horizontal, 28)
                Spacer()
            case .inconnu:
                EtatChargement(texte: "Lecture de vos rappels…").padding(.horizontal, 28)
                Spacer()
            case .coupe:
                EtatVide(texte: "Rappels coupés : à activer dans reglages.json (rappels_calendrier).").padding(.horizontal, 28)
                Spacer()
            case .accorde:
                HStack(alignment: .top, spacing: 12) {
                    ForEach(colonnes) { c in
                        ColonneVue(colonne: c, cartes: cartes(c))
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Listes", selection: $liste) {
                    Text("Tout").tag("tout")
                    Text("Relances de contacts").tag("contacts")
                    Divider()
                    ForEach(agenda.listes, id: \.self) { Text($0).tag($0) }
                }
                .help("Quelles cartes afficher")
            }
            ToolbarItem(placement: .primaryAction) {
                BoutonPrincipal(titre: "Nouvelle tâche", symbole: "plus") { feuille = true }
            }
        }
        .sheet(isPresented: $feuille) { NouvelleTache(listeParDefaut: agenda.listes.contains("KRYVA") ? "KRYVA" : (agenda.listes.first ?? "")) }
    }
}

struct ColonneVue: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    let colonne: Colonne
    let cartes: [CarteTache]
    @State private var cible = false

    private var sousTitre: String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        switch colonne {
        case .aujourdhui: return f.string(from: Jours.aujourdhui)
        case .demain: return f.string(from: Jours.demain)
        case .semaine: return "jusqu'à \(f.string(from: Jours.finSemaine))"
        case .plusTard: return "et sans date"
        case .fait: return "hier et aujourd'hui"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(colonne.titre).font(.titreSection).foregroundStyle(Color.texte)
                Text("\(cartes.count)").font(.secondaire.monospacedDigit()).foregroundStyle(Color.texte2)
                Spacer()
            }
            if let sousTitre { Text(sousTitre).font(.petit).foregroundStyle(Color.texte3).padding(.top, -6) }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if cartes.isEmpty {
                        Text(colonne == .fait ? "Rien de coché depuis hier." : "Rien ici.")
                            .font(.secondaire).foregroundStyle(Color.texte3)
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    ForEach(cartes) { carte in
                        CarteVue(carte: carte, colonne: colonne)
                            .draggable(carte.id)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.never)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(cible ? Color.separateur.opacity(0.6) : Color.surface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(cible ? Color.texte3 : Color.clear, lineWidth: 1))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { poser(id) }
            return !ids.isEmpty
        } isTargeted: { cible = $0 }
        .animation(.snappy(duration: 0.2), value: cible)
    }

    private func poser(_ id: String) { Tableau.poser(id, dans: colonne, etat: etat, agenda: agenda) }
}

/// Poser une carte dans une colonne : glisser-déposer ou clic droit, même effet.
enum Tableau {
    @MainActor
    static func poser(_ id: String, dans colonne: Colonne, etat: Etat, agenda: Agenda) {
        if id.hasPrefix("r:") {
            let rid = String(id.dropFirst(2))
            let actuel = agenda.taches.first { $0.id == rid }
            if colonne == .fait {
                agenda.marquerFaite(rid, true)
            } else {
                agenda.deplacer(rid, vers: Jours.jour(pour: colonne, actuel: actuel?.faite == true ? nil : actuel?.echeance))
            }
        } else if id.hasPrefix("c:"), let c = etat.contact(String(id.dropFirst(2))) {
            if colonne == .fait {
                etat.actionFaite(c)
            } else if let jour = Jours.jour(pour: colonne, actuel: Dates.jour.date(from: c.prochaineDate)) {
                var modifie = c
                modifie.prochaineDate = Dates.jour.string(from: jour)
                etat.enregistrer(modifie)
            }
        }
    }
}

struct CarteVue: View {
    @Environment(Etat.self) private var etat
    @Environment(Agenda.self) private var agenda
    let carte: CarteTache
    let colonne: Colonne
    @State private var detail = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            coche
            VStack(alignment: .leading, spacing: 4) {
                Text(titre).font(.ligne).foregroundStyle(estFaite ? Color.texte3 : Color.texte)
                    .strikethrough(estFaite, color: Color.texte3)
                    .lineLimit(3)
                if !sousTitre.isEmpty {
                    Text(sousTitre).font(.petit).foregroundStyle(Color.texte2).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if !quand.isEmpty {
                        Text(quand).font(.petit.weight(.medium).monospacedDigit()).foregroundStyle(enRetard ? Color.rouge : Color.texte2)
                    }
                    Text(etiquette).font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.eleve, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.separateur, lineWidth: 0.5))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { ouvrir() }
        .contextMenu {
            if case .contact(let c) = carte {
                Button("Ouvrir la fiche") { etat.ouvrir(c) }
                Button("Fait") { Tableau.poser(carte.id, dans: .fait, etat: etat, agenda: agenda) }
            } else if case .rappel(let t) = carte {
                Button(t.faite ? "Décocher" : "Fait") { agenda.marquerFaite(t.id, !t.faite) }
                if let n = t.lienNotion { Button("Ouvrir dans Notion") { NSWorkspace.shared.open(n) } }
            }
            Divider()
            ForEach([Colonne.aujourdhui, .demain, .semaine, .plusTard]) { c in
                Button("Déplacer à « \(c.titre) »") { Tableau.poser(carte.id, dans: c, etat: etat, agenda: agenda) }
                    .disabled(c == .semaine && Jours.semaineVide)
            }
            if case .rappel(let t) = carte, t.echeance != nil {
                Button("Retirer la date") { agenda.deplacer(t.id, vers: nil) }
            }
        }
        .popover(isPresented: $detail, arrowEdge: .trailing) {
            if case .rappel(let t) = carte { DetailTache(tache: t) }
        }
    }

    @ViewBuilder private var coche: some View {
        switch carte {
        case .rappel(let t):
            Button { agenda.marquerFaite(t.id, !t.faite) } label: {
                Image(systemName: t.faite ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17)).foregroundStyle(t.faite ? Color.vert : Color.texte3)
            }
            .buttonStyle(.plain)
            .help(t.faite ? "Décocher" : "Fait")
        case .contact:
            Image(systemName: "person.crop.circle").font(.system(size: 17)).foregroundStyle(Color.texte3)
                .help("Relance d'un contact")
        }
    }

    private var estFaite: Bool { if case .rappel(let t) = carte { return t.faite }; return false }

    private var titre: String {
        switch carte {
        case .rappel(let t): return t.titre
        case .contact(let c): return c.titre
        }
    }

    private var sousTitre: String {
        switch carte {
        case .rappel(let t):
            let premiere = t.notes.split(separator: "\n").first.map(String.init) ?? ""
            return premiere.hasPrefix("http") ? "" : premiere
        case .contact(let c):
            return c.prochaineAction.isEmpty ? "Prochaine action à préciser" : c.prochaineAction
        }
    }

    private var etiquette: String {
        switch carte {
        case .rappel(let t): return t.liste + (t.recurrente ? " · se répète" : "")
        case .contact(let c): return c.entreprise.isEmpty ? Libelles.espace(c.espace) : c.entrepriseCourte
        }
    }

    private var enRetard: Bool {
        guard !estFaite, let d = carte.echeance else { return false }
        return Calendar.current.startOfDay(for: d) < Jours.aujourdhui
    }

    private var quand: String {
        if case .rappel(let t) = carte, t.faite, let f = t.faiteLe {
            return "Fait " + f.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "fr_FR")))
        }
        guard let d = carte.echeance else { return "" }
        let fr = Locale(identifier: "fr_FR")
        var morceaux: [String] = []
        if enRetard {
            morceaux.append("En retard · " + d.formatted(.dateTime.day().month(.abbreviated).locale(fr)))
        } else if colonne == .semaine || colonne == .plusTard {
            morceaux.append(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr)))
        }
        if case .rappel(let t) = carte, t.avecHeure {
            morceaux.append(Jours.heure(d))
        }
        return morceaux.joined(separator: " · ")
    }

    private func ouvrir() {
        switch carte {
        case .rappel: detail = true
        case .contact(let c): etat.ouvrir(c)
        }
    }
}

/// Le détail d'un rappel : changer son jour et son heure, le cocher, ouvrir sa ligne Notion.
struct DetailTache: View {
    @Environment(Agenda.self) private var agenda
    @Environment(\.dismiss) private var fermer
    let tache: Tache
    @State private var date = Date()
    @State private var avecDate = false
    @State private var avecHeure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tache.titre).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.texte)
                .fixedSize(horizontal: false, vertical: true)
            Text(tache.liste + (tache.recurrente ? " · se répète" : "")).font(.secondaire).foregroundStyle(Color.texte2)
            if !tache.notes.isEmpty {
                ScrollView {
                    Text(tache.notes).font(.secondaire).foregroundStyle(Color.texte).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            Divider()
            Toggle("Une date", isOn: $avecDate)
            if avecDate {
                HStack {
                    DatePicker("", selection: $date, displayedComponents: avecHeure ? [.date, .hourAndMinute] : [.date])
                        .labelsHidden().datePickerStyle(.field).environment(\.locale, Locale(identifier: "fr_FR"))
                    Toggle("Heure", isOn: $avecHeure).toggleStyle(.checkbox)
                }
            }
            HStack(spacing: 8) {
                if let n = tache.lienNotion {
                    Button("Ouvrir dans Notion") { NSWorkspace.shared.open(n) }
                }
                Spacer()
                Button(tache.faite ? "Décocher" : "Fait") {
                    agenda.marquerFaite(tache.id, !tache.faite)
                    fermer()
                }
                Button("Enregistrer") {
                    if avecDate { agenda.changerEcheance(tache.id, date: date, avecHeure: avecHeure) }
                    else { agenda.deplacer(tache.id, vers: nil) }
                    fermer()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(.action)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            avecDate = tache.echeance != nil
            avecHeure = tache.avecHeure
            date = tache.echeance ?? Jours.aujourdhui
        }
    }
}

/// Feuille « Nouvelle tâche » : quoi, quand, dans quelle liste.
struct NouvelleTache: View {
    @Environment(Agenda.self) private var agenda
    @Environment(\.dismiss) private var fermer
    let listeParDefaut: String
    @State private var titre = ""
    @State private var notes = ""
    @State private var liste = ""
    @State private var quand = "aujourdhui"
    @State private var date = Jours.aujourdhui
    @State private var avecHeure = false
    @State private var heure = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nouvelle tâche").font(.system(size: 19, weight: .semibold))
            TextField("Quoi", text: $titre, prompt: Text("Ex. Rappeler le cabinet Exemplis · 5 min"))
                .textFieldStyle(.roundedBorder).font(.ligne)
            Picker("Quand", selection: $quand) {
                Text("Aujourd'hui").tag("aujourdhui")
                Text("Demain").tag("demain")
                Text("Un autre jour").tag("jour")
                Text("Sans date").tag("aucune")
            }
            .pickerStyle(.segmented)
            if quand == "jour" {
                DatePicker("Jour", selection: $date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            }
            if quand != "aucune" {
                HStack {
                    Toggle("À une heure précise", isOn: $avecHeure).toggleStyle(.checkbox)
                    if avecHeure {
                        DatePicker("", selection: $heure, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }
            }
            Picker("Liste", selection: $liste) {
                ForEach(agenda.listes, id: \.self) { Text($0).tag($0) }
            }
            TextField("Notes", text: $notes, prompt: Text("Le détail, un lien, un fichier"), axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(2...5)
            Text("Dans la liste KRYVA, la synchro du matin lui crée sa ligne dans Notion.")
                .font(.petit).foregroundStyle(Color.texte3)
            HStack {
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button("Ajouter la tâche") {
                    agenda.creer(titre: titre, notes: notes, liste: liste, date: dateChoisie, avecHeure: avecHeure && quand != "aucune")
                    fermer()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(.action)
                .disabled(titre.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 480)
        .onAppear { liste = listeParDefaut }
    }

    private var dateChoisie: Date? {
        let jour: Date
        switch quand {
        case "aujourdhui": jour = Jours.aujourdhui
        case "demain": jour = Jours.demain
        case "jour": jour = Calendar.current.startOfDay(for: date)
        default: return nil
        }
        guard avecHeure else { return jour }
        let h = Calendar.current.dateComponents([.hour, .minute], from: heure)
        return Calendar.current.date(bySettingHour: h.hour ?? 18, minute: h.minute ?? 0, second: 0, of: jour)
    }
}

