import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
#if canImport(MobileCoreServices)
#elseif canImport(CoreServices)
import CoreServices
#endif
import OPCCompanyCore

// ── opc-demo-gif: renders the pixel-workforce status gallery to an
// animated GIF entirely OFFSCREEN — no screen, no window, no recording
// permission. Reuses the real AgentDeskView composition (OPCDemoStudio),
// so what the GIF shows is what the app draws.
//
//   swift run opc-demo-gif --out /tmp/opc.gif [--frames 12] [--scale 2]
//
// Release-asset companion to scripts/capture-demo.sh (which records the
// live app and needs TCC screen permission). This binary is the sandbox
// path: deterministic, CI-safe, and honest — every pixel comes from the
// shipping render code, not a mock.

struct Options {
    var out = "opc-workforce.gif"
    var frames = 12
    var scale: CGFloat = 2
    var secondsPerLoop: TimeInterval = 2.4
}

func parseArgs() -> Options {
    var o = Options()
    let args = CommandLine.arguments
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--out": i += 1; if i < args.count { o.out = args[i] }
        case "--frames": i += 1; if i < args.count, let n = Int(args[i]) { o.frames = max(4, n) }
        case "--scale": i += 1; if i < args.count, let s = Double(args[i]) { o.scale = CGFloat(s) }
        case "--help":
            FileHandle.standardError.write(Data("usage: opc-demo-gif [--out path] [--frames n] [--scale s]\n".utf8))
            exit(0)
        default: break
        }
        i += 1
    }
    return o
}

@MainActor
func renderFrames(options: Options) -> [CGImage] {
    var images: [CGImage] = []
    let base = Date()
    let dt = options.secondsPerLoop / Double(options.frames)
    for f in 0..<options.frames {
        let date = base.addingTimeInterval(Double(f) * dt)
        let view = OPCDemoStudio.statusGallery(date: date)
            .frame(width: 780, height: OPCDemoStudio.galleryHeight)
        let renderer = ImageRenderer(content: view)
        renderer.scale = options.scale
        if let img = renderer.cgImage { images.append(img) }
    }
    return images
}

func writeGIF(images: [CGImage], to path: String, frameDelay: TimeInterval) -> Bool {
    guard !images.isEmpty else { return false }
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, images.count, nil) else { return false }
    let props: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
    ]
    CGImageDestinationSetProperties(dest, props as CFDictionary)
    let frame: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay],
    ]
    for img in images { CGImageDestinationAddImage(dest, img, frame as CFDictionary) }
    return CGImageDestinationFinalize(dest)
}

let options = parseArgs()
let images = MainActor.assumeIsolated { renderFrames(options: options) }
guard !images.isEmpty else {
    FileHandle.standardError.write(Data("error: rendered zero frames (macOS + SwiftUI required)\n".utf8))
    exit(1)
}
let ok = writeGIF(images: images, to: options.out, frameDelay: options.secondsPerLoop / Double(options.frames))
if ok {
    let attrs = (try? FileManager.default.attributesOfItem(atPath: options.out)) ?? [:]
    print("wrote \(options.out) frames=\(images.count) bytes=\(attrs[.size] ?? "?")")
    exit(0)
} else {
    FileHandle.standardError.write(Data("error: GIF finalize failed\n".utf8))
    exit(1)
}
