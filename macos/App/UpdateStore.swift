import Foundation
import Combine
import AppKit
import CryptoKit

@MainActor final class UpdateStore: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var status = ""
    @Published private(set) var isBusy = false
    @Published var showsDetails = false
    @Published private(set) var releaseNotes = "尚未读取更新说明。"
    private var retryAfter: Date?
    private var retryTask: Task<Void, Never>?
    private var packageSize: Int?
    private var packageDigest: String?
    var canInstall: Bool { latestVersion != nil && packageURL != nil && (checksumsURL != nil || packageDigest != nil) }
    private var releaseURL: URL?
    private var packageURL: URL?
    private var checksumsURL: URL?
    private var checkedAt: Date?
    private let session: URLSession
    private let defaults: UserDefaults
    private let localVersion: String
    private let cacheKey = "dailyReleaseCache"
    private let releaseList = URL(string: "https://api.github.com/repos/march7th-26/Daily/releases?per_page=50")!

    private struct Release: Codable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        let body: String?
    }
    private struct Asset: Codable {
        let name: String
        let browser_download_url: URL
        let size: Int?
        let digest: String?
        let state: String?
    }
    private struct Cache: Codable {
        let release: Release?
        let checkedAt: Date
        let build: String?
    }

    init(session: URLSession = .shared, defaults: UserDefaults = .standard,
         localVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        self.session = session
        self.defaults = defaults
        self.localVersion = localVersion
        if let data = defaults.data(forKey: cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            checkedAt = cache.build == localVersion ? cache.checkedAt : nil
            apply(cache.release, force: false)
        }
    }

    deinit { retryTask?.cancel() }

    func presentDetails() async {
        showsDetails = true
        await check(force: true)
    }

    func checkIfNeeded() async {
        if let retryAfter, Date() < retryAfter { return }
        if let checkedAt, Calendar.current.isDateInToday(checkedAt) { return }
        await check(force: false)
    }

    func check(force: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        if force { status = "正在检查更新…" }
        defer { isBusy = false }
        do {
            var request = URLRequest(url: releaseList)
            request.timeoutInterval = 20
            request.setValue("Daily-macOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576 else {
                throw UpdateError.message("GitHub 暂时无法访问，请稍后重试。")
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            let newest = releases.filter {
                $0.tag_name.hasPrefix("macos-v") && !$0.draft && !$0.prerelease &&
                    Self.versionParts(String($0.tag_name.dropFirst(7))) != nil
            }.max { Self.compare(String($0.tag_name.dropFirst(7)), String($1.tag_name.dropFirst(7))) == .orderedAscending }
            apply(newest, force: force)
            let cache = Cache(release: newest, checkedAt: Date(), build: localVersion)
            defaults.set(try JSONEncoder().encode(cache), forKey: cacheKey)
            checkedAt = cache.checkedAt
            retryAfter = nil
            retryTask?.cancel()
        } catch {
            retryAfter = Date().addingTimeInterval(30 * 60)
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 1_800_000_000_000) } catch { return }
                await self?.checkIfNeeded()
            }
            if force { status = (error as? UpdateError)?.errorDescription ?? "检查更新失败，请检查网络后重试。" }
        }
    }

    private func apply(_ release: Release?, force: Bool) {
        latestVersion = nil
        releaseURL = release?.html_url
        packageURL = nil
        checksumsURL = nil
        packageSize = nil
        packageDigest = nil
        releaseNotes = release?.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if releaseNotes.isEmpty { releaseNotes = "此版本暂未提供更新日志。" }
        guard let release else {
            status = force ? "暂未发布 macOS 版本更新。" : ""
            return
        }
        let remote = String(release.tag_name.dropFirst(7))
        let order = Self.compare(remote, localVersion)
        if order == .orderedDescending { latestVersion = remote }
        let filename = "Daily-macOS-\(remote).pkg"
        let prefix = "https://github.com/march7th-26/Daily/releases/download/\(release.tag_name)/"
        let packages = release.assets.filter { $0.name == filename && $0.browser_download_url.absoluteString == prefix + filename && ($0.state == nil || $0.state == "uploaded") }
        if packages.count == 1 {
            let package = packages[0]
            packageURL = package.browser_download_url
            packageSize = package.size
            packageDigest = package.digest
        }
        checksumsURL = release.assets.first { $0.name == "SHA256SUMS.txt" && $0.browser_download_url.absoluteString == prefix + "SHA256SUMS.txt" }?.browser_download_url
        if latestVersion != nil {
            status = "发现 v\(remote)，点击下载并启动安装器。"
        } else if force {
            status = order == .orderedAscending ? "当前构建 v\(localVersion) 高于最新正式版 v\(remote)。" : "当前已是最新版本 v\(localVersion)。"
        } else {
            status = ""
        }
    }

    func installUpdate(beforeInstall: () -> Bool) async {
        guard let version = latestVersion, !isBusy, canInstall, let packageURL else { return }
        isBusy = true
        status = "正在下载并校验更新…"
        var stage: URL?
        defer { isBusy = false }
        do {
            let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Daily/Updates", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            Self.cleanup(at: root)
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            stage = directory
            var request = URLRequest(url: packageURL)
            request.timeoutInterval = 120
            let (temporary, response) = try await session.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let final = response.url, final.scheme == "https",
                  final.host == "github.com" || final.host?.hasSuffix(".githubusercontent.com") == true else {
                throw UpdateError.message("安装包下载失败，请重试。")
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0, size <= 64 * 1024 * 1024, packageSize == nil || packageSize == size else {
                throw UpdateError.message("安装包大小与发布信息不一致。")
            }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if let packageDigest, packageDigest.lowercased() != "sha256:" + hash {
                throw UpdateError.message("更新附件 SHA-256 不匹配。")
            }
            let filename = "Daily-macOS-\(version).pkg"
            if let checksumsURL {
                let (bytes, checkResponse) = try await session.data(from: checksumsURL)
                guard (checkResponse as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 16384,
                      let checksums = String(data: bytes, encoding: .utf8), Self.validate(package: data, checksums: checksums, fileName: filename) else {
                    throw UpdateError.message("更新文件校验失败，已取消安装。")
                }
            }
            let package = directory.appendingPathComponent(filename)
            try FileManager.default.copyItem(at: temporary, to: package)
            try await Task.detached { try PackageValidator.validate(package, version: version) }.value
            try Task.checkCancellation()
            guard beforeInstall() else { throw UpdateError.message("当前编辑尚未保存或数据备份失败，已取消更新。") }
            guard NSWorkspace.shared.open(package) else { throw UpdateError.message("安装器无法打开，请从下载页手动安装。") }
            status = "数据已备份，安装器已打开。按提示安装后重新打开 Daily。"
        } catch {
            if let stage { try? FileManager.default.removeItem(at: stage) }
            status = Task.isCancelled ? "已取消更新。" : (error as? UpdateError)?.errorDescription ?? "更新失败，原程序和数据已保留。"
        }
    }

    func cleanupDownloads() {
        Self.cleanup(at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Daily/Updates", isDirectory: true))
    }

    static func cleanup(at directory: URL, now: Date = Date()) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) else { return }
        for entry in entries where UUID(uuidString: entry.lastPathComponent) != nil {
            guard let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, let date = values.contentModificationDate,
                  date < now.addingTimeInterval(-86400) else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    static func validate(package: Data, checksums: String, fileName: String) -> Bool {
        let matches = checksums.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { return nil }
            let name = fields[1].first == "*" ? String(fields[1].dropFirst()) : String(fields[1])
            guard name == fileName else { return nil }
            return String(fields[0]).lowercased()
        }
        guard matches.count == 1 else { return false }
        let actual = SHA256.hash(data: package).map { String(format: "%02x", $0) }.joined()
        return matches[0] == actual
    }

    func openRelease() {
        NSWorkspace.shared.open(releaseURL ?? URL(string: "https://github.com/march7th-26/Daily/releases?q=macos-v")!)
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let numbers = parts.compactMap { part in part.allSatisfy(\.isNumber) ? Int(part) : nil }
        return numbers.count == parts.count ? numbers : nil
    }

    private static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let lhs = versionParts(a) ?? [], rhs = versionParts(b) ?? []
        for index in 0..<max(lhs.count, rhs.count) {
            let x = index < lhs.count ? lhs[index] : 0, y = index < rhs.count ? rhs[index] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private enum UpdateError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case .message(let value): return value }
        }
    }
}
