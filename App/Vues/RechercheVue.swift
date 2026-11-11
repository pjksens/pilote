// Chercher partout (⌘K) : projets, contacts, journal des agents et fichiers (Spotlight), d'un seul champ.
import AppKit
import SwiftUI

struct RechercheVue: View {
    @Environment(Etat.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State private var texte = ""
    @State private var resultats = ResultatsRecherche()
    @State private var cherche = false
    @FocusState private var focus: Bool

    /// Les autres pages de l'app (09/11 : ⌘K est la seule porte vers elles). Toutes tant que rien n'est tapé, sinon celles
    /// dont le nom ou le contenu contient le texte.
    private var pages: [Ecran] {
        let t = nu(texte.trimmingCharacters(in: .whitespaces))
        guard t.count >= 2 else { return Ecran.pages }
        return Ecran.pages.filter { nu($0.titre).contains(t) || nu($0.resume).contains(t) }
    }

    private func ouvrir(_ e: Ecran) {
        etat.fichePanneau = nil
        etat.apercu = nil
        etat.ecran = e
        fermer()
    }

    private var vide: Bool {
        pages.isEmpty && resultats.projets.isEmpty && resultats.contacts.isEmpty && resultats.journal.isEmpty && resultats.fichiers.isEmpty
            && !ouvreRadar && radarTrouve.isEmpty
    }

    private func nu(_ t: String) -> String { t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

    /// « radar » dans la recherche propose d'ouvrir le Radar, même s'il n'a encore aucun relevé.
    private var ouvreRadar: Bool { texte.count >= 2 && nu(texte).contains("radar") }

    /// Posts suivis par le Radar dont le compte ou la légende contient le texte (classement déjà en mémoire, aucune requête).
    private var radarTrouve: [RadarLigne] {
        let t = nu(texte.trimmingCharacters(in: .whitespaces))
        guard t.count >= 2 else { return [] }
        let tous = etat.radar.flatMap { $0.classement + $0.ecartes }
        return Array(tous.filter { nu($0.createur).contains(t) || nu($0.legende).contains(t) }.prefix(5))
    }

    private func ouvrirRadar() {
        fermer()
        // Deux feuilles ne s'enchaînent pas dans le même tour : on laisse la recherche se fermer d'abord.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { etat.radarOuvert = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.texte3)
                TextField("", text: $texte, prompt: Text("Chercher un projet, un contact, un fichier, ce qu'un agent a fait…"))
                    .textFieldStyle(.plain).font(.system(size: 17)).focused($focus)
                    .onSubmit { premier() }
                if cherche { ProgressView().controlSize(.small) }
            }
            .padding(16)
            Rectangle().fill(Color.separateur).frame(height: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !pages.isEmpty {
                        section("Pages") {
                            ForEach(pages) { e in
                                ligne(titre: e.titre, detail: e.resume, symbole: e.symbole) { ouvrir(e) }
                            }
                        }
                    }
                    if texte.trimmingCharacters(in: .whitespaces).count < 2 {
                        Text("Tapez deux lettres pour chercher un projet, un contact, un fichier ou ce qu'un agent a fait.")
                            .font(.petit).foregroundStyle(Color.texte3)
                    } else if vide && cherche {
                        EtatChargement(texte: L("Recherche dans les projets, les contacts, le journal et les fichiers…"))
                    } else if vide {
                        EtatVide(texte: L("Rien trouvé pour « \(texte) »."))
                    }
                    if ouvreRadar || !radarTrouve.isEmpty {
                        section("Radar") {
                            if ouvreRadar {
                                ligne(titre: L("Ouvrir le Radar"), detail: L("pistes du moment, classement par ratio, boîte à idées (⇧⌘R)"),
                                      symbole: "dot.radiowaves.left.and.right") { ouvrirRadar() }
                            }
                            ForEach(radarTrouve) { l in
                                ligne(titre: "@\(l.createur) · \(l.ratio.map { "×" + decimal($0) } ?? L("ratio indéterminé"))",
                                      detail: l.legende.isEmpty ? l.url : l.legende, symbole: "dot.radiowaves.left.and.right") { ouvrirRadar() }
                            }
                        }
                    }
                    if !resultats.projets.isEmpty {
                        section("Projets") {
                            ForEach(resultats.projets) { p in
                                ligne(titre: p.nom, detail: p.dossier, symbole: "folder") { etat.ouvrir(projet: p.id); fermer() }
                            }
                        }
                    }
                    if !resultats.contacts.isEmpty {
                        section("Contacts") {
                            ForEach(resultats.contacts) { c in
                                ligne(titre: c.titre, detail: c.sousTitre, symbole: "person") { etat.ouvrir(c); fermer() }
                            }
                        }
                    }
                    if !resultats.fichiers.isEmpty {
                        section("Fichiers") {
                            ForEach(resultats.fichiers, id: \.self) { f in
                                ligne(titre: (f as NSString).lastPathComponent, detail: Chemins.court((f as NSString).deletingLastPathComponent),
                                      symbole: "doc", secondaire: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) }) {
                                    etat.montrer(f); fermer()
                                }
                            }
                        }
                    }
                    if !resultats.journal.isEmpty {
                        section("Journal des agents") {
                            ForEach(resultats.journal) { e in
                                ligne(titre: e.texte, detail: "\(e.titreSession) · \(Dates.court(e.le))", symbole: "sparkle") {
                                    if !e.projetId.isEmpty { etat.ouvrir(projet: e.projetId) } else { etat.ecran = .claude }
                                    fermer()
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 720, height: 520)
        .background(Color.fond)
        .onAppear { focus = true }
        .task(id: texte) {
            let t = texte
            guard t.trimmingCharacters(in: .whitespaces).count >= 2, let stock = etat.stock else {
                resultats = ResultatsRecherche(); cherche = false; return
            }
            cherche = true
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let r = await Task.detached { (try? stock.chercherPartout(t)) ?? ResultatsRecherche() }.value
            guard !Task.isCancelled else { return }
            resultats = r
            cherche = false
        }
    }

    private func premier() {
        if ouvreRadar || (resultats.projets.isEmpty && resultats.contacts.isEmpty && resultats.fichiers.isEmpty && !radarTrouve.isEmpty) { ouvrirRadar() }
        else if let p = resultats.projets.first { etat.ouvrir(projet: p.id); fermer() }
        else if let c = resultats.contacts.first { etat.ouvrir(c); fermer() }
        else if let f = resultats.fichiers.first { etat.montrer(f); fermer() }
        else if let e = pages.first { ouvrir(e) }
    }

    private func section<C: View>(_ titre: LocalizedStringKey, @ViewBuilder _ contenu: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titre).font(.petit.weight(.semibold)).foregroundStyle(Color.texte3).padding(.bottom, 4)
            contenu()
        }
    }

    private func ligne(titre: String, detail: String, symbole: String, secondaire: (() -> Void)? = nil,
                       action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbole).foregroundStyle(Color.texte3).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(titre).font(.ligne).foregroundStyle(Color.texte).lineLimit(1)
                Text(detail).font(.petit).foregroundStyle(Color.texte3).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let secondaire {
                Button(action: secondaire) { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).foregroundStyle(Color.texte2).help("Montrer dans le Finder")
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
