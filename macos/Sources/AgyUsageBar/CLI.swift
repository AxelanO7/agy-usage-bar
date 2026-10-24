import AppKit
import SwiftUI

private final class Box<T>: @unchecked Sendable { var value: T? }

/// Command-line modes for testing without the GUI:
///   --once                          fetch once and print what the menu bar would show
///   --snapshot out.png [--demo] [--dark] [--lang en|id] [--pool gemini|3p]
///   --menubar-preview out.png [--lang en|id]
enum CLI {
    static func option(_ name: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func applyLanguage() {
        if let l = option("--lang") {
            setenv("AGY_USAGE_LANG", l, 1)   // UsageManager re-detects the language, so go through the same override
            L.lang = L.detect()
        }
    }

    static func fetchBlocking() -> Result<Snapshot, FetchError> {
        let box = Box<Result<Snapshot, FetchError>>()
        let sem = DispatchSemaphore(value: 0)
        Task.detached { box.value = await AgyRunner.fetch(); sem.signal() }
        sem.wait()
        return box.value ?? .failure(.failed("no result"))
    }

    static func once() -> Int32 {
        applyLanguage()
        switch fetchBlocking() {
        case .failure(let e):
            print("FAILED: \(e)")
            return 1
        case .success(let snap):
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            for g in snap.groups {
                print("\(g.name)  [\(g.models)]")
                for b in g.buckets {
                    print(String(format: "  %-14@ used %3d%%  left %5.1f%%  reset %@  %@", b.id as NSString, b.usedPercent,
                                 b.remaining * 100, f.string(from: b.resetTime) as NSString, b.untouched ? "(not started)" : ""))
                }
            }
            for c in DisplayChoice.allCases {
                if let b = Fmt.chosenBucket(snap, c) {
                    print("menu bar [\(c.label)]: \(Fmt.barText(bucket: b, showCountdown: true, now: snap.fetchedAt))")
                }
            }
            return 0
        }
    }

    // MARK: - Demo data (high usage + synthetic history so colors, pace and the chart are visible)

    static let demoNow = UsageParser.date("2026-10-24T12:00:00Z")!

    static func demo() -> (Snapshot, URL) {
        let now = demoNow
        func b(_ id: String, _ w: String, used: Double, reset: TimeInterval) -> Bucket {
            Bucket(id: id, window: w, remaining: 1 - used, resetTime: now.addingTimeInterval(reset))
        }
        let g5 = b("gemini-5h", "5h", used: 0.72, reset: 2 * 3600 + 10 * 60)
        let gw = b("gemini-weekly", "weekly", used: 0.41, reset: 2 * 86400 + 5 * 3600)
        let t5 = b("3p-5h", "5h", used: 0.30, reset: 3 * 3600)
        let tw = b("3p-weekly", "weekly", used: 0.05, reset: 6 * 86400)
        let snap = Snapshot(fetchedAt: now, groups: [
            UsageGroup(name: "Gemini Models", models: "Gemini Flash, Gemini Pro", buckets: [gw, g5]),
            UsageGroup(name: "Claude and GPT models", models: "Claude Opus, Claude Sonnet, GPT-OSS", buckets: [tw, t5])])
        var h = History()
        func add(_ minutesAgo: Double, _ bucket: Bucket, _ used: Double) {
            let t = now.addingTimeInterval(-minutesAgo * 60)
            let sample = Bucket(id: bucket.id, window: bucket.window, remaining: 1 - used, resetTime: bucket.resetTime)
            h.append(Snapshot(fetchedAt: t, groups: [UsageGroup(name: "g", models: "", buckets: [sample])]))
        }
        for (ago, used) in [(165.0, 0.02), (130.0, 0.10), (90.0, 0.27), (60.0, 0.42), (30.0, 0.58)] { add(ago, g5, used) }
        add(12 * 60, gw, 0.36)
        add(60, t5, 0.10)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agy-usage-demo-\(UUID().uuidString)")
        Store(dir: dir).write(h, "history.json")
        return (snap, dir)
    }

    // MARK: - Popover render

    static func snapshot(path: String, dark: Bool, demo useDemo: Bool) -> Int32 {
        applyLanguage()
        let snap: Snapshot, dir: URL
        if useDemo { (snap, dir) = demo() }
        else if case .success(let s) = fetchBlocking() { snap = s; dir = Store.defaultDir }
        else { print("could not fetch data"); return 1 }
        return MainActor.assumeIsolated {
            _ = NSApplication.shared
            let m = UsageManager(dir: dir)
            m.preview(snap)
            if let pool = option("--pool") {
                let key = pool.lowercased() == "3p" ? "claude" : pool.lowercased()
                m.poolID = snap.groups.first { $0.shortName.lowercased().contains(key) }?.id
            }
            print("menu bar text: \(m.bar.text)")
            // The real popover has a vibrancy background; a flat color stands in for it here.
            let root = PopoverView(m: m)
                .background(Color(white: dark ? 0.16 : 0.96))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .environment(\.colorScheme, dark ? .dark : .light)
            return render(root, dark: dark, path: path)
        }
    }

    @MainActor
    static func render<V: View>(_ root: V, dark: Bool, path: String) -> Int32 {
        let host = NSHostingView(rootView: root)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return 1 }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        do { try png.write(to: URL(fileURLWithPath: path)) } catch { print("write failed: \(error)"); return 1 }
        print("PNG \(Int(size.width))x\(Int(size.height)) -> \(path)")
        return 0
    }

    // MARK: - Menu bar render (approximation of the status item on a light and a dark menu bar)

    static func menuBarPreview(path: String) -> Int32 {
        applyLanguage()
        let now = demoNow
        func bucket(_ id: String, _ w: String, _ used: Double, reset: TimeInterval) -> Bucket {
            Bucket(id: id, window: w, remaining: 1 - used, resetTime: now.addingTimeInterval(reset))
        }
        let items: [(Bucket, Bool)] = [
            (bucket("gemini-5h", "5h", 0.02, reset: 4 * 3600 + 44 * 60), true),
            (bucket("gemini-5h", "5h", 0.72, reset: 2 * 3600 + 10 * 60), true),
            (bucket("gemini-5h", "5h", 0.93, reset: 25 * 60), true),
            (bucket("gemini-weekly", "weekly", 0.41, reset: 2 * 86400 + 5 * 3600), true),
            (bucket("3p-5h", "5h", 0.0, reset: 5 * 3600), true),
            (bucket("gemini-5h", "5h", 0.72, reset: 2 * 3600 + 10 * 60), false),
        ]
        return MainActor.assumeIsolated {
            _ = NSApplication.shared
            let scale: CGFloat = 4, rowH: CGFloat = 24, colW: CGFloat = 150
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let size = NSSize(width: colW * 2 * scale, height: rowH * CGFloat(items.count) * scale)
            let image = NSImage(size: size)
            image.lockFocus()
            for (col, dark) in [(0, false), (1, true)] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                appearance.performAsCurrentDrawingAppearance {
                    for (row, item) in items.enumerated() {
                        let (b, countdown) = item
                        let y = size.height - CGFloat(row + 1) * rowH * scale
                        let rect = NSRect(x: CGFloat(col) * colW * scale, y: y, width: colW * scale, height: rowH * scale)
                        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.94, alpha: 1)).setFill()
                        rect.fill()
                        let text = Fmt.barText(bucket: b, showCountdown: countdown, now: now)
                        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
                        let textSize = (text as NSString).size(withAttributes: attrs)
                        let icon = MenuBarIcon.ring(used: b.used, color: b.band.nsColor)
                        let total = icon.size.width + 4 + textSize.width
                        let x0 = rect.minX + (colW * scale - total * scale) / 2
                        icon.draw(in: NSRect(x: x0, y: rect.minY + (rowH - icon.size.height) / 2 * scale,
                                             width: icon.size.width * scale, height: icon.size.height * scale))
                        let t = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12 * scale, weight: .medium),
                                                                              .foregroundColor: NSColor.labelColor])
                        t.draw(at: NSPoint(x: x0 + (icon.size.width + 4) * scale, y: rect.minY + (rowH * scale - textSize.height * scale) / 2))
                    }
                }
            }
            image.unlockFocus()
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return 1 }
            do { try png.write(to: URL(fileURLWithPath: path)) } catch { print("write failed: \(error)"); return 1 }
            print("PNG -> \(path)")
            return 0
        }
    }
}
