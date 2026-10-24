import AppKit
import Combine
import ServiceManagement

@MainActor
final class UsageManager: ObservableObject {
    enum LoadState: Equatable { case idle, loading, ok, error(String), notSignedIn, noAgy }

    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var bar = BarState(text: "…", fraction: nil, band: .ok, symbol: "circle.dotted", tooltip: "")
    @Published private(set) var now = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var launchAtLogin = false
    @Published var poolID: String?

    @Published var choice: DisplayChoice {
        didSet { defaults.set(choice.rawValue, forKey: "displayChoice"); updateBar() }
    }
    @Published var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: "showCountdown"); updateBar() }
    }
    /// "auto" | "en" | "id"
    @Published var langOverride: String {
        didSet { defaults.set(langOverride, forKey: "lang"); applyLanguage(); updateBar() }
    }

    private let defaults = UserDefaults.standard
    private let store: Store
    private var history: History
    private var failures = 0
    private var lastAttempt: Date?
    private var pollTask: Task<Void, Never>?
    private var tick: Timer?

    init(dir: URL = Store.defaultDir) {
        store = Store(dir: dir)
        history = store.read("history.json", as: History.self) ?? History()
        snapshot = store.read("last-usage.json", as: Snapshot.self)
        choice = defaults.string(forKey: "displayChoice").flatMap(DisplayChoice.init(rawValue:)) ?? .gemini5h
        showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? true
        langOverride = defaults.string(forKey: "lang") ?? "auto"
        launchAtLogin = SMAppService.mainApp.status == .enabled
        applyLanguage()
        updateBar()
    }

    private func applyLanguage() {
        switch langOverride {
        case "en": L.lang = .en
        case "id": L.lang = .id
        default: L.lang = L.detect()
        }
    }

    func start() {
        tick = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date(); self?.updateBar() }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetch()
                try? await Task.sleep(nanoseconds: UInt64(self.nextDelay() * 1_000_000_000))
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.fetch()
            }
        }
    }

    /// 3 minutes; doubled after each consecutive failure, up to 15 minutes.
    func nextDelay() -> TimeInterval {
        failures == 0 ? 180 : min(180 * pow(2, Double(failures - 1)), 900)
    }

    func refresh() { Task { await fetch() } }

    func refreshIfStale(after seconds: TimeInterval = 30) {
        if let t = lastAttempt, Date().timeIntervalSince(t) < seconds { return }
        refresh()
    }

    func fetch() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastAttempt = Date()
        if snapshot == nil { state = .loading; updateBar() }
        let result = await AgyRunner.fetch()
        isRefreshing = false
        now = Date()
        switch result {
        case .success(let snap):
            snapshot = snap
            state = .ok
            failures = 0
            history.append(snap)
            store.write(snap, "last-usage.json")
            store.write(history, "history.json")
        case .failure(let err):
            failures += 1
            switch err {
            case .noAgy: state = .noAgy
            case .notSignedIn: state = .notSignedIn
            case .failed(let m): state = .error(m)
            }
        }
        updateBar()
    }

    /// For the `--snapshot` render mode: use data that was already fetched, persist nothing.
    func preview(_ snap: Snapshot) {
        snapshot = snap
        state = .ok
        now = snap.fetchedAt
        updateBar()
    }

    // MARK: - Derived data for the views

    func projection(for bucket: Bucket) -> Projection? { history.projection(for: bucket, now: now) }

    func trend(for bucket: Bucket) -> Trend? {
        history.trend(for: bucket, now: now, projection: projection(for: bucket))
    }

    /// The pool shown in the popover: the user's pick, otherwise the pool of the bucket shown in the menu bar.
    func selectedGroup(in snap: Snapshot) -> UsageGroup? {
        if let id = poolID, let g = snap.groups.first(where: { $0.id == id }) { return g }
        if let b = Fmt.chosenBucket(snap, choice), let g = snap.groups.first(where: { $0.buckets.contains(b) }) { return g }
        return snap.groups.first
    }

    func isPinned(_ bucket: Bucket) -> Bool {
        guard let s = snapshot else { return false }
        return Fmt.chosenBucket(s, choice)?.id == bucket.id
    }

    var banner: String? {
        switch state {
        case .error(let m): return L.updateFailed(m)
        case .notSignedIn: return L.notSignedIn
        case .noAgy: return L.noAgy
        default: return nil
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("AgyUsageBar: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Menu bar state

    private func updateBar() {
        let isError: Bool = { if case .error = state { return true }; return false }()
        switch state {
        case .noAgy:
            bar = BarState(text: "agy?", fraction: nil, band: .warn, symbol: "exclamationmark.triangle", tooltip: L.noAgy)
        case .notSignedIn:
            bar = BarState(text: L.login, fraction: nil, band: .warn, symbol: "person.crop.circle.badge.exclamationmark", tooltip: L.notSignedIn)
        default:
            if let s = snapshot, let b = Fmt.chosenBucket(s, choice) {
                bar = BarState(text: Fmt.barText(bucket: b, showCountdown: showCountdown, now: now) + (isError ? " !" : ""),
                               fraction: b.used, band: b.band, symbol: nil,
                               tooltip: Fmt.tooltip(snapshot: s, bucket: b, now: now))
            } else {
                bar = BarState(text: isError ? "Error" : "…", fraction: nil, band: .ok,
                               symbol: isError ? "exclamationmark.triangle" : "circle.dotted", tooltip: banner ?? L.loading)
            }
        }
    }
}
