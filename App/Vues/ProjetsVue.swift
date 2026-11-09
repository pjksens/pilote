// Projets : la carte de tout l'espace de travail. Chaque projet = un dossier, son état, ses documents,
// les sessions qui y travaillent et le journal de ce qu'elles y ont fait.
import AppKit
import SwiftUI

struct ProjetsVue: View {
    @Environment(Etat.self) private var etat
    @State private var filtre = ""
    @State private var archives = false
    @State private var edition: Projet?

    private var choisi: Projet? { etat.projets.first { $0.id == etat.projetSelection } }

    private func liste(_ espace: String) -> [Projet] {
        let f = filtre.trimmingCharacters(in: .whitespaces).lowercased()
        return etat.projets.filter { p in
            p.espace == espace && (archives || p.statut != "archive")
                && (f.isEmpty || "\(p.nom) \(p.description) \(p.dossier)".lowercased().contains(f))
        }
    }

    var body: some View {
        @Bindable var etat = etat
        HStack(spacing: 0) {
            List(selection: $etat.projetSelection) {
                ForEach(Libelles2.espaces, id: \.0) { cle, nom in
                    let projets = liste(cle)
                    if !projets.isEmpty {
                        Section(nom) {
                            ForEach(projets) { p in LigneProjet(projet: p).tag(p.id) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .frame(width: 340)
            Rectangle().fill(Color.separateur).frame(width: 0.5)
            Group {
                if let p = choisi {
                    FicheProjetVue(projet: p, modifier: { edition = p })
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choisissez un projet").font(.titreSection).foregroundStyle(Color.texte)
                        Text("Chaque projet montre son dossier, son état, ses documents clés et ce que les agents y ont fait.")
                            .font(.secondaire).foregroundStyle(Color.texte2)
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                EnTete(titre: "Projets", detail: "\(etat.projets.filter { $0.statut != "archive" }.count) projets, où est quoi et qui y travaille")
                TextField("", text: $filtre, prompt: Text("Filtrer les projets"))
                    .textFieldStyle(.roundedBorder).frame(width: 220)
                Toggle("Archivés", isOn: $archives).toggleStyle(.checkbox).font(.secondaire)
                BoutonPrincipal(titre: "Nouveau projet", symbole: "plus") {
                    edition = Projet(id: "", espace: "kryva")
                }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
            .background(Color.fond)
        }
        .sheet(item: $edition) { p in EditionProjet(projet: p) }
    }
}

struct LigneProjet: View {
    @Environment(Etat.self) private var etat
    let projet: Projet

    var body: some View {
        let actifs = etat.agents(dans: projet)
        let dernier = etat.journal.first { $0.projetId == projet.id }
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(actifs.contains { $0.etat == "busy" } ? Color.vert : (actifs.isEmpty ? Color.clear : Color.texte3))
                .frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(projet.nom).font(.ligne).foregroundStyle(projet.statut == "archive" ? Color.texte3 : Color.texte).lineLimit(1)
                Text(projet.description).font(.petit).foregroundStyle(Color.texte2).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let d = dernier.flatMap({ Dates.date($0.le) }) {
                Text(d.formatted(.relative(presentation: .named).locale(Locale(identifier: "fr_FR"))))
                    .font(.petit).foregroundStyle(Color.texte3).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

struct FicheProjetVue: View {
    @Environment(Etat.self) private var etat
    let projet: Projet
    let modifier: () -> Void
    @State private var etatFichier: String?
    @State private var sessions: [SessionClaude] = []

    private var existe: Bool { FileManager.default.fileExists(atPath: projet.cheminComplet) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(projet.nom).font(.system(size: 24, weight: .bold)).tracking(-0.4).foregroundStyle(Color.texte)
                        Pastille(texte: Libelles2.statut(projet.statut),
                                 couleur: projet.statut == "actif" ? .vert : (projet.statut == "en_pause" ? .ambre : .texte3))
                        Spacer()
                        Button("Modifier", action: modifier).controlSize(.small)
                    }
                    if !projet.description.isEmpty {
                        Text(projet.description).font(.ligne).foregroundStyle(Color.texte2)
                    }
                    Text(projet.dossier.isEmpty ? "Pas de dossier" : projet.dossier + (existe ? "" : " (introuvable)"))
                        .font(.secondaire.monospaced()).foregroundStyle(existe ? Color.texte3 : Color.rouge)
                        .textSelection(.enabled)
                }
                actions
                carteEtat
                agentsEnCours
                if !projet.listeDocuments.isEmpty { documents }
                journal
                if !projet.notes.isEmpty {
                    Carte(titre: "Notes") {
                        Text(projet.notes).font(.secondaire).foregroundStyle(Color.texte).textSelection(.enabled)
                            .padding(.horizontal, 16).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(28)
        }
        .task(id: projet.id) {
            etatFichier = projet.lireEtat()
            let dossier = projet.cheminComplet
            sessions = await Task.detached { Claude.sessions(limite: 200) }.value
                .filter { $0.dossier == dossier || $0.dossier.hasPrefix(dossier + "/") }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if existe {
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: projet.cheminComplet)) } label: {
                    Label("Ouvrir le dossier", systemImage: "folder")
                }
            }
            if let u = URL(string: projet.site), !projet.site.isEmpty {
                Button { NSWorkspace.shared.open(u) } label: { Label("Site", systemImage: "safari") }
            }
            if !projet.depot.isEmpty, let u = URL(string: "https://github.com/\(projet.depot)") {
                Button { NSWorkspace.shared.open(u) } label: { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
            if existe {
                Button { Claude.nouvelle(consigne: "", dossier: projet.cheminComplet) } label: {
                    Label("Nouvelle session ici", systemImage: "sparkle")
                }
                .help("Ouvre une nouvelle session dans l'app Claude, dans ce dossier")
            }
        }
        .controlSize(.regular)
    }

    private var carteEtat: some View {
        Carte(titre: "Où en est le projet", detail: etatFichier == nil ? nil : "ETAT.md") {
            if let t = etatFichier {
                Text(t).font(.secondaire).foregroundStyle(Color.texte).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.bottom, 14).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EtatVide(texte: "Pas encore d'ETAT.md dans ce dossier. Les sessions l'écrivent en fin de travail (fait, en cours, prochaine étape, fichiers clés).")
            }
        }
    }

    @ViewBuilder private var agentsEnCours: some View {
        let actifs = etat.agents(dans: projet)
        let anciennes = sessions.filter { s in !actifs.contains { $0.sessionApp == s.id } }.prefix(5)
        if !actifs.isEmpty || !anciennes.isEmpty {
            Carte(titre: "Sessions", detail: actifs.isEmpty ? nil : "\(actifs.count) ouverte\(actifs.count > 1 ? "s" : "")") {
                ForEach(actifs) { a in
                    LigneCarte(dernier: false) { LigneActivite(activite: a) }
                }
                ForEach(Array(anciennes.enumerated()), id: \.element.id) { i, s in
                    LigneCarte(dernier: i == anciennes.count - 1) {
                        Button { Claude.ouvrir(s) } label: { LigneSession(session: s) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var documents: some View {
        Carte(titre: "Documents clés") {
            let docs = projet.listeDocuments
            ForEach(Array(docs.enumerated()), id: \.offset) { i, d in
                LigneCarte(dernier: i == docs.count - 1) {
                    LigneFichier(libelle: d.libelle, chemin: Chemins.complet(d.chemin))
                }
            }
        }
    }

    @ViewBuilder private var journal: some View {
        let entrees = etat.journal.filter { $0.projetId == projet.id }.prefix(15)
        Carte(titre: "Journal", detail: entrees.isEmpty ? nil : "ce que les agents y ont fait") {
            if entrees.isEmpty {
                EtatVide(texte: "Rien encore. Chaque fin de réponse d'une session dans ce dossier s'inscrira ici.")
            } else {
                ForEach(Array(entrees.enumerated()), id: \.element.id) { i, e in
                    LigneCarte(dernier: i == entrees.count - 1) { LigneJournal(entree: e, avecProjet: false) }
                }
            }
        }
    }
}

/// Un fichier : clic = ouvrir, bouton = montrer dans le Finder.
struct LigneFichier: View {
    @Environment(Etat.self) private var etat
    let libelle: String
    let chemin: String
    var body: some View {
        let existe = FileManager.default.fileExists(atPath: chemin)
        HStack(spacing: 10) {
            Image(systemName: existe ? "doc" : "questionmark.folder").foregroundStyle(Color.texte3)
            VStack(alignment: .leading, spacing: 1) {
                Text(libelle).font(.ligne).foregroundStyle(existe ? Color.texte : Color.texte3).lineLimit(1)
                Text(Chemins.court(chemin)).font(.petit).foregroundStyle(Color.texte3).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if existe {
                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: chemin)]) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain).foregroundStyle(Color.texte2).help("Montrer dans le Finder")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if existe { etat.montrer(chemin) } }
    }
}

struct EditionProjet: View {
    @Environment(Etat.self) private var etat
    @Environment(\.dismiss) private var fermer
    @State var projet: Projet

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(projet.id.isEmpty ? "Nouveau projet" : "Modifier le projet").font(.system(size: 19, weight: .semibold))
            Form {
                TextField("Nom", text: $projet.nom)
                TextField("En une phrase", text: $projet.description)
                Picker("Espace", selection: $projet.espace) {
                    ForEach(Libelles2.espaces, id: \.0) { Text($0.1).tag($0.0) }
                }
                Picker("Statut", selection: $projet.statut) {
                    ForEach(Libelles2.statuts, id: \.0) { Text($0.1).tag($0.0) }
                }
                HStack {
                    TextField("Dossier", text: $projet.dossier)
                    Button("Choisir…") {
                        let p = NSOpenPanel()
                        p.canChooseDirectories = true
                        p.canChooseFiles = false
                        if p.runModal() == .OK, let u = p.url { projet.dossier = Chemins.court(u.path) }
                    }
                }
                TextField("Site", text: $projet.site)
                TextField("Dépôt GitHub (propriétaire/nom)", text: $projet.depot)
                TextField("Documents clés (une ligne : « Libellé : chemin »)", text: $projet.documents, axis: .vertical)
                    .lineLimit(3...8)
                TextField("Notes", text: $projet.notes, axis: .vertical).lineLimit(2...6)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Annuler") { fermer() }.keyboardShortcut(.cancelAction)
                Button("Enregistrer") {
                    var champs: [String: Any] = [
                        "nom": projet.nom, "description": projet.description, "espace": projet.espace, "statut": projet.statut,
                        "dossier": projet.dossier, "site": projet.site, "depot": projet.depot,
                        "documents": projet.documents, "notes": projet.notes,
                    ]
                    if !projet.id.isEmpty { champs["id"] = projet.id }
                    etat.enregistrer(projet: champs)
                    fermer()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(.action)
                .disabled(projet.nom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600)
    }
}
