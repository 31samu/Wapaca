import WebKit

// The worker is deliberately private and is never added to a view or window.
// Only JSON values and PNG bytes cross into the native interface.
@MainActor
final class CalendarEngine: NSObject, WKNavigationDelegate {
    private let worker: WKWebView
    private let resource: URL
    private var loading: CheckedContinuation<Void, Error>?
    private var loadTimer: Timer?
    private var tail: Task<Void, Never>?
    private var failure: Error?
    var onFailure: ((Error) -> Void)?

    override init() {
        resource = Bundle.main.url(forResource: "calendar-worker", withExtension: "html")!
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        worker = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        worker.navigationDelegate = self
        worker.setAccessibilityElement(false)
        if #available(macOS 13.3, *) { worker.isInspectable = false }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            loadTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.finishLoading(
                        WallpaperError.invalid(
                            "The calendar renderer did not start. Reopen Wapacal to retry."))
                }
            }
            worker.loadFileURL(resource, allowingReadAccessTo: resource.deletingLastPathComponent())
        }
    }

    // Calls remain ordered across awaits, including rasterization and refreshes.
    func call(_ body: String, _ arguments: [String: Any] = [:]) async throws -> Any {
        let previous = tail
        let operation = Task { @MainActor in
            await previous?.value
            return try await evaluate(body, arguments)
        }
        tail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    private func evaluate(_ body: String, _ arguments: [String: Any]) async throws -> Any {
        if let failure { throw failure }
        return try await withCheckedThrowingContinuation { continuation in
            var pending: CheckedContinuation<Any, Error>? = continuation
            let timeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
                let current = pending
                pending = nil
                let error = WallpaperError.invalid(
                    "The calendar renderer timed out. Reopen Wapacal to retry.")
                MainActor.assumeIsolated { self.failWorker(error) }
                current?.resume(throwing: error)
            }
            // A detached WKWebView can report a different color scheme from AppKit.
            let appearance =
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? "dark" : "light"
            let script = "window.nativeAppearance('\(appearance)');\n" + body
            worker.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                timeout.invalidate()
                let current = pending
                pending = nil
                switch result {
                case .success(let value): current?.resume(returning: value)
                case .failure(let error): current?.resume(throwing: error)
                }
            }
        }
    }

    private func finishLoading(_ error: Error? = nil) {
        loadTimer?.invalidate()
        loadTimer = nil
        let continuation = loading
        loading = nil
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoading(error)
    }
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) { finishLoading(error) }
    private func failWorker(_ error: Error) {
        failure = error
        worker.stopLoading()
        finishLoading(error)
        onFailure?(error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failWorker(
            WallpaperError.invalid(
                "The calendar renderer stopped. Your saved calendar was kept. Reopen Wapacal to retry."
            ))
    }
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(
            action.targetFrame?.isMainFrame == true
                && action.request.url?.standardizedFileURL == resource.standardizedFileURL
                ? .allow : .cancel)
    }
}
