import Foundation
import Combine

@MainActor final class QuoteStore: ObservableObject {
    @Published private(set) var text = "把平凡的小事，做成今天的光。"
    @Published private(set) var source: String?
    @Published private(set) var isLoading = false
    @Published private(set) var status = "点击换一句"
    private let session: URLSession
    private let defaults: UserDefaults
    private let now: () -> Date
    private var retryAfter: Date?
    private var retryTask: Task<Void, Never>?
    private let cacheKey = "dailyQuote"

    private struct Quote: Codable {
        let hitokoto: String
        let from: String?
        let from_who: String?
    }
    private struct Cache: Codable {
        let day: Date
        let quote: Quote
    }

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.session = session
        self.defaults = defaults
        self.now = now
        if let cache = cached() { show(cache.quote) }
    }

    deinit { retryTask?.cancel() }

    private func cached() -> Cache? {
        defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    }
    private func show(_ quote: Quote) {
        text = quote.hitokoto
        source = [quote.from_who, quote.from].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if source?.isEmpty == true { source = nil }
    }

    func refresh(for date: Date, force: Bool = false) async {
        guard !isLoading else { return }
        if !force {
            if let cache = cached(), Calendar.current.isDate(cache.day, inSameDayAs: date) { return }
            if let retryAfter, now() < retryAfter { return }
        }
        isLoading = true
        status = "正在换一句…"
        defer { isLoading = false }
        do {
            let url = URL(string: "https://v1.hitokoto.cn/?c=d&c=k&min_length=8&max_length=42")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.timeoutInterval = 12
            request.setValue("Daily-macOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8192 else { throw URLError(.badServerResponse) }
            let quote = try JSONDecoder().decode(Quote.self, from: data)
            let clean = quote.hitokoto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.utf16.count <= 80, !clean.contains("<"), !clean.contains(">") else { throw URLError(.cannotParseResponse) }
            let cleaned = Quote(hitokoto: clean, from: quote.from, from_who: quote.from_who)
            defaults.set(try JSONEncoder().encode(Cache(day: date, quote: cleaned)), forKey: cacheKey)
            show(cleaned)
            retryAfter = nil
            retryTask?.cancel()
            status = "点击换一句"
        } catch is CancellationError {
            status = "点击换一句"
        } catch {
            retryAfter = now().addingTimeInterval(30 * 60)
            status = "暂时无法更新，原句已保留；点击重试"
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 1_800_000_000_000) } catch { return }
                guard let self else { return }
                await self.refresh(for: self.now())
            }
        }
    }
}
