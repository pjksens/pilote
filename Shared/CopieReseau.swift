// Une copie de la vidéo par réseau, préparée à la programmation (10/11, Sacha : « pourquoi ça ne marche pas du premier coup à
// chaque fois ? Il faut régler ça »). Vu le 10/11 : TikTok accepte un fichier de 1,1 Go à 268 Mbit/s mais le brouillon n'arrive
// jamais, alors que le même à 25 Mbit/s passe ; Instagram refuse 268 Mbit/s, et HEVC.
// Règles (PILOTE, 10/11) : on garde la taille d'image (2160×3840) et les images par seconde, jamais réduites ; H.264 obligatoire ;
// seul le débit est ramené au profil du réseau ; YouTube reçoit la vidéo telle quelle. Une vidéo déjà dans le profil n'est pas
// réencodée (perte de qualité pour rien) : elle est seulement réécrite avec l'index en tête (+faststart).
import Foundation

enum CopieReseau {
    struct Sonde: Equatable {
        var codec: String
        var pixFmt: String
        var largeur: Int
        var hauteur: Int
        var fps: Double
        /// Débit de la piste vidéo, en bit/s (0 : inconnu).
        var debitVideo: Int
        /// Codec de la piste son ("" : pas de son).
        var codecAudio: String
        var duree: Double
    }

    struct Profil: Equatable {
        /// Suffixe du nom de la copie ; change avec le profil (une copie faite avec un ancien profil n'est pas reprise).
        let suffixe: String
        let debit: Int, debitMax: Int, tampon: Int, audio: Int
        let gop = 120
    }

    static let instagram = Profil(suffixe: "ig1", debit: 20_000_000, debitMax: 24_000_000, tampon: 24_000_000, audio: 128_000)
    static let tiktok = Profil(suffixe: "tt1", debit: 30_000_000, debitMax: 36_000_000, tampon: 36_000_000, audio: 192_000)
    /// Images par seconde acceptées par Instagram et TikTok (leurs pages « spécifications vidéo » : 23 à 60).
    static let fpsMin = 23.0, fpsMax = 60.0

    static func profil(_ r: ReseauPublication) -> Profil? {
        switch r {
        case .youtube: return nil
        case .instagram: return instagram
        case .tiktok: return tiktok
        }
    }

    static func outil(_ nom: String) -> String? {
        ["/opt/homebrew/bin/\(nom)", "/usr/local/bin/\(nom)"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Lecture (ffprobe)

    static func sonder(_ u: URL) -> Sonde? {
        guard let ffprobe = outil("ffprobe") else { return nil }
        let r = FileEnvoi.lancer(ffprobe, ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", u.path])
        guard r.code == 0 else { return nil }
        return lire(r.sortie)
    }

    /// La sonde depuis le JSON de ffprobe (-show_format -show_streams).
    static func lire(_ json: String) -> Sonde? {
        guard let o = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let pistes = o["streams"] as? [[String: Any]],
              let v = pistes.first(where: { $0["codec_type"] as? String == "video" && ($0["disposition"] as? [String: Any])?["attached_pic"] as? Int != 1 })
        else { return nil }
        let a = pistes.first { $0["codec_type"] as? String == "audio" }
        let format = o["format"] as? [String: Any] ?? [:]
        func nombre(_ x: Any?) -> Double { (x as? String).flatMap(Double.init) ?? (x as? Double) ?? Double(x as? Int ?? 0) }
        var duree = nombre(format["duration"])
        if duree <= 0 { duree = nombre(v["duration"]) }
        var debit = Int(nombre(v["bit_rate"]))
        if debit <= 0, let total = Int(exactly: nombre(format["bit_rate"]).rounded()), total > 0 {
            debit = max(0, total - Int(nombre(a?["bit_rate"])))
        }
        return Sonde(codec: v["codec_name"] as? String ?? "", pixFmt: v["pix_fmt"] as? String ?? "",
                     largeur: v["width"] as? Int ?? 0, hauteur: v["height"] as? Int ?? 0,
                     fps: fps(v["avg_frame_rate"] as? String) ?? fps(v["r_frame_rate"] as? String) ?? 0,
                     debitVideo: debit, codecAudio: a?["codec_name"] as? String ?? "", duree: duree)
    }

    /// « 60/1 », « 30000/1001 » ; nil pour « 0/0 ».
    static func fps(_ s: String?) -> Double? {
        guard let s else { return nil }
        let p = s.split(separator: "/").compactMap { Double($0) }
        guard p.count == 2, p[1] > 0, p[0] > 0 else { return p.count == 1 && p[0] > 0 ? p[0] : nil }
        return p[0] / p[1]
    }

    // MARK: Ce qui ne passera pas (refus dès la programmation)

    /// Déjà dans le profil : H.264, 4:2:0 8 bits, débit connu et sous le plafond, son AAC ou pas de son.
    static func conforme(_ s: Sonde, _ p: Profil) -> Bool {
        s.codec == "h264" && ["yuv420p", "yuvj420p"].contains(s.pixFmt) && s.debitVideo > 0 && s.debitVideo <= p.debitMax
            && (s.codecAudio.isEmpty || s.codecAudio == "aac")
    }

    /// La taille de la copie : celle de la source si elle est gardée, sinon débit plafond × durée (+5 %).
    static func tailleEstimee(_ s: Sonde, _ p: Profil, tailleSource: Int) -> Int {
        if conforme(s, p) { return tailleSource }
        return min(tailleSource, Int(Double(p.debitMax + p.audio) * s.duree / 8 * 1.05))
    }

    static func refus(_ s: Sonde?, reseau: ReseauPublication) -> [String] {
        guard reseau != .youtube else { return [] }
        let nom = reseau == .instagram ? "Instagram" : "TikTok"
        guard outil("ffmpeg") != nil, outil("ffprobe") != nil else {
            return [L("ffmpeg absent du Mac : la copie \(nom) ne peut pas être préparée (brew install ffmpeg)")]
        }
        guard let s, s.largeur > 0, s.hauteur > 0 else { return [L("vidéo illisible : la copie \(nom) ne peut pas être préparée")] }
        var r: [String] = []
        if s.fps > 0 && (s.fps < fpsMin - 0.5 || s.fps > fpsMax + 0.5) {
            r.append(L("vidéo à \(Int(s.fps.rounded())) images/s : \(nom) prend de 23 à 60 (on ne change pas les images/s)"))
        }
        return r
    }

    // MARK: Préparation

    /// Les arguments ffmpeg : réécriture seule (déjà conforme) ou réencodage au profil (même taille d'image, mêmes images/s).
    static func arguments(source: URL, sortie: URL, profil p: Profil, reencoder: Bool, logiciel: Bool = false) -> [String] {
        var a = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-i", source.path, "-map", "0:v:0", "-map", "0:a:0?", "-dn",
                 "-map_metadata", "-1"]
        if reencoder {
            a += logiciel ? ["-c:v", "libx264", "-preset", "veryfast"] : ["-c:v", "h264_videotoolbox"]
            a += ["-profile:v", "high", "-b:v", "\(p.debit)", "-maxrate", "\(p.debitMax)", "-bufsize", "\(p.tampon)",
                  "-g", "\(p.gop)", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "\(p.audio)", "-ar", "48000"]
        } else {
            a += ["-c", "copy"]
        }
        return a + ["-movflags", "+faststart", "-f", "mp4", sortie.path]
    }

    /// Ce qui cloche entre la source et sa copie (vide = bonne copie) : taille d'image, images/s, durée, codec, débit.
    static func ecarts(source s: Sonde, copie c: Sonde, profil p: Profil) -> [String] {
        var e: [String] = []
        if c.codec != "h264" { e.append("codec \(c.codec)") }
        if Set([s.largeur, s.hauteur]) != Set([c.largeur, c.hauteur]) { e.append("taille \(c.largeur)×\(c.hauteur) au lieu de \(s.largeur)×\(s.hauteur)") }
        if s.fps > 0 && abs(c.fps - s.fps) > 0.5 { e.append("\(c.fps) images/s au lieu de \(s.fps)") }
        if abs(c.duree - s.duree) > 0.3 { e.append("durée \(c.duree) s au lieu de \(s.duree) s") }
        if c.debitVideo > Int(Double(p.debitMax) * 1.1) { e.append("débit \(c.debitVideo / 1_000_000) Mbit/s") }
        return e
    }

    /// Le chemin de la copie : nommée d'après l'empreinte de la source et le profil.
    static func chemin(dossier: URL, empreinteSource: String, profil p: Profil) -> URL {
        dossier.appendingPathComponent("\(empreinteSource.prefix(16))-\(p.suffixe).mp4")
    }

    /// La copie pour ce réseau, dans `dossier` (reprise si elle existe déjà).
    static func preparer(source: URL, sonde s: Sonde, reseau: ReseauPublication, empreinteSource: String, dossier: URL) throws -> URL {
        guard let p = profil(reseau) else { return source }
        let nom = reseau == .instagram ? "Instagram" : "TikTok"
        let copie = chemin(dossier: dossier, empreinteSource: empreinteSource, profil: p)
        if FileManager.default.fileExists(atPath: copie.path) { return copie }
        guard let ffmpeg = outil("ffmpeg") else {
            throw RefusPublication(raisons: [L("ffmpeg absent du Mac : la copie \(nom) ne peut pas être préparée (brew install ffmpeg)")])
        }
        let tmp = dossier.appendingPathComponent(".\(copie.lastPathComponent).\(UUID().uuidString.prefix(8)).mp4")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let reencoder = !conforme(s, p)
        var r = FileEnvoi.lancer(ffmpeg, arguments(source: source, sortie: tmp, profil: p, reencoder: reencoder))
        if r.code != 0 && reencoder {
            // L'encodeur du Mac refuse parfois une taille ou un format : même réglage en logiciel (plus lent).
            r = FileEnvoi.lancer(ffmpeg, arguments(source: source, sortie: tmp, profil: p, reencoder: true, logiciel: true))
        }
        guard r.code == 0 else {
            throw RefusPublication(raisons: [L("copie \(nom) ratée : \("ffmpeg " + (r.erreur.split(separator: "\n").last.map(String.init) ?? ""))")])
        }
        guard let c = sonder(tmp) else { throw RefusPublication(raisons: [L("copie \(nom) ratée : \("ffprobe")")]) }
        let e = ecarts(source: s, copie: c, profil: p)
        guard e.isEmpty else { throw RefusPublication(raisons: [L("copie \(nom) ratée : \(e.joined(separator: ", "))")]) }
        try FileManager.default.moveItem(at: tmp, to: copie)
        return copie
    }
}
