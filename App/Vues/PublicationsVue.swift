// Publications (08/11, Sacha : « on va créer un PlugKit directement dans Pilote », pour Instagram et YouTube ; puis « on fait
// aussi Tiktok » : brouillon dans la boîte TikTok, publié par Sacha depuis l'app).
// Sacha choisit la vidéo, les comptes, le titre, le texte et l'heure ; « Programmer la publication » vaut sa validation du texte et
// de la vidéo exacts. Ce qu'une session a proposé attend ici son « Valider ». Les comptes se (re)connectent d'un bouton.
// L'envoi : l'agent launchd et Shared/Publication.swift. Le réseau et le trousseau : seulement l'outil `pilote` (lancé d'ici).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum OngletPublications: String, CaseIterable, Identifiable {
    case planning = "Planning", liste = "Liste"
    var id: String { rawValue }
    var titre: String {
        switch self {
        case .planning: return L("Planning")
        case .liste: return L("Liste")
        }
    }
}

struct PublicationsVue: View {
    @Environment(Etat.self) private var etat
    @State private var comptes: [EtatComptePublication] = []
    @State private var publications: [Publication] = []
    @State private var agentCharge = true
    @State private var erreur: String?
    @State private var enCours: Set<String> = []
    @State private var message: String?
    @State private var feuilleInstagram: ComptePublication?
    @State private var onglet: OngletPublications = .planning
    @State private var actualisation = 0

    // Le formulaire
    @State private var fichier: URL?
    @State private var choisis: Set<String> = []
    @State private var titre = ""
    @State private var texte = ""
    @State private var le = Date().addingTimeInterval(86400)
    @State private var ia = false
    @State private var avertissements: [String] = []
    @State private var refus: [String] = []
    @State private var couverture: URL?
    @State private var avecInstant = false
    @State private var instant: Double = 1
    @State private var apercuCouverture: NSImage?
    @State private var preparation = false

    private var aValider: [Publication] { publications.filter { $0.etat == "a_valider" } }
    private var actives: [Publication] { publications.filter { ["planifie", "envoi", "envoye", "reconnexion"].contains($0.etat) } }
    private var terminees: [Publication] { publications.filter { ["publie", "echec", "annule"].contains($0.etat) }.reversed() }
    private var avecYouTube: Bool { choisis.contains { ComptePublication.trouver($0)?.reseau == .youtube } }
    private var avecInstagram: Bool { choisis.contains { ComptePublication.trouver($0)?.reseau == .instagram } }
    private var avecTikTok: Bool { choisis.contains { ComptePublication.trouver($0)?.reseau == .tiktok } }

    var body: some View {
        ScrollViewReader { defilement in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    EnTete(titre: L("Publications"), detail: L("YouTube, Instagram et TikTok, depuis votre Mac."))
                    Spacer()
                    Picker("", selection: $onglet) {
                        ForEach(OngletPublications.allCases) { Text($0.titre).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                .id("haut")
                if !agentCharge {
                    EtatErreur(texte: L("L'agent de publication n'est pas lancé : rien ne part tant qu'il ne tourne pas."))
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
                }
                if let erreur { EtatErreur(texte: erreur).background(Color.surface, in: RoundedRectangle(cornerRadius: 12)) }
                if let message {
                    Text(message).font(.secondaire).foregroundStyle(Color.vert)
                }
                switch onglet {
                case .planning:
                    if !aValider.isEmpty { carteAValider }
                    PlanningPublicationsVue(actualisation: actualisation, valider: valider) { jour in
                        le = Self.memeHeure(le, jour: jour)
                        withAnimation { defilement.scrollTo("programmer", anchor: .top) }
                    }
                    .id("planning")
                    carteProgrammer.id("programmer")
                    carteComptes
                case .liste:
                    carteComptes
                    if !aValider.isEmpty { carteAValider }
                    carteProgrammer.id("programmer")
                    carteActives
                    if !terminees.isEmpty { carteTerminees }
                }
            }
            .padding(28)
        }
        // macOS donne le focus au champ Texte à l'ouverture et fait défiler jusqu'à lui :
        // on revient en haut pour voir l'en-tête et le planning.
        // PILOTE_DEFILER=planning descend directement au planning (captures de vérification).
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            defilement.scrollTo(ProcessInfo.processInfo.environment["PILOTE_DEFILER"] ?? "haut", anchor: .top)
        }
        }
        .task {
            while !Task.isCancelled {
                charger()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .sheet(item: $feuilleInstagram) { c in
            FeuilleJetonInstagram(compte: c) { resultat in
                feuilleInstagram = nil
                if let resultat { message = resultat }
                charger()
            }
        }
    }

    private func charger() {
        guard let stock = etat.stock else { erreur = L("La base de Pilote n'est pas ouverte."); return }
        do {
            comptes = try Publications.comptes(stock)
            publications = try Publications.liste(stock)
        } catch { erreur = "\(error)" }
        agentCharge = Publications.agentCharge()
        actualisation += 1
    }

    /// Le jour choisi dans le planning, à l'heure déjà choisie (18 h si elle est passée).
    static func memeHeure(_ heure: Date, jour: Date) -> Date {
        let cal = PlanningPublicationsVue.calendrier
        let h = cal.dateComponents([.hour, .minute], from: heure)
        var d = cal.date(bySettingHour: h.hour ?? 18, minute: h.minute ?? 0, second: 0, of: jour) ?? jour
        if d < Date().addingTimeInterval(20 * 60) { d = cal.date(bySettingHour: 18, minute: 0, second: 0, of: jour) ?? d }
        return d
    }

    // MARK: Comptes

    private var carteComptes: some View {
        Carte(titre: L("Comptes"), detail: L("un clic pour connecter ou reconnecter")) {
            ForEach(Array(ComptePublication.tous.enumerated()), id: \.element.id) { i, c in
                LigneCarte(dernier: i == ComptePublication.tous.count - 1) { ligneCompte(c) }
            }
        }
    }

    private func ligneCompte(_ c: ComptePublication) -> some View {
        let e = comptes.first { $0.compte == c.id }
        let etatCompte = e?.etat ?? "jamais"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.nom).font(.ligneForte).foregroundStyle(Color.texte)
                if let lu = e?.lu, !lu.isEmpty, etatCompte == "connecte" {
                    Text("Connecté à \(lu)").font(.petit).foregroundStyle(Color.texte2)
                }
                // Connexion en cours ou ratée (écrit par l'outil : reste visible même après un changement d'écran).
                if let r = e?.raison, !r.isEmpty {
                    Text(r).font(.petit).foregroundStyle(r.hasPrefix("connexion en cours") ? Color.texte2 : Color.rouge)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            switch etatCompte {
            case "connecte": Pastille(texte: L("connecté"), couleur: .vert)
            case "a_reconnecter": Pastille(texte: L("à reconnecter"), couleur: .rouge)
            default: Pastille(texte: L("pas connecté"), couleur: .texte2)
            }
            if enCours.contains(c.id) {
                ProgressView().controlSize(.small)
                Text(c.reseau == .youtube ? "Choisissez \(c.poignee) dans la page Google"
                     : c.reseau == .tiktok ? "Autorisez avec le compte \(c.nom) dans la page TikTok" : "…").font(.petit).foregroundStyle(Color.texte2)
            } else {
                Button(etatCompte == "jamais" ? "Connecter" : "Reconnecter") { connecter(c) }
            }
        }
    }

    private func connecter(_ c: ComptePublication) {
        if c.reseau == .instagram { feuilleInstagram = c; return }
        enCours.insert(c.id)
        erreur = nil
        Task {
            let r = await Self.outil(["publication", "connecter", c.id])
            enCours.remove(c.id)
            if r.code == 0 { message = L("\(c.nom) : connecté.") } else { erreur = Self.raison(r) }
            charger()
        }
    }

    // MARK: À valider (proposées par une session)

    private var carteAValider: some View {
        Carte(titre: L("À valider"), detail: L("proposées par une session : rien ne part sans votre clic")) {
            ForEach(aValider) { p in
                LigneCarte(dernier: p.id == aValider.last?.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        enTetePublication(p)
                        if !p.titre.isEmpty { Text("Titre : \(p.titre)").font(.ligne).foregroundStyle(Color.texte) }
                        Text(p.texte.isEmpty ? L("(texte vide)") : p.texte).font(.ligne).foregroundStyle(Color.texte)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        if p.ia { Text("Contenu réaliste généré ou modifié par IA : signalé à YouTube").font(.petit).foregroundStyle(Color.texte2) }
                        if !p.plugkit.isEmpty {
                            Text("Remplace un post PlugKit : en validant, PILOTE est prévenu de le retirer (sinon double publication).")
                                .font(.petit).foregroundStyle(Color.texte2)
                        }
                        HStack(spacing: 10) {
                            BoutonPrincipal(titre: L("Valider et programmer"), symbole: "checkmark") { valider(p) }
                            Button("Voir la vidéo") { etat.apercu = p.fichier }
                            Button("Refuser") { annuler(p) }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func valider(_ p: Publication) {
        guard let stock = etat.stock else { return }
        do {
            try Publications.valider(stock, id: p.id, empreinte: p.empreinte, par: "\(Moi.nom) (app)")
            Publications.reveillerAgent()
            message = L("Validée : \(ComptePublication.trouver(p.compte)?.nom ?? p.compte), \(Publications.heureAffichee(p.prevuLe)).")
            erreur = nil
        } catch { erreur = "\(error)" }
        charger()
    }

    // MARK: Programmer

    private var carteProgrammer: some View {
        Carte(titre: L("Programmer une vidéo"), detail: L("vous validez ce texte et cette vidéo en cliquant")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(fichier == nil ? "Choisir la vidéo…" : "Changer de vidéo…") { choisirFichier() }
                    if let fichier {
                        Text(fichier.lastPathComponent).font(.ligne).foregroundStyle(Color.texte).lineLimit(1).truncationMode(.middle)
                        Button("Voir") { etat.apercu = fichier.path }.buttonStyle(.link)
                    }
                    Spacer()
                }
                HStack(spacing: 14) {
                    ForEach(ComptePublication.tous) { c in
                        Toggle(isOn: Binding(get: { choisis.contains(c.id) }, set: { if $0 { choisis.insert(c.id) } else { choisis.remove(c.id) } })) {
                            Text(c.nom.replacingOccurrences(of: " · ", with: " ")).font(.secondaire)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                if avecYouTube {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Titre YouTube (\(titre.count)/100)").font(.petit).foregroundStyle(titre.count > 100 ? Color.rouge : Color.texte2)
                        TextField("Titre", text: $titre).textFieldStyle(.roundedBorder)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(libelleTexte).font(.petit).foregroundStyle((avecInstagram || avecTikTok) && texte.count > 2200 ? Color.rouge : Color.texte2)
                    TextEditor(text: $texte).font(.ligne).frame(minHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.separateur))
                }
                HStack(spacing: 14) {
                    DatePicker("Le", selection: $le, in: Date().addingTimeInterval(15 * 60)..., displayedComponents: [.date, .hourAndMinute])
                        .fixedSize()
                    if avecYouTube {
                        Toggle("Contenu réaliste généré ou modifié par IA", isOn: $ia).toggleStyle(.checkbox).font(.secondaire)
                    }
                    Spacer()
                }
                ligneCouverture
                if avecInstagram {
                    Text("Instagram : Pilote publie à l'heure. Le Mac doit être allumé et éveillé ; avec plus de 30 min de retard, la vidéo ne part pas et vous êtes prévenu.")
                        .font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
                }
                if avecYouTube {
                    Text("YouTube : la vidéo part tout de suite en privé et YouTube la publie seul à l'heure, Mac éteint compris.")
                        .font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
                }
                if avecTikTok {
                    Text("TikTok : 15 min avant l'heure, Pilote envoie la vidéo en brouillon dans votre boîte TikTok (rien de public). Vous la publiez depuis l'app TikTok en collant la légende ; Pilote vous prévient.")
                        .font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(refus, id: \.self) { r in Text(r).font(.secondaire).foregroundStyle(Color.rouge).fixedSize(horizontal: false, vertical: true) }
                ForEach(avertissements, id: \.self) { a in Text(a).font(.secondaire).foregroundStyle(Color.ambre).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 10) {
                    BoutonPrincipal(titre: L("Programmer la publication"), symbole: "calendar.badge.plus") { programmer() }
                        .disabled(fichier == nil || choisis.isEmpty || preparation)
                    if preparation {
                        ProgressView().controlSize(.small)
                        Text("Préparation de la vidéo… (jusqu'à 1 min par réseau)").font(.petit).foregroundStyle(Color.texte2)
                    }
                    Spacer()
                }
            }
            // Pendant la préparation, le formulaire ne bouge plus : c'est lui qui sera vidé une fois la vidéo programmée.
            .disabled(preparation)
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
    }

    private var cleApercuCouverture: String {
        "\(fichier?.path ?? "")|\(couverture?.path ?? "")|\(avecInstant)|\(instant)"
    }

    private var ligneCouverture: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.separateur.opacity(0.35))
                if let apercuCouverture {
                    Image(nsImage: apercuCouverture).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(Color.texte3)
                }
            }
            .frame(width: 54, height: 96).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 6) {
                Text("Couverture").font(.petit).foregroundStyle(Color.texte2)
                HStack(spacing: 10) {
                    Button(couverture == nil ? "Choisir une image…" : "Changer d'image…") { choisirCouverture() }
                    if let couverture {
                        Text(couverture.lastPathComponent).font(.secondaire).foregroundStyle(Color.texte).lineLimit(1).truncationMode(.middle)
                        Button("Retirer") { self.couverture = nil }.buttonStyle(.link)
                    }
                }
                HStack(spacing: 6) {
                    Toggle("Image de la vidéo à", isOn: $avecInstant).toggleStyle(.checkbox).font(.secondaire)
                    TextField("", value: $instant, format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder).frame(width: 54).disabled(!avecInstant)
                    Text("s").font(.secondaire).foregroundStyle(Color.texte2)
                }
                Text(noteCouverture).font(.petit).foregroundStyle(Color.texte2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .task(id: cleApercuCouverture) {
            let (f, c, a, t) = (fichier, couverture, avecInstant, instant)
            apercuCouverture = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                if let c { return NSImage(contentsOf: c) }
                guard a, let f else { return nil }
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pilote-apercu-couverture.jpg")
                return Publications.imageDeLaVideo(f, a: t, vers: tmp, taille: 400) ? NSImage(contentsOf: tmp) : nil
            }.value
        }
    }

    private var noteCouverture: String {
        var l: [String] = []
        if avecYouTube { l.append(L("YouTube : miniature posée une fois la vidéo traitée (l'image, sinon celle de la vidéo à l'instant choisi).")) }
        if avecInstagram { l.append(avecInstant ? L("Instagram : l'image de la vidéo à l'instant choisi.") : L("Instagram : cochez un instant de la vidéo (l'API ne prend pas d'image), sinon la 1re image.")) }
        if avecTikTok { l.append(L("TikTok : à choisir dans l'app TikTok en publiant le brouillon.")) }
        return l.isEmpty ? L("Choisissez d'abord les comptes.") : l.joined(separator: " ")
    }

    private func choisirCouverture() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.jpeg, .png]
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.message = L("L'image de couverture (.jpg ou .png, verticale 1080 × 1920 de préférence)")
        if p.runModal() == .OK, let u = p.url { couverture = u }
    }

    private var libelleTexte: String {
        var l: [String] = []
        if avecYouTube { l.append(L("description YouTube")) }
        if avecInstagram { l.append(L("légende Instagram")) }
        if avecTikTok { l.append(L("légende TikTok (à coller dans l'app)")) }
        guard !l.isEmpty else { return L("Texte") }
        let t = l.joined(separator: ", ")
        let titre = t.prefix(1).uppercased() + t.dropFirst()
        // Pas de L() : la clé ne serait que « %@ (%lld/%lld) », sans mot. Les nombres suivent la langue (2 200 / 2,200 / 2200).
        let compte = texte.count.formatted(.number.locale(Loc.locale)), plafond = 2200.formatted(.number.locale(Loc.locale))
        return avecInstagram || avecTikTok ? "\(titre) (\(compte)/\(plafond))" : titre
    }

    private func choisirFichier() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]
        p.allowsMultipleSelection = false
        p.canChooseDirectories = false
        p.message = L("La vidéo à publier (verticale, .mp4 ou .mov)")
        if p.runModal() == .OK, let u = p.url { fichier = u }
    }

    /// La préparation (empreinte, copies Instagram et TikTok ré-encodées : jusqu'à 1 min par réseau) tourne hors du fil
    /// principal, sur sa propre connexion à la base : l'app reste utilisable pendant ce temps.
    private func programmer() {
        guard let stock = etat.stock, let fichier, !preparation else { return }
        refus = []
        avertissements = []
        erreur = nil
        let quand = le
        let demande = DemandePublication(comptes: ComptePublication.tous.map(\.id).filter(choisis.contains),
                                         fichier: fichier.path, titre: titre, texte: texte, prevuLe: quand,
                                         ia: ia, par: "\(Moi.nom) (app)", couverture: couverture?.path ?? "",
                                         couvertureA: avecInstant ? instant : nil)
        let chemin = stock.base.chemin
        preparation = true
        Task {
            let resultat = await Task.detached(priority: .userInitiated) { () -> Result<Publications.Programmees, Error> in
                Result { try Publications.programmer(Stockage(base: try Base(chemin: chemin)), demande, validee: true) }
            }.value
            preparation = false
            switch resultat {
            case .success(let r):
                Publications.reveillerAgent()
                avertissements = r.avertissements
                let noms = r.publications.map { ComptePublication.trouver($0.compte)?.nom ?? $0.compte }.joined(separator: ", ")
                message = L("Programmée : \(noms), \(Publications.heureAffichee(quand)).")
                self.fichier = nil
                titre = ""
                texte = ""
                ia = false
                choisis = []
                couverture = nil
                avecInstant = false
            case .failure(let e as RefusPublication):
                refus = e.raisons
            case .failure(let e):
                erreur = "\(e)"
            }
            charger()
        }
    }

    // MARK: Programmées et terminées

    private var carteActives: some View {
        Carte(titre: L("Programmées"), detail: actives.isEmpty ? nil : L("\(actives.count) à venir")) {
            if actives.isEmpty {
                EtatVide(texte: L("Aucune publication à venir."))
            } else {
                ForEach(actives) { p in
                    LigneCarte(dernier: p.id == actives.last?.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            enTetePublication(p)
                            Text(Publications.affichage(p)).font(.petit).foregroundStyle(p.etat == "reconnexion" ? Color.rouge : Color.texte2)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 10) {
                                Button("Voir la vidéo") { etat.apercu = p.fichier }.buttonStyle(.link)
                                if p.reseau == .tiktok && !p.texte.isEmpty {
                                    Button("Copier la légende") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(p.texte, forType: .string)
                                        message = L("Légende TikTok copiée : collez-la dans l'app TikTok (la couverture s'y choisit aussi).")
                                    }.buttonStyle(.link)
                                }
                                if p.etat != "envoi" {
                                    if enCours.contains(p.id) { ProgressView().controlSize(.small) } else {
                                        Button("Annuler la publication") { annuler(p) }.buttonStyle(.link)
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var carteTerminees: some View {
        Carte(titre: L("Terminées"), detail: L("30 derniers jours")) {
            ForEach(terminees) { p in
                LigneCarte(dernier: p.id == terminees.last?.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        enTetePublication(p)
                        if p.etat == "echec" {
                            Text(p.raison).font(.petit).foregroundStyle(Color.rouge).fixedSize(horizontal: false, vertical: true)
                        }
                        if !p.lien.isEmpty && p.etat == "publie", let u = URL(string: p.lien) {
                            Link("Ouvrir la publication", destination: u).font(.petit)
                        }
                    }
                }
            }
        }
    }

    private func enTetePublication(_ p: Publication) -> some View {
        HStack(spacing: 8) {
            Text(ComptePublication.trouver(p.compte)?.nom ?? p.compte).font(.ligneForte).foregroundStyle(Color.texte)
            Text(Publications.heureAffichee(p.prevuLe)).font(.secondaire).foregroundStyle(Color.texte2)
            Text(Publications.entreGuillemets(Publications.apercu(p))).font(.secondaire).foregroundStyle(Color.texte2).lineLimit(1)
            Spacer()
            Pastille(texte: libelle(p), couleur: couleur(p))
        }
    }

    private func libelle(_ p: Publication) -> String {
        switch p.etat {
        case "a_valider": return L("à valider")
        case "planifie": return L("prévue")
        case "envoi": return L("envoi en cours")
        case "envoye":
            switch p.reseau {
            case .youtube: return L("chez YouTube")
            case .instagram: return L("prête chez Instagram")
            case .tiktok: return p.phase == "boite" ? L("brouillon TikTok à publier") : L("chez TikTok")
            }
        case "publie": return L("publiée")
        case "echec": return L("pas publiée")
        case "reconnexion": return L("compte à reconnecter")
        case "annule": return L("annulée")
        default: return p.etat
        }
    }

    private func couleur(_ p: Publication) -> Color {
        switch p.etat {
        case "publie": return .vert
        case "echec", "reconnexion": return .rouge
        case "a_valider": return .ambre
        case "annule": return .texte2
        default: return .action
        }
    }

    /// Annuler passe par l'outil : une vidéo déjà chez YouTube y est supprimée (trousseau et réseau : l'outil seul).
    private func annuler(_ p: Publication) {
        enCours.insert(p.id)
        erreur = nil
        Task {
            let r = await Self.outil(["publication", "annuler", p.id, "--par", "\(Moi.nom) (app)"])
            enCours.remove(p.id)
            if r.code != 0 { erreur = Self.raison(r) } else { message = L("Annulée.") }
            charger()
        }
    }

    // MARK: L'outil

    static func outil(_ arguments: [String]) async -> (code: Int32, sortie: String, erreur: String) {
        await Task.detached { FileEnvoi.lancer(FileEnvoi.outil.path, arguments) }.value
    }

    static func raison(_ r: (code: Int32, sortie: String, erreur: String)) -> String {
        let e = r.erreur.trimmingCharacters(in: .whitespacesAndNewlines)
        let lignes = e.split(separator: "\n").filter { !$0.hasPrefix("Page Google ouverte") }
        return lignes.last.map(String.init) ?? L("L'outil n'a pas répondu (code \(Int(r.code))).")
    }
}

/// Instagram : le jeton se génère dans le tableau de bord Meta (connexion unifiée : jeton sans expiration, une seule fois).
struct FeuilleJetonInstagram: View {
    let compte: ComptePublication
    let fini: (String?) -> Void
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connecter \(compte.nom)").font(.titreSection).foregroundStyle(Color.texte)
            VStack(alignment: .leading, spacing: 8) {
                etape(1, L("Sur instagram.com, connecté en @\(compte.poignee) : Paramètres › Autorisations du site Web › Applications et sites Web › Invitations à tester : acceptez « Pilote publication »."))
                etape(2, L("developers.facebook.com › « Pilote publication » › Cas d'utilisation › Instagram › Personnaliser › Configuration de l'API avec connexion unifiée › Générer des tokens d'accès."))
                etape(3, L("Sur la ligne @\(compte.poignee) : « Générer un token », cochez le compte @\(compte.poignee) à partager, puis « Copier »."))
                etape(4, L("Revenez ici et cliquez « Coller le jeton copié » (ou directement, si PILOTE l'a rangé dans le trousseau). Le presse-papiers est vidé."))
            }
            Button("Ouvrir le tableau de bord Meta") { NSWorkspace.shared.open(URL(string: "https://developers.facebook.com/apps/")!) }
                .buttonStyle(.link)
            if let erreur { Text(erreur).font(.secondaire).foregroundStyle(Color.rouge).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Fermer") { fini(nil) }
                Spacer()
                if enCours { ProgressView().controlSize(.small) }
                BoutonPrincipal(titre: L("Coller le jeton copié"), symbole: "doc.on.clipboard") { coller() }.disabled(enCours)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func etape(_ n: Int, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").font(.ligneForte).foregroundStyle(Color.texte2)
            Text(t).font(.ligne).foregroundStyle(Color.texte).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func coller() {
        enCours = true
        erreur = nil
        Task {
            let r = await PublicationsVue.outil(["publication", "connecter", compte.id])
            enCours = false
            if r.code == 0 { fini(L("\(compte.nom) : connecté.")) } else { erreur = PublicationsVue.raison(r) }
        }
    }
}
