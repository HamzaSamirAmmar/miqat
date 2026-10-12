import Combine
import Foundation

/// Looks for a newer Miqat release on GitHub.
///
/// It only *reports* — updating stays manual (Homebrew or the release page) —
/// so no signing keys or appcast are involved. The one request goes to
/// GitHub's public "latest release" endpoint and carries no user data.
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var status: Status = .idle

    /// Whether the app checks by itself (at launch, then daily). On by default.
    @Published var automaticChecksEnabled: Bool = true {
        didSet {
            guard oldValue != automaticChecksEnabled else { return }
            UserDefaults.standard.set(automaticChecksEnabled, forKey: Keys.automatic)
        }
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/HamzaSamirAmmar/miqat/releases/latest")!
    static let interval: TimeInterval = 24 * 3600

    private enum Keys {
        static let automatic = "miqat.update.automatic"
        static let lastCheck = "miqat.update.lastCheck"
    }

    private let session: URLSession
    private let currentVersion: String
    private var timer: Timer?

    init(
        session: URLSession = .shared,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    ) {
        self.session = session
        self.currentVersion = currentVersion
        if UserDefaults.standard.object(forKey: Keys.automatic) != nil {
            automaticChecksEnabled = UserDefaults.standard.bool(forKey: Keys.automatic)
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Checking

    /// Checks now if automatic checks are on and a day has passed, then keeps
    /// re-evaluating hourly while the app runs.
    func startAutomaticChecks() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard automaticChecksEnabled else { return }
        let last = UserDefaults.standard.object(forKey: Keys.lastCheck) as? Date
        if let last, Date().timeIntervalSince(last) < Self.interval { return }
        check()
    }

    /// Asks GitHub for the latest release and updates `status`.
    func check() {
        if case .checking = status { return }
        status = .checking

        var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { [weak self] data, response, _ in
            let result: Status
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data,
               let release = Self.parseRelease(data) {
                result = Self.status(for: release, current: self?.currentVersion ?? "0")
                UserDefaults.standard.set(Date(), forKey: Keys.lastCheck)
            } else {
                result = .failed
            }
            DispatchQueue.main.async { self?.status = result }
        }.resume()
    }

    // MARK: - Pure logic

    struct Release: Equatable {
        let version: String
        let url: URL
    }

    /// Reads `tag_name` / `html_url` from GitHub's release JSON.
    static func parseRelease(_ data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String,
              let link = object["html_url"] as? String,
              let url = URL(string: link),
              url.scheme == "https" else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, url: url)
    }

    static func status(for release: Release, current: String) -> Status {
        isNewer(release.version, than: current)
            ? .available(version: release.version, url: release.url)
            : .upToDate
    }

    /// Numeric dotted-version comparison ("1.10.0" > "1.9.2"); missing parts
    /// count as zero and anything after a "-" (pre-release) is ignored.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: "-").first.map {
                $0.split(separator: ".").map { Int($0) ?? 0 }
            } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
