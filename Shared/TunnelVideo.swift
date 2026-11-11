// Adresse publique temporaire pour UNE vidéo (Instagram video_url, accord de Sacha le 10/11 : « Et ok pour ce moyen là. »).
// Garde-fous : un dossier temporaire qui ne contient que ce fichier (clone APFS, rien de copié ailleurs), un petit serveur sur
// 127.0.0.1 seulement qui ne sert que ce fichier à un nom au hasard (404 partout ailleurs, pas de liste), un « quick tunnel »
// cloudflared (https://<mots-au-hasard>.trycloudflare.com, sans compte). Rien n'est stocké chez un tiers. Un seul processus
// surveillant (python3) tient le serveur et cloudflared ; il coupe tout et efface le dossier quand Pilote ferme le tunnel,
// quand Pilote meurt (son entrée se ferme), sur SIGTERM, ou au bout de `dureeMax` (15 min) au plus.
import Foundation

final class TunnelVideo {
    /// Au-delà, tout est coupé quoi qu'il arrive (garde-fou demandé par Sacha via PILOTE le 10/11).
    static let dureeMax: TimeInterval = 15 * 60

    let adresse: String
    let ouvertLe: Date
    private let surveillant: Process
    private let entree: Pipe
    private let dossier: URL
    private let pidTunnel: Int32
    private var ferme = false

    var ouvertDepuis: TimeInterval { Date().timeIntervalSince(ouvertLe) }

    static func cloudflared() -> String? {
        ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Le 1er « https://….trycloudflare.com » du journal de cloudflared (api.trycloudflare.com n'est pas le tunnel).
    static func hoteTunnel(_ journal: String) -> String? {
        var reste = journal[...]
        while let r = reste.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression) {
            let h = String(reste[r])
            if h != "https://api.trycloudflare.com" { return h }
            reste = reste[r.upperBound...]
        }
        return nil
    }

    /// La valeur entière d'une ligne « CLE 123 » écrite par le surveillant.
    static func valeur(_ cle: String, _ texte: String) -> Int32? {
        for l in texte.split(separator: "\n") where l.hasPrefix(cle + " ") {
            if let v = Int32(l.dropFirst(cle.count + 1).trimmingCharacters(in: .whitespaces)) { return v }
        }
        return nil
    }

    init(fichier: URL, delai: TimeInterval = 60, dureeMax: TimeInterval = TunnelVideo.dureeMax) throws {
        guard let cf = Self.cloudflared() else {
            throw ErreurPlateforme.definitive("cloudflared absent : pas d'adresse temporaire possible pour Instagram")
        }
        let fm = FileManager.default
        let d = fm.temporaryDirectory.appendingPathComponent("pilote-tunnel-" + UUID().uuidString.lowercased(), isDirectory: true)
        try fm.createDirectory(at: d, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let nom = UUID().uuidString.lowercased() + ".mp4"
        do { try fm.copyItem(at: fichier, to: d.appendingPathComponent(nom)) } catch { try? fm.removeItem(at: d); throw error }

        let s = Process()
        s.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        s.arguments = ["-I", "-c", Self.codeSurveillant, d.path, nom, cf, String(Int(dureeMax))]
        let sortie = Pipe()
        let e = Pipe()
        s.standardOutput = sortie
        s.standardError = FileHandle.nullDevice
        s.standardInput = e
        do { try s.run() } catch { try? fm.removeItem(at: d); throw error }

        let lu = Self.lire(sortie.fileHandleForReading, delai: delai) { t -> (String, Int32)? in
            guard let h = Self.hoteTunnel(t), let pid = Self.valeur("PID", t) else { return nil }
            return (h, pid)
        }
        surveillant = s
        entree = e
        dossier = d
        pidTunnel = lu?.1 ?? 0
        adresse = lu.map { "\($0.0)/\(nom)" } ?? ""
        ouvertLe = Date()
        guard lu != nil else {
            fermer()
            throw ErreurPlateforme.passagere("tunnel cloudflared pas ouvert en \(Int(delai)) s")
        }
        // L'adresse se propage en quelques secondes ; on attend qu'elle réponde (au plus `delai`), sans bloquer si le DNS
        // de la box est en retard (Instagram passe par le sien).
        var r = URLRequest(url: URL(string: adresse)!)
        r.httpMethod = "HEAD"
        r.timeoutInterval = 10
        let fin = Date().addingTimeInterval(delai)
        while Date() < fin {
            if let rep = try? HTTP.envoyer(r), rep.code == 200 { break }
            Thread.sleep(forTimeInterval: 3)
        }
    }

    /// Coupe tout : le surveillant arrête cloudflared et le serveur, efface le dossier ; on vérifie derrière lui.
    func fermer() {
        guard !ferme else { return }
        ferme = true
        try? entree.fileHandleForWriting.close()
        let fin = Date().addingTimeInterval(10)
        while surveillant.isRunning && Date() < fin { Thread.sleep(forTimeInterval: 0.2) }
        if surveillant.isRunning { surveillant.terminate(); Thread.sleep(forTimeInterval: 1) }
        if pidTunnel > 0, kill(pidTunnel, 0) == 0 {
            kill(pidTunnel, SIGTERM)
            Thread.sleep(forTimeInterval: 1)
            if kill(pidTunnel, 0) == 0 { kill(pidTunnel, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: dossier)
    }

    deinit { fermer() }

    /// Lit la sortie d'un processus jusqu'à ce que `trouve` rende une valeur (ou `delai` écoulé). La lecture continue ensuite en
    /// tâche de fond (sinon le tuyau se remplit et le processus se bloque).
    private static func lire<T>(_ h: FileHandle, delai: TimeInterval, _ trouve: @escaping (String) -> T?) -> T? {
        let verrou = NSLock()
        var texte = ""
        h.readabilityHandler = { f in
            let d = f.availableData
            if d.isEmpty { f.readabilityHandler = nil; return }
            verrou.lock(); if texte.count < 100_000 { texte += String(decoding: d, as: UTF8.self) }; verrou.unlock()
        }
        let fin = Date().addingTimeInterval(delai)
        while Date() < fin {
            verrou.lock(); let t = texte; verrou.unlock()
            if let v = trouve(t) { return v }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    /// Le surveillant : serveur (un seul fichier, à /<nom> seulement, GET et HEAD, plages d'octets) sur 127.0.0.1, cloudflared
    /// devant lui, son journal recopié sur la sortie (Pilote y lit l'adresse), « PID n » pour cloudflared. Coupe tout et efface
    /// le dossier à la fin de l'entrée (Pilote ferme ou meurt), sur SIGTERM/SIGINT/SIGHUP, si cloudflared s'arrête, ou au bout
    /// de la durée maximale.
    static let codeSurveillant = #"""
import http.server, os, re, shutil, signal, subprocess, sys, threading
dossier, nom, cf, duree = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
fichier = os.path.join(dossier, nom)
taille = os.path.getsize(fichier)
fini = threading.Event()
def dire(t):
    try:
        sys.stdout.write(t + "\n"); sys.stdout.flush()
    except Exception:
        pass
class Lecture(http.server.BaseHTTPRequestHandler):
    def _servir(self, corps):
        if self.path.split("?")[0] != "/" + nom:
            self.send_error(404); return
        debut, fin = 0, taille - 1
        m = re.match(r"bytes=(\d*)-(\d*)$", self.headers.get("Range", "").strip())
        if m and (m.group(1) or m.group(2)):
            if m.group(1):
                debut = int(m.group(1)); fin = min(int(m.group(2)), taille - 1) if m.group(2) else taille - 1
            else:
                debut = max(0, taille - int(m.group(2)))
            if debut > fin:
                self.send_response(416); self.send_header("Content-Range", "bytes */%d" % taille); self.end_headers(); return
            self.send_response(206); self.send_header("Content-Range", "bytes %d-%d/%d" % (debut, fin, taille))
        else:
            self.send_response(200)
        self.send_header("Content-Type", "video/mp4"); self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(fin - debut + 1)); self.end_headers()
        if not corps: return
        with open(fichier, "rb") as h:
            h.seek(debut); reste = fin - debut + 1
            while reste > 0 and not fini.is_set():
                b = h.read(min(1 << 20, reste))
                if not b: break
                self.wfile.write(b); reste -= len(b)
    def do_GET(self): self._servir(True)
    def do_HEAD(self): self._servir(False)
    def log_message(self, *a): pass
serveur = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Lecture)
serveur.daemon_threads = True
threading.Thread(target=serveur.serve_forever, daemon=True).start()
port = serveur.server_address[1]
dire("PORT %d" % port)
tunnel = subprocess.Popen([cf, "tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:%d" % port],
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
dire("PID %d" % tunnel.pid)
def journal():
    for ligne in tunnel.stdout:
        dire("CF " + ligne.rstrip())
    fini.set()
def parent():
    try:
        while sys.stdin.buffer.read(4096):
            pass
    except Exception:
        pass
    fini.set()
threading.Thread(target=journal, daemon=True).start()
threading.Thread(target=parent, daemon=True).start()
for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
    signal.signal(s, lambda *a: fini.set())
fini.wait(duree)
try:
    tunnel.terminate(); tunnel.wait(5)
except Exception:
    try:
        tunnel.kill()
    except Exception:
        pass
try:
    serveur.server_close()
except Exception:
    pass
shutil.rmtree(dossier, ignore_errors=True)
dire("FERME")
os._exit(0)
"""#
}
