import Foundation

@main struct WakePresentationRegression {
    static func main() {
        // A dismissed session cannot publish either its seed or its upload
        // into a replacement session, including after a second interruption.
        var session = EffectSession()
        let seed = session.generation
        let upload = session.generation
        session.invalidate()
        let nextSeed = session.generation
        guard !session.accepts(seed), !session.accepts(upload), session.accepts(nextSeed) else { exit(1) }
        session.invalidate()
        guard !session.accepts(nextSeed) else { exit(1) }
        let reveal = PresentationReveal()
        guard reveal.opacity(at: 100) == 0 else { exit(1) }
        print("PASS: cancelled presentations cannot reveal a late picture")
    }
}
