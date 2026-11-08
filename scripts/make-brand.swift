// Renders every Niche brand asset from brand/*.svg with WebKit (gradients, filters and clip
// paths render exactly as in a browser):
//   resources/AppIcon.icns                 brand/niche-icon.svg
//   resources/app-icons/<id>.png (512 px)  the Settings ▸ General ▸ App Icon choices
//   resources/brand/niche-mark*.png        the in-app mark (BrandMark.swift)
// Run after editing a brand SVG:  swift scripts/make-brand.swift
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func path(_ p: String) -> URL { root.appendingPathComponent(p) }

// source svg -> [(output png, pixel size)]
let jobs: [(String, [(String, Int)])] = [
    ("niche-icon", [("resources/app-icons/segments.png", 512)]),
    ("niche-icon-light", [("resources/app-icons/light.png", 512)]),
    ("niche-icon-mono", [("resources/app-icons/mono.png", 512)]),
    ("niche-mark", [("resources/brand/niche-mark.png", 256), ("resources/brand/niche-mark@2x.png", 512)]),
    ("niche-mark-mono", [("resources/brand/niche-mark-mono.png", 256)]),
]
let iconset: [(String, Int)] = [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                                ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
                                ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)]

func resized(_ cg: CGImage, _ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
    print("wrote \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
}

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 512, height: 512))
    var queue = jobs

    func next() {
        guard let (name, _) = queue.first else { finish() }
        let svg = try! String(contentsOf: path("brand/\(name).svg"), encoding: .utf8)
            .replacingOccurrences(of: "currentColor", with: "#000")
            .replacingOccurrences(of: #"<svg "#, with: #"<svg style="display:block;width:100vw;height:100vh" "#)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString("<!doctype html><body style='margin:0;background:transparent;overflow:hidden'>\(svg)</body>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let (name, outputs) = queue.removeFirst()
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: 1024 / Double(webView.window?.backingScaleFactor ?? 2))
        webView.takeSnapshot(with: config) { image, error in
            guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("\(name): \(error?.localizedDescription ?? "no image")")
            }
            for (out, px) in outputs { write(resized(cg, px), path(out)) }
            if name == "niche-icon" { self.icns(cg) }
            self.next()
        }
    }

    func icns(_ cg: CGImage) {
        let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: set)
        try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        for (file, px) in iconset { try! resized(cg, px).write(to: set.appendingPathComponent("\(file).png")) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = ["-c", "icns", set.path, "-o", path("resources/AppIcon.icns").path]
        try! task.run(); task.waitUntilExit()
        precondition(task.terminationStatus == 0, "iconutil failed")
        print("wrote resources/AppIcon.icns")
    }

    func finish() -> Never {
        try? FileManager.default.removeItem(at: path("resources/brand/niche-mark.svg"))
        try! FileManager.default.copyItem(at: path("brand/niche-mark.svg"), to: path("resources/brand/niche-mark.svg"))
        exit(0)
    }
}

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 512, height: 512), styleMask: .borderless,
                      backing: .buffered, defer: false)
let renderer = Renderer()
window.contentView = renderer.view
window.orderBack(nil)
renderer.next()
app.run()
