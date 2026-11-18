import Foundation
import os

/// Local, bounded duration telemetry. No URLs, account IDs, payloads or tokens.
struct LoadTimingSample: Codable {
    let trace: UUID
    let category: String
    let phase: String
    let milliseconds: Double
    var recordedUptime: Double = ProcessInfo.processInfo.systemUptime
}

final class LoadTimingRecorder: @unchecked Sendable {
    static let shared = LoadTimingRecorder()
    private let lock = NSLock()
    private var values: [LoadTimingSample] = []
    private let logger = Logger(subsystem: "app.soom.prototype", category: "LoadPerformance")
    func record(_ sample: LoadTimingSample) {
        lock.lock()
        values.append(sample)
        if values.count > 160 { values.removeFirst(values.count - 160) }
        lock.unlock()
        logger.info("\(sample.category, privacy: .public) \(sample.phase, privacy: .public) \(sample.milliseconds, privacy: .public)ms trace=\(sample.trace.uuidString, privacy: .public)")
    }
    func snapshot() -> [LoadTimingSample] {
        lock.lock(); defer { lock.unlock() }; return values
    }
}

struct LoadTrace {
    let id = UUID()
    let category: String
    private let start = ProcessInfo.processInfo.systemUptime
    init(_ category: String) { self.category = category; mark("request-start") }
    func mark(_ phase: String) {
        LoadTimingRecorder.shared.record(.init(trace: id, category: category, phase: phase,
            milliseconds: max(0, (ProcessInfo.processInfo.systemUptime - start) * 1_000)))
    }
}

/// TTFB includes network travel and server work, not server-only execution.
/// Uses the same default URLSession configuration as the previous shared session.
final class LoadNetworkMetrics: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = LoadNetworkMetrics()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [PhotoNoCacheURLProtocol.self] + (configuration.protocolClasses ?? [])
        return URLSession(configuration: configuration, delegate: shared, delegateQueue: nil)
    }()
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        let id = UUID()
        for transaction in metrics.transactionMetrics {
            if let start = transaction.requestStartDate, let response = transaction.responseStartDate {
                LoadTimingRecorder.shared.record(.init(trace: id, category: "http", phase: "request-to-first-byte",
                    milliseconds: max(0, response.timeIntervalSince(start) * 1_000)))
            }
            if let start = transaction.responseStartDate, let end = transaction.responseEndDate {
                LoadTimingRecorder.shared.record(.init(trace: id, category: "http", phase: "response-transfer",
                    milliseconds: max(0, end.timeIntervalSince(start) * 1_000)))
            }
        }
        LoadTimingRecorder.shared.record(.init(trace: id, category: "http", phase: "task-total",
            milliseconds: max(0, metrics.taskInterval.duration * 1_000)))
    }
}

/// Only authenticated photo metadata/bytes leave the SDK's ordinary transport.
/// Auth refresh, REST, uploads and other buckets keep their existing session.
class PhotoNoCacheURLProtocol: URLProtocol, URLSessionDataDelegate, @unchecked Sendable {
    private static let originLock = NSLock()
    private static var origins = Set<String>()
    private let stateLock = NSLock()
    private var forwardingSession: URLSession?
    private var forwardingTask: URLSessionDataTask?
    private var finished = false

    static func register(projectURL: URL) {
        guard let origin = origin(projectURL), projectURL.path.isEmpty || projectURL.path == "/",
              projectURL.query == nil, projectURL.fragment == nil else { return }
        originLock.lock(); origins.insert(origin); originLock.unlock()
    }
    private static func origin(_ url: URL) -> String? {
        guard url.scheme == "https", let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return "https://\(host):\(url.port ?? 443)"
    }
    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: "SOOMPhotoNoCacheForwarded", in: request) == nil,
              request.httpMethod == "GET", let url = request.url, let key = origin(url),
              url.query == nil, url.fragment == nil,
              request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true,
              request.value(forHTTPHeaderField: "apikey")?.isEmpty == false,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !parts.percentEncodedPath.contains("%"), !url.path.contains("//") else { return false }
        originLock.lock(); let trusted = origins.contains(key); originLock.unlock()
        guard trusted else { return false }
        let components = url.path.split(separator: "/").map(String.init)
        guard components.prefix(3) == ["storage", "v1", "object"] else { return false }
        let index = components.count > 3 && components[3] == "info" ? 4 : 3
        guard components.count > index + 1, ["workout-photos", "activity-photos-candidate"].contains(components[index]),
              components.dropFirst(index + 1).allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\\") }) else { return false }
        return true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    class func forwardingConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.protocolClasses = []
        return configuration
    }
    static func uncached(_ request: URLRequest) -> URLRequest {
        var copy = request
        copy.cachePolicy = .reloadIgnoringLocalCacheData
        copy.setValue("no-store, no-cache, max-age=0", forHTTPHeaderField: "Cache-Control")
        copy.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let forwarded = (copy as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: "SOOMPhotoNoCacheForwarded", in: forwarded)
        return forwarded as URLRequest
    }
    override func startLoading() {
        guard Self.canInit(with: request) else { client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return }
        let session = URLSession(configuration: Self.forwardingConfiguration(), delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: Self.uncached(request))
        stateLock.lock()
        guard !finished else { stateLock.unlock(); session.invalidateAndCancel(); return }
        forwardingSession = session; forwardingTask = task; stateLock.unlock()
        task.resume()
    }
    override func stopLoading() {
        stateLock.lock(); finished = true; let session = forwardingSession; forwardingSession = nil; forwardingTask = nil; stateLock.unlock()
        session?.invalidateAndCancel()
    }
    private func finish(_ error: Error?) {
        stateLock.lock()
        guard !finished else { stateLock.unlock(); return }
        finished = true; let session = forwardingSession; forwardingSession = nil; forwardingTask = nil; stateLock.unlock()
        if let error { client?.urlProtocol(self, didFailWithError: error) }
        else { client?.urlProtocolDidFinishLoading(self) }
        session?.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Even same-origin redirects are rejected: never forward auth to a new URL.
        completionHandler(nil)
        finish(URLError(.httpTooManyRedirects))
        task.cancel()
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        stateLock.lock(); let active = !finished; stateLock.unlock()
        guard active else { completionHandler(.cancel); return }
        guard let http = response as? HTTPURLResponse, !(300...399).contains(http.statusCode) else {
            completionHandler(.cancel); finish(URLError(.httpTooManyRedirects)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateLock.lock(); let active = !finished; stateLock.unlock()
        if active { client?.urlProtocol(self, didLoad: data) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error) }
}
