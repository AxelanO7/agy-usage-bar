import AppKit

let args = CommandLine.arguments

if args.contains("--selftest") { exit(SelfTest.run()) }
if args.contains("--once") { exit(CLI.once()) }
if let path = CLI.option("--snapshot") {
    exit(CLI.snapshot(path: path, dark: args.contains("--dark"), demo: args.contains("--demo")))
}
if let path = CLI.option("--menubar-preview") { exit(CLI.menuBarPreview(path: path)) }

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
