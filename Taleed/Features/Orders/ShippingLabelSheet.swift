import SwiftUI
import UIKit
import WebKit

/// The shipping label to show and print (screens.md §2 G13 screen 3, slice D "Printing the label"): the
/// signed `label.url` of `POST /orders/{id}/ship` or `GET /orders/{id}/label`.
struct ShippingLabelDocument: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The label in the app, with a print path that works: the carrier's PDF or the website's printable
/// page (only the label and its print button since API 1.5.8) in a web view, printed through the system
/// print dialog (`UIPrintInteractionController`).
///
/// - The website's page has its own "Imprimer le bordereau", whose `window.print()` the web view does
///   not handle by itself: the app answers it. A PDF gets the sheet's "Imprimer le bordereau" under it.
/// - The link opens in the web view, never through `UIApplication.open`: `/ar/orders/*` and
///   `/en/orders/*` are universal-link paths of the app.
/// - States: loading; an expired link (the page sends to the sign-in) fetches a fresh one once; an error
///   (offline included) with Retry, which also asks for a fresh link.
struct ShippingLabelSheet: View {
    @State private var model: ShippingLabelModel
    @Environment(LanguageManager.self) private var l10n
    @Environment(AppToasts.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    /// `refresh` asks the API for a fresh link (`GET /orders/{id}/label`); nil when it failed.
    init(document: ShippingLabelDocument, jobName: String, refresh: @escaping @MainActor () async -> URL?) {
        _model = State(initialValue: ShippingLabelModel(url: document.url, jobName: jobName, refresh: refresh))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: l10n.string(.ordersGetShippingLabel)) { dismiss() }
            Divider().overlay(TaleedColor.borderSubtle)
            ZStack {
                ShippingLabelWebView(webView: model.webView)
                    .opacity(model.phase == .loaded ? 1 : 0)
                    .accessibilityHidden(model.phase != .loaded)
                    .accessibilityIdentifier("label.document")
                switch model.phase {
                case .loading:
                    LoadingStateView()
                case let .failed(error):
                    ErrorStateView(error: error, retry: { Task { await model.retry() } }, onBack: { dismiss() })
                case .loaded:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.phase == .loaded, model.isPDF {
                Divider().overlay(TaleedColor.borderSubtle)
                SheetFooterButton(title: l10n.string(.ordersDownloadLabel), isLoading: model.isPrinting,
                                  isEnabled: !model.isPrinting) {
                    Task { await model.print() }
                }
                .accessibilityIdentifier("label.print")
            }
        }
        .background(TaleedColor.surfacePrimary.ignoresSafeArea())
        .task { model.start() }
        .onChange(of: model.printError) { _, error in
            guard let error else { return }
            model.printError = nil
            toasts.show(error: error)
        }
    }
}

/// The web view, owned by the model so the print button reaches it.
private struct ShippingLabelWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Loads the label, answers the page's `window.print()` and prints through the system dialog.
@MainActor
@Observable
final class ShippingLabelModel: NSObject {
    enum Phase: Equatable {
        case loading, loaded
        case failed(ApiError)
    }

    private(set) var phase: Phase = .loading
    private(set) var isPrinting = false
    var printError: ApiError?

    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var url: URL
    @ObservationIgnored private let jobName: String
    @ObservationIgnored private let refresh: @MainActor () async -> URL?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshedExpiredLink = false
    /// The carrier's document is usually a PDF: printed from its bytes, with the sheet's own button (the
    /// website's label page has its print button).
    private(set) var isPDF = false

    /// The name of the message the page's `window.print()` sends.
    static let printMessage = "taleedPrint"

    init(url: URL, jobName: String, refresh: @escaping @MainActor () async -> URL?) {
        self.url = url
        self.jobName = jobName
        self.refresh = refresh
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The mock label draws its barcode and the amount bar with backgrounds: print them, as a PDF would.
        configuration.preferences.shouldPrintBackgrounds = true
        let printScript = "window.print = function () { window.webkit.messageHandlers.\(Self.printMessage).postMessage(null); };"
        configuration.userContentController.addUserScript(
            WKUserScript(source: printScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .white
        super.init()
        configuration.userContentController.add(WeakScriptHandler(target: self), name: Self.printMessage)
        webView.navigationDelegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        load(url)
    }

    /// Retry asks for a fresh link: the signed one lasts an hour.
    func retry() async {
        phase = .loading
        guard let fresh = await refresh() else {
            phase = .failed(.network)
            return
        }
        load(fresh)
    }

    private func load(_ url: URL) {
        self.url = url
        isPDF = false
        phase = .loading
        webView.load(URLRequest(url: url))
    }

    /// The system print dialog, with the PDF's bytes or the page's print formatter.
    func print() async {
        guard phase == .loaded, !isPrinting else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        info.outputType = .general
        controller.printInfo = info
        controller.printingItem = nil
        controller.printFormatter = nil
        if isPDF {
            isPrinting = true
            defer { isPrinting = false }
            let source = webView.url ?? url
            guard
                let (data, _) = try? await URLSession.shared.data(from: source) else {
                printError = .network
                return
            }
            controller.printingItem = data
        } else {
            controller.printFormatter = webView.viewPrintFormatter()
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            let bounds = webView.bounds
            controller.present(from: CGRect(x: bounds.midX, y: bounds.maxY, width: 1, height: 1),
                               in: webView, animated: true)
        } else {
            controller.present(animated: true)
        }
    }

    fileprivate func pagePrinted() {
        Task { await print() }
    }

    /// A signed link the server no longer accepts sends to the sign-in page: ask for a fresh one once.
    private func expired() {
        webView.stopLoading()
        guard !refreshedExpiredLink else {
            phase = .failed(.unknown(status: 403, code: nil))
            return
        }
        refreshedExpiredLink = true
        Task { await retry() }
    }

    private func isSignInPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.path.split(separator: "/").last == "login"
    }

    private func sameSite(_ other: URL?) -> Bool {
        guard let other else { return false }
        return other.host == url.host && other.port == url.port && other.scheme == url.scheme
    }

    private static func error(for error: Error) -> ApiError? {
        let nsError = error as NSError
        // A load replaced by another one (the redirect, a retry) is not a failure.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return nil }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return nil } // Frame load interrupted.
        return .network
    }
}

extension ShippingLabelModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction)
        async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame ?? true else { return .allow }
        let target = navigationAction.request.url
        if isSignInPage(target) {
            expired()
            return .cancel
        }
        // The label page has no links of its own; anything else opens outside the label.
        if navigationAction.navigationType == .linkActivated, !sameSite(target) {
            if let target, ["http", "https"].contains(target.scheme ?? "") { InAppBrowser.open(target) }
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse)
        async -> WKNavigationResponsePolicy {
        guard navigationResponse.isForMainFrame else { return .allow }
        if let http = navigationResponse.response as? HTTPURLResponse, http.statusCode >= 400 {
            phase = .failed(http.statusCode >= 500 ? .server(status: http.statusCode)
                : .unknown(status: http.statusCode, code: nil))
            return .cancel
        }
        isPDF = navigationResponse.response.mimeType == "application/pdf"
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isSignInPage(webView.url) {
            expired()
        } else if case .loading = phase {
            // WebKit refuses some loads with a blank page instead of an error.
            guard let shown = webView.url, ["http", "https"].contains(shown.scheme ?? "") else {
                phase = .failed(.network)
                return
            }
            phase = .loaded
            refreshedExpiredLink = false
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let failure = Self.error(for: error), phase == .loading { phase = .failed(failure) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let failure = Self.error(for: error), phase == .loading { phase = .failed(failure) }
    }
}

/// `WKUserContentController` keeps its handlers: this one does not keep the model.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: ShippingLabelModel?

    init(target: ShippingLabelModel) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == ShippingLabelModel.printMessage else { return }
        MainActor.assumeIsolated { target?.pagePrinted() }
    }
}
