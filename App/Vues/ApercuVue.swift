// Le panneau de droite (03/11, Sacha : « que je puisse ouvrir tous les fichiers depuis Pilote ») : le fichier à lire
// pour décider, sans quitter l'app. Fiche .md mise en page, texte brut, dossier = sa liste ; le reste (PDF, images,
// vidéos, pages web) par Coup d'œil. « Ouvrir dans son app » reste à un clic.
import SwiftUI
import AppKit
import QuickLookUI

struct ApercuVue: View {
    @Environment(Etat.self) private var etat
    let chemin: String

    private var url: URL { URL(fileURLWithPath: chemin) }
    private var estDossier: Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: chemin, isDirectory: &d) && d.boolValue
    }
    private var existe: Bool { FileManager.default.fileExists(atPath: chemin) }
    private var ext: String { url.pathExtension.lowercased() }
    private static let textes: Set<String> = ["txt", "log", "json", "jsonl", "csv", "tsv", "yml", "yaml", "swift", "py",
                                              "sh", "js", "ts", "tsx", "css", "toml", "env", "srt", "vtt"]

    var body: some View {
        VStack(spacing: 0) {
            entete
            Rectangle().fill(Color.separateur).frame(height: 0.5)
            if !existe {
                EtatErreur(texte: "Fichier introuvable : \(Chemins.court(chemin))")
                Spacer()
            } else if estDossier {
                ListeDossier(chemin: chemin)
            } else if ext == "md" || ext == "markdown" {
                LectureMarkdown(texte: Self.lire(url))
            } else if Self.textes.contains(ext) || ext.isEmpty {
                ScrollView {
                    Text(Self.lire(url)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.texte)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            } else {
                CoupDOeil(url: url)
            }
        }
        .background(Color.surface)
        .id(chemin)
    }

    private var entete: some View {
        HStack(spacing: 10) {
            Image(systemName: estDossier ? "folder.fill" : "doc.text.fill").foregroundStyle(Color.action)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.ligneForte).foregroundStyle(Color.texte).lineLimit(1)
                Text(Chemins.court(url.deletingLastPathComponent().path)).font(.petit).foregroundStyle(Color.texte3)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 4)
            Button { etat.apercu = url.deletingLastPathComponent().path } label: { Image(systemName: "arrow.up.left") }
                .help("Le dossier qui le contient")
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }
                .help("Ouvrir dans son app")
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                .help("Montrer dans le Finder")
            Button { etat.apercu = nil } label: { Image(systemName: "xmark") }
                .help("Fermer le panneau (Échap)").keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless).font(.system(size: 14))
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Les 400 premiers Ko : assez pour toute fiche, sans figer l'app sur un gros fichier.
    static func lire(_ url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let d = (try? h.read(upToCount: 400_000)) ?? Data()
        return String(decoding: d, as: UTF8.self)
    }
}

/// Une fiche .md lue comme une page : titres, listes, tableaux, gras et liens rendus.
struct LectureMarkdown: View {
    let texte: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(Markdown.blocs(texte).enumerated()), id: \.offset) { _, b in bloc(b) }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private func bloc(_ b: BlocMarkdown) -> some View {
        switch b {
        case .titre(let n, let t):
            Text(Self.enLigne(t)).font(.system(size: n == 1 ? 22 : (n == 2 ? 18 : 15), weight: .bold))
                .foregroundStyle(Color.texte).padding(.top, n <= 2 ? 8 : 4)
        case .puce(let r, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Color.texte3)
                Text(Self.enLigne(t)).font(.ligne).foregroundStyle(Color.texte)
            }
            .padding(.leading, CGFloat(r) * 18)
        case .numero(let r, let n, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").font(.ligne.monospacedDigit()).foregroundStyle(Color.texte2)
                Text(Self.enLigne(t)).font(.ligne).foregroundStyle(Color.texte)
            }
            .padding(.leading, CGFloat(r) * 18)
        case .tache(let fait, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: fait ? "checkmark.square.fill" : "square").foregroundStyle(fait ? Color.vert : Color.texte3)
                Text(Self.enLigne(t)).font(.ligne).foregroundStyle(fait ? Color.texte2 : Color.texte)
            }
        case .citation(let t):
            Text(Self.enLigne(t)).font(.ligne).foregroundStyle(Color.texte2)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Color.action.opacity(0.5)).frame(width: 3) }
        case .code(let t):
            Text(t).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.texte)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.fond, in: RoundedRectangle(cornerRadius: 8))
        case .tableau(let lignes):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(Array(lignes.enumerated()), id: \.offset) { i, l in
                        GridRow {
                            ForEach(Array(l.enumerated()), id: \.offset) { _, c in
                                Text(Self.enLigne(c)).font(i == 0 ? .secondaire.weight(.semibold) : .secondaire)
                                    .foregroundStyle(i == 0 ? Color.texte : Color.texte2)
                                    .frame(maxWidth: 320, alignment: .leading)
                            }
                        }
                        if i == 0 { Divider() }
                    }
                }
                .padding(10)
            }
            .background(Color.fond, in: RoundedRectangle(cornerRadius: 8))
        case .trait:
            Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.vertical, 4)
        case .paragraphe(let t):
            Text(Self.enLigne(t)).font(.ligne).foregroundStyle(Color.texte).lineSpacing(3)
        }
    }

    static func enLigne(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

/// Un dossier : ses fichiers, du plus récent au plus ancien ; un clic l'ouvre dans le panneau.
struct ListeDossier: View {
    @Environment(Etat.self) private var etat
    let chemin: String

    private var elements: [(url: URL, dossier: Bool, date: Date)] {
        let cles: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: chemin), includingPropertiesForKeys: cles,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return urls.map { u in
            let v = try? u.resourceValues(forKeys: Set(cles))
            return (u, v?.isDirectory ?? false, v?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        let liste = elements
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if liste.isEmpty { EtatVide(texte: "Dossier vide.") }
                ForEach(Array(liste.enumerated()), id: \.element.url) { i, e in
                    Button { etat.apercu = e.url.path } label: {
                        HStack(spacing: 10) {
                            Image(systemName: e.dossier ? "folder.fill" : "doc.text").foregroundStyle(e.dossier ? Color.action : Color.texte2)
                                .frame(width: 18)
                            Text(e.url.lastPathComponent).font(.ligne).foregroundStyle(Color.texte).lineLimit(1)
                            Spacer()
                            Text(e.date.formatted(.dateTime.day().month(.abbreviated))).font(.petit).foregroundStyle(Color.texte3)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if i < liste.count - 1 { Rectangle().fill(Color.separateur).frame(height: 0.5).padding(.leading, 44) }
                }
            }
        }
    }
}

/// Coup d'œil de macOS (PDF, images, vidéos, pages web, documents Office).
struct CoupDOeil: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.autostarts = true
        v.previewItem = url as NSURL
        return v
    }
    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL)?.path != url.path { v.previewItem = url as NSURL }
    }
}
