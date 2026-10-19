import SwiftUI
import WebKit

// Il video dell'esecuzione: un clip di YouTube incorporato (youtube-nocookie.com, senza audio, in loop, dentro l'app).
// Quasi tutti sono i clip di 10–15 secondi di Renaissance Periodization, che mostrano solo il movimento.
// Gli id stanno in movimenti.json (campo «yt», da tools/movimenti.py). Serve internet: senza rete c'è il manichino 3D.
struct VideoYouTube: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> WKWebView {
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: c)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.isScrollEnabled = false
        w.scrollView.bounces = false
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        guard context.coordinator.caricato != id else { return }
        context.coordinator.caricato = id
        let parametri = "autoplay=1&mute=1&loop=1&playlist=\(id)&playsinline=1&controls=0&rel=0&modestbranding=1&iv_load_policy=3"
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(id)?\(parametri)" allow="autoplay; encrypted-media; picture-in-picture"
        referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></body></html>
        """
        // YouTube vuole sapere da che sito arriva il video incorporato: uso l'indirizzo del sito di Recomp
        w.loadHTMLString(html, baseURL: URL(string: "https://splancxs.github.io/"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var caricato: String? }
}

// copertina del video (per le miniature): l'immagine di YouTube, ritagliata al centro
struct CopertinaVideo: View {
    let id: String
    var body: some View {
        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")) { fase in
            if let img = fase.image { img.resizable().scaledToFill() } else { Color.clear }
        }
    }
}
