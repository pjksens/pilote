// Retour OAuth sur 127.0.0.1 (08/11) : une connexion ouverte d'avance par le navigateur, qui n'envoie rien, ne doit pas
// bloquer la vraie réponse de Google (bug vu : « Connecter » restait sans suite).
import XCTest

final class EcouteLocaleTests: XCTestCase {
    private func connecter(_ port: UInt16) -> Int32 {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        a.sin_port = port.bigEndian
        _ = withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        return s
    }

    func testPreconnexionMuetteNeBloquePasLaReponse() throws {
        let e = try EcouteLocale()
        defer { e.fermer() }
        let muette = connecter(e.port)          // pré-connexion : rien n'est envoyé
        defer { close(muette) }
        let favicon = connecter(e.port)
        defer { close(favicon) }
        let vraie = connecter(e.port)
        defer { close(vraie) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            _ = "GET /favicon.ico HTTP/1.1\r\nHost: x\r\n\r\n".withCString { write(favicon, $0, strlen($0)) }
            _ = "GET /?state=s1&code=abc HTTP/1.1\r\nHost: x\r\n\r\n".withCString { write(vraie, $0, strlen($0)) }
        }
        let debut = Date()
        let q = try e.attendre(secondes: 5) { _ in "ok" }
        XCTAssertEqual(q["code"], "abc")
        XCTAssertEqual(q["state"], "s1")
        XCTAssertLessThan(Date().timeIntervalSince(debut), 3, "la connexion muette n'a pas fait attendre")
        var tampon = [UInt8](repeating: 0, count: 4096)
        let n = read(vraie, &tampon, tampon.count)
        XCTAssertTrue(String(decoding: tampon[0..<max(0, n)], as: UTF8.self).hasPrefix("HTTP/1.1 200"))
    }

    func testSansReponseErreurClaire() throws {
        let e = try EcouteLocale()
        defer { e.fermer() }
        let muette = connecter(e.port)
        defer { close(muette) }
        XCTAssertThrowsError(try e.attendre(secondes: 1) { _ in "ok" }) { err in
            XCTAssertTrue("\(err)".contains("pas de retour"), "\(err)")
        }
    }
}
