// Planning des publications (08/11, Sacha : « tout doit être ensuite prêt, et on doit tout programmer directement dans Pilote.
// Je veux un planning complet et très visuel »). Semaine ou mois, une colonne par jour, une carte par publication : couverture,
// heure, réseau et compte, statut. Les trous (lundi-vendredi : chacun des 6 comptes sans vidéo, règle du 08/11) et les
// doublons (la même vidéo deux fois sur un compte) se voient d'un coup d'œil. Clic : le détail.
import AppKit
import SwiftUI

enum ModePlanningPublications: String, CaseIterable, Identifiable {
    case semaine = "Semaine", mois = "Mois"
    var id: String { rawValue }
}

/// Couleur, symbole et nom court de chaque réseau (les mêmes partout dans le planning).
enum StylePublication {
    static func couleur(_ r: ReseauPublication) -> Color {
        switch r {
        case .youtube: return Color(hex: 0xE62117)
        case .instagram: return Color(hex: 0xC13584)
        case .tiktok: return Color.dynamique(0x161823, 0x25F4EE)
        }
    }

    static func encre(_ r: ReseauPublication) -> Color { r == .tiktok ? Color.dynamique(0xFFFFFF, 0x161823) : .white }

    static func symbole(_ r: ReseauPublication) -> String {
        switch r {
        case .youtube: return "play.fill"
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        }
    }

    static func nom(_ r: ReseauPublication) -> String {
        switch r {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        }
    }

    static func espace(_ compte: String) -> String { compte.hasSuffix("kryva") ? "KRYVA" : "perso" }
    /// « YT perso », « IG KRYVA », « TT perso » : le compte en court, pour les trous.
    static func court(_ c: ComptePublication) -> String {
        ([ReseauPublication.youtube: "YT", .instagram: "IG", .tiktok: "TT"][c.reseau] ?? "") + " " + espace(c.id)
    }

    /// à valider, prévu, envoyé, publié, échec, brouillon TikTok à finir (et à reconnecter, envoi en cours).
    static func statut(_ p: Publication) -> (texte: String, couleur: Color, symbole: String) {
        switch p.etat {
        case "a_valider": return ("à valider", .ambre, "hand.raised.fill")
        case "planifie": return ("prévu", .texte2, "clock")
        case "envoi": return ("envoi en cours", .texte2, "arrow.up.circle")
        case "envoye":
            if p.reseau == .tiktok && p.phase == "boite" { return ("brouillon TikTok à finir", .ambre, "tray.and.arrow.down.fill") }
            return ("envoyé", .vert, "checkmark.circle")
        case "publie": return ("publié", .vert, "checkmark.seal.fill")
        case "echec": return ("échec", .rouge, "xmark.octagon.fill")
        case "reconnexion": return ("à reconnecter", .rouge, "exclamationmark.triangle.fill")
        case "annule": return ("annulé", .texte3, "minus.circle")
        default: return (p.etat, .texte2, "circle")
        }
    }
}

struct PlanningPublicationsVue: View {
    @Environment(Etat.self) private var etat
    /// Change à chaque rechargement de l'écran parent (toutes les 15 s, après une action).
    let actualisation: Int
    let valider: (Publication) -> Void
    /// « + » sur un jour : le formulaire passe à ce jour.
    var ajouter: ((Date) -> Void)? = nil

    /// PILOTE_PLANNING_LE=2026-11-09 et PILOTE_PLANNING_MODE=Mois ouvrent le planning sur cette semaine ou ce mois (vérifications).
    @State private var mode = ModePlanningPublications(rawValue: ProcessInfo.processInfo.environment["PILOTE_PLANNING_MODE"] ?? "") ?? .semaine
    @State private var reference = Publications.lireDate((ProcessInfo.processInfo.environment["PILOTE_PLANNING_LE"] ?? "") + " 12:00") ?? Date()
    @State private var pubs: [Publication] = []
    @State private var detail: Publication?
    @State private var erreur: String?

    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_FR")
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        c.firstWeekday = 2
        return c
    }
    private var cal: Calendar { Self.calendrier }

    /// Les jours montrés : la semaine (7), ou les semaines entières qui couvrent le mois.
    private var jours: [Date] {
        switch mode {
        case .semaine:
            let debut = cal.dateInterval(of: .weekOfYear, for: reference)!.start
            return (0..<7).map { cal.date(byAdding: .day, value: $0, to: debut)! }
        case .mois:
            let m = cal.dateInterval(of: .month, for: reference)!
            let debut = cal.dateInterval(of: .weekOfYear, for: m.start)!.start
            let fin = cal.dateInterval(of: .weekOfYear, for: m.end.addingTimeInterval(-1))!.end
            let n = cal.dateComponents([.day], from: debut, to: fin).day ?? 35
            return (0..<n).map { cal.date(byAdding: .day, value: $0, to: debut)! }
        }
    }

    private var cle: String { "\(mode.rawValue)|\(Int(reference.timeIntervalSince1970 / 86400))|\(actualisation)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            barre
            legende
            if let erreur { EtatErreur(texte: erreur) }
            switch mode {
            case .semaine: semaine
            case .mois: mois
            }
        }
        .task(id: cle) { charger() }
        .sheet(item: $detail) { p in
            DetailPublicationVue(publication: p, valider: { valider(p); detail = nil }, publiee: { marquerPubliee(p); detail = nil }, fermer: { detail = nil })
        }
    }

    private func marquerPubliee(_ p: Publication) {
        guard let stock = etat.stock else { return }
        do {
            try Publications.marquerPubliee(stock, id: p.id, par: "\(Moi.nom) (app)")
            erreur = nil
        } catch { erreur = "\(error)" }
        charger()
    }

    private func charger() {
        guard let stock = etat.stock, let premier = jours.first, let dernier = jours.last else { return }
        do {
            pubs = try Publications.entre(stock, premier, cal.date(byAdding: .day, value: 1, to: dernier)!).filter { $0.etat != "annule" }
            erreur = nil
        } catch { erreur = "\(error)" }
    }

    // MARK: Barre, légende

    private var titrePeriode: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = cal.timeZone
        switch mode {
        case .semaine:
            guard let a = jours.first, let b = jours.last else { return "" }
            f.dateFormat = "d MMMM"
            let fin = f.string(from: b)
            f.dateFormat = cal.isDate(a, equalTo: b, toGranularity: .month) ? "d" : "d MMMM"
            return "Semaine du \(f.string(from: a)) au \(fin)"
        case .mois:
            f.dateFormat = "LLLL yyyy"
            let t = f.string(from: reference)
            return t.prefix(1).uppercased() + t.dropFirst()
        }
    }

    private var barre: some View {
        HStack(spacing: 10) {
            Button { deplacer(-1) } label: { Image(systemName: "chevron.left") }
            Button("Aujourd'hui") { reference = Date() }
            Button { deplacer(1) } label: { Image(systemName: "chevron.right") }
            Text(titrePeriode).font(.titreSection).foregroundStyle(Color.texte)
            Spacer()
            Text(resume).font(.secondaire).foregroundStyle(Color.texte2)
            Picker("", selection: $mode) {
                ForEach(ModePlanningPublications.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private var resume: String {
        let trous = jours.filter { !manques($0).isEmpty }.count
        let doubles = jours.filter { !doublons($0).isEmpty }.count
        var l = ["\(pubs.count) publication\(pubs.count > 1 ? "s" : "")"]
        if trous > 0 { l.append("\(trous) jour\(trous > 1 ? "s" : "") à trou") }
        if doubles > 0 { l.append("\(doubles) jour\(doubles > 1 ? "s" : "") avec doublon") }
        return l.joined(separator: " · ")
    }

    private func deplacer(_ sens: Int) {
        reference = cal.date(byAdding: mode == .semaine ? .weekOfYear : .month, value: sens, to: reference) ?? reference
    }

    private var legende: some View {
        HStack(spacing: 14) {
            ForEach([ReseauPublication.youtube, .instagram, .tiktok], id: \.self) { r in
                HStack(spacing: 5) { BadgeReseau(reseau: r); Text(StylePublication.nom(r)).font(.petit).foregroundStyle(Color.texte2) }
            }
            Divider().frame(height: 14)
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.circle.fill").font(.petit).foregroundStyle(Color.rouge)
                Text("trou : lundi-vendredi, un compte sans vidéo (6 comptes)").font(.petit).foregroundStyle(Color.texte2)
            }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).stroke(Color.ambre, lineWidth: 2).frame(width: 12, height: 12)
                Text("doublon : la même vidéo 2 fois sur un compte").font(.petit).foregroundStyle(Color.texte2)
            }
            Spacer()
        }
    }

    // MARK: Trous, doublons

    private func duJour(_ d: Date) -> [Publication] {
        pubs.filter { p in p.prevu.map { cal.isDate($0, inSameDayAs: d) } ?? false }
    }

    /// Lundi-vendredi, aujourd'hui et après : les comptes sans aucune publication ce jour-là (08/11, Sacha : « les 6 comptes
    /// doivent être alimentés »). Seul ce que Pilote programme est connu : un post fait ailleurs (PlugKit, l'app) n'y est pas.
    private func manques(_ d: Date) -> [String] {
        let jour = cal.component(.weekday, from: d)
        guard (2...6).contains(jour), cal.startOfDay(for: d) >= cal.startOfDay(for: Date()) else { return [] }
        let l = duJour(d).filter { $0.etat != "echec" && $0.etat != "annule" }
        return ComptePublication.tous.filter { c in !l.contains { $0.compte == c.id } }.map(StylePublication.court)
    }

    /// Les comptes qui ont deux publications ou plus ce jour-là.
    /// Doublon (08/11) : la même vidéo (même fichier) deux fois sur un compte, ce jour-là et un autre jour. Deux vidéos
    /// différentes le même jour sur un compte (12:30 et 18:00) sont voulues : pas un doublon.
    private func doublons(_ d: Date) -> Set<String> {
        let actives = pubs.filter { $0.etat != "echec" && $0.etat != "annule" }
        return Set(duJour(d).filter { p in p.etat != "echec" && p.etat != "annule" && actives.contains {
            $0.id != p.id && $0.compte == p.compte && $0.empreinteFichier == p.empreinteFichier } }.map(\.compte))
    }

    private func estAujourdhui(_ d: Date) -> Bool { cal.isDateInToday(d) }

    // MARK: Semaine

    private var semaine: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(jours, id: \.self) { d in
                let double = doublons(d)
                VStack(alignment: .leading, spacing: 8) {
                    enTeteJour(d)
                    ForEach(duJour(d)) { p in
                        CartePublicationPlanning(publication: p, doublon: double.contains(p.compte)) { detail = p }
                    }
                    if duJour(d).isEmpty {
                        Text(manques(d).isEmpty ? "rien de prévu" : "à remplir")
                            .font(.petit).foregroundStyle(manques(d).isEmpty ? Color.texte3 : Color.rouge)
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .foregroundStyle(manques(d).isEmpty ? Color.separateur : Color.rouge.opacity(0.6)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(maxWidth: .infinity, minHeight: 420, alignment: .top)
                .background(estAujourdhui(d) ? Color.action.opacity(0.05) : Color.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(estAujourdhui(d) ? Color.action.opacity(0.5) : Color.separateur.opacity(0.6)))
            }
        }
    }

    private func enTeteJour(_ d: Date) -> some View {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = cal.timeZone
        f.dateFormat = "EEE"
        let nom = f.string(from: d).replacingOccurrences(of: ".", with: "")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(nom.prefix(1).uppercased() + nom.dropFirst()).font(.secondaire).foregroundStyle(Color.texte2)
                Text("\(cal.component(.day, from: d))").font(.titreSection)
                    .foregroundStyle(estAujourdhui(d) ? Color.action : Color.texte)
                Spacer()
                if !duJour(d).isEmpty { Text("\(duJour(d).count)").font(.petit).foregroundStyle(Color.texte2) }
                if let ajouter, cal.startOfDay(for: d) >= cal.startOfDay(for: Date()) {
                    Button { ajouter(d) } label: { Image(systemName: "plus.circle").font(.secondaire) }
                        .buttonStyle(.plain).foregroundStyle(Color.action).help("Programmer une vidéo ce jour-là")
                }
            }
            ForEach(manques(d), id: \.self) { e in
                Label("manque \(e)", systemImage: "exclamationmark.circle.fill").font(.petit.weight(.medium)).foregroundStyle(Color.rouge)
            }
            if !doublons(d).isEmpty {
                Label("doublon", systemImage: "square.on.square").font(.petit.weight(.medium)).foregroundStyle(Color.ambre)
            }
        }
    }

    // MARK: Mois

    private var mois: some View {
        let colonnes = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .top), count: 7)
        let moisMontre = cal.component(.month, from: reference)
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"], id: \.self) {
                    Text($0).font(.petit.weight(.medium)).foregroundStyle(Color.texte2).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: colonnes, spacing: 6) {
                ForEach(jours, id: \.self) { d in caseMois(d, dansLeMois: cal.component(.month, from: d) == moisMontre) }
            }
        }
    }

    private func caseMois(_ d: Date, dansLeMois: Bool) -> some View {
        let l = duJour(d)
        let double = doublons(d)
        let manque = manques(d)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("\(cal.component(.day, from: d))").font(.secondaire.weight(estAujourdhui(d) ? .bold : .regular))
                    .foregroundStyle(estAujourdhui(d) ? Color.action : dansLeMois ? Color.texte : Color.texte3)
                Spacer()
                if !manque.isEmpty {
                    Image(systemName: "exclamationmark.circle.fill").font(.petit).foregroundStyle(Color.rouge)
                        .help("manque " + manque.joined(separator: " et "))
                }
                if !double.isEmpty { Image(systemName: "square.on.square").font(.petit).foregroundStyle(Color.ambre).help("doublon") }
            }
            ForEach(l.prefix(4)) { p in
                Button { detail = p } label: {
                    HStack(spacing: 4) {
                        BadgeReseau(reseau: p.reseau, petit: true)
                        Text(heure(p)).font(.petit.monospacedDigit()).foregroundStyle(Color.texte)
                        Text(StylePublication.espace(p.compte)).font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: StylePublication.statut(p).symbole).font(.system(size: 10))
                            .foregroundStyle(StylePublication.statut(p).couleur)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.eleve))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(double.contains(p.compte) ? Color.ambre : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            if l.count > 4 { Text("+ \(l.count - 4)").font(.petit).foregroundStyle(Color.texte2) }
            if !manque.isEmpty && l.isEmpty { Text("manque les 6 comptes").font(.petit).foregroundStyle(Color.rouge) }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(dansLeMois ? Color.surface : Color.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(estAujourdhui(d) ? Color.action.opacity(0.6) : Color.separateur.opacity(0.5)))
    }

    private func heure(_ p: Publication) -> String {
        guard let d = p.prevu else { return "--:--" }
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Le réseau en pastille de couleur avec son symbole.
struct BadgeReseau: View {
    let reseau: ReseauPublication
    var petit = false
    var body: some View {
        Image(systemName: StylePublication.symbole(reseau))
            .font(.system(size: petit ? 7 : 9, weight: .bold))
            .foregroundStyle(StylePublication.encre(reseau))
            .frame(width: petit ? 13 : 18, height: petit ? 13 : 18)
            .background(StylePublication.couleur(reseau), in: RoundedRectangle(cornerRadius: petit ? 3 : 5))
    }
}

/// Une publication dans la semaine : couverture, heure, réseau et compte, statut.
struct CartePublicationPlanning: View {
    let publication: Publication
    let doublon: Bool
    let ouvrir: () -> Void

    var body: some View {
        let p = publication
        let s = StylePublication.statut(p)
        Button(action: ouvrir) {
            HStack(alignment: .top, spacing: 7) {
                VignettePublication(publication: p).frame(width: 38, height: 67).clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(heureParis(p)).font(.ligneForte.monospacedDigit()).foregroundStyle(Color.texte)
                    HStack(spacing: 4) {
                        BadgeReseau(reseau: p.reseau, petit: true)
                        Text(StylePublication.espace(p.compte)).font(.petit.weight(.medium)).foregroundStyle(Color.texte).lineLimit(1)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: s.symbole).font(.system(size: 9))
                        Text(s.texte).font(.petit).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(s.couleur)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.eleve, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9).fill(StylePublication.couleur(p.reseau)).frame(width: 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(doublon ? Color.ambre : Color.separateur.opacity(0.5), lineWidth: doublon ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help("\(ComptePublication.trouver(p.compte)?.nom ?? p.compte) · « \(Publications.apercu(p)) »")
    }

    private func heureParis(_ p: Publication) -> String {
        guard let d = p.prevu else { return "--:--" }
        let c = PlanningPublicationsVue.calendrier.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// La couverture (ou l'image de la vidéo à 1 s), chargée hors du fil principal et gardée en mémoire.
struct VignettePublication: View {
    let publication: Publication
    @State private var image: NSImage?
    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            Rectangle().fill(StylePublication.couleur(publication.reseau).opacity(0.18))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film").font(.system(size: 12)).foregroundStyle(Color.texte3)
            }
        }
        .task(id: publication.id + publication.couverture) {
            let cle = (publication.id + publication.couverture) as NSString
            if let i = Self.cache.object(forKey: cle) { image = i; return }
            let p = publication
            let i = await Task.detached(priority: .utility) { Publications.vignette(p).flatMap { NSImage(contentsOf: $0) } }.value
            if let i { Self.cache.setObject(i, forKey: cle) }
            image = i
        }
    }
}

/// Le détail d'une publication : couverture, compte, heure, statut, titre, légende, couverture prévue, actions.
struct DetailPublicationVue: View {
    @Environment(Etat.self) private var etat
    let publication: Publication
    let valider: () -> Void
    let publiee: () -> Void
    let fermer: () -> Void
    @State private var copie = false

    var body: some View {
        let p = publication
        let s = StylePublication.statut(p)
        HStack(alignment: .top, spacing: 20) {
            VignettePublication(publication: p).frame(width: 180, height: 320).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    BadgeReseau(reseau: p.reseau)
                    Text(ComptePublication.trouver(p.compte)?.nom ?? p.compte).font(.titreSection).foregroundStyle(Color.texte)
                    Spacer()
                    Pastille(texte: s.texte, couleur: s.couleur)
                }
                Text(Publications.heureParis(p.prevuLe)).font(.ligne).foregroundStyle(Color.texte2)
                if !p.titre.isEmpty {
                    champ("Titre") { Text(p.titre).font(.ligneForte).foregroundStyle(Color.texte).textSelection(.enabled) }
                }
                champ(p.reseau == .youtube ? "Description" : "Légende") {
                    ScrollView {
                        Text(p.texte.isEmpty ? "(vide)" : p.texte).font(.ligne).foregroundStyle(Color.texte)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                    .frame(maxHeight: 140)
                }
                champ("Couverture") {
                    Text(Publications.couvertureTexte(p)).font(.secondaire).foregroundStyle(Color.texte)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !p.raison.isEmpty {
                    Text(p.raison).font(.secondaire).foregroundStyle(p.etat == "echec" || p.etat == "reconnexion" ? Color.rouge : Color.texte2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !p.plugkit.isEmpty {
                    Text(p.plugkitReveilLe.isEmpty
                         ? "Remplace le post PlugKit \(p.plugkit) : en validant, PILOTE est prévenu de le retirer."
                         : "Remplace le post PlugKit \(p.plugkit) : PILOTE prévenu de le retirer le \(Publications.heureParis(p.plugkitReveilLe)).")
                        .font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
                }
                if p.reseau == .tiktok {
                    Text("TikTok : la légende et la couverture se mettent dans l'app TikTok, en publiant le brouillon (l'API ne les prend pas).")
                        .font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    if p.etat == "a_valider" { BoutonPrincipal(titre: "Valider et programmer", symbole: "checkmark", action: valider) }
                    if p.reseau == .tiktok && p.etat == "envoye" && p.phase == "boite" {
                        BoutonPrincipal(titre: "Publiée", symbole: "checkmark", action: publiee)
                    }
                    Button("Voir la vidéo") { etat.apercu = p.fichier; fermer() }
                    Button(copie ? "Légende copiée" : "Copier la légende") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(p.texte, forType: .string)
                        copie = true
                    }
                    .disabled(p.texte.isEmpty)
                    if !p.lien.isEmpty, let u = URL(string: p.lien) { Link("Ouvrir", destination: u) }
                    Spacer()
                    Button("Fermer", action: fermer).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 640, height: 400)
    }

    private func champ<C: View>(_ titre: String, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre).font(.petit).foregroundStyle(Color.texte2)
            contenu()
        }
    }
}
