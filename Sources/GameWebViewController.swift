import AVFoundation
import UIKit
import WebKit

final class GameWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private static let savedUrlKey = "ddtank_vn_server_url_v1"

    private var webView: WKWebView!
    private let loader = UIActivityIndicatorView(style: .large)
    private let errorStack = UIStackView()
    private let errorLabel = UILabel()
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    private var defaultServerURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "DDTankDefaultServerURL") as? String)
            ?? "https://passes-objective-port-discussions.trycloudflare.com/play"
    }

    private var currentServerURL: String {
        get {
            let saved = UserDefaults.standard.string(forKey: Self.savedUrlKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (saved?.isEmpty == false) ? saved! : defaultServerURL
        }
        set {
            let cleaned = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(cleaned, forKey: Self.savedUrlKey)
        }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.bottom, .left, .right] }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1.0)
        configureAudioAndIdle()
        prepareHaptics()
        setupWebView()
        setupLoaderAndErrorUI()
        setupServerShortcutGesture()
        loadGame()
    }

    private func configureAudioAndIdle() {
        UIApplication.shared.isIdleTimerDisabled = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func prepareHaptics() {
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        // Inject native iOS touch optimization (no tap highlight circle, no long-press callout/copy menu, no pinch zoom)
        let ucc = WKUserContentController()
        ucc.add(self, name: "haptic")
        let cssInject = """
        (function(){
          var st = document.createElement('style');
          st.textContent = '* { -webkit-tap-highlight-color: transparent !important; -webkit-touch-callout: none !important; } html, body { overscroll-behavior: none; touch-action: manipulation; }';
          (document.head || document.documentElement).appendChild(st);
        })();
        """
        ucc.addUserScript(WKUserScript(source: cssInject, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        config.userContentController = ucc

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1.0)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = true
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        view.addSubview(webView)
    }

    private func setupLoaderAndErrorUI() {
        loader.color = UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1.0)
        loader.translatesAutoresizingMaskIntoConstraints = false
        loader.hidesWhenStopped = true
        view.addSubview(loader)

        errorStack.axis = .vertical
        errorStack.alignment = .center
        errorStack.spacing = 12
        errorStack.isHidden = true
        errorStack.translatesAutoresizingMaskIntoConstraints = false

        errorLabel.textColor = .white
        errorLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center

        let retryBtn = makeButton(title: "Thử lại", bg: UIColor(red: 0.95, green: 0.62, blue: 0.07, alpha: 1.0), fg: .black)
        retryBtn.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        let urlBtn = makeButton(title: "Đổi link Server", bg: UIColor(red: 0.12, green: 0.18, blue: 0.30, alpha: 1.0), fg: .white)
        urlBtn.addTarget(self, action: #selector(openServerSettings), for: .touchUpInside)

        let btnRow = UIStackView(arrangedSubviews: [retryBtn, urlBtn])
        btnRow.axis = .horizontal
        btnRow.spacing = 12

        errorStack.addArrangedSubview(errorLabel)
        errorStack.addArrangedSubview(btnRow)
        view.addSubview(errorStack)

        NSLayoutConstraint.activate([
            loader.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loader.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            errorStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func makeButton(title: String, bg: UIColor, fg: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(fg, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        b.backgroundColor = bg
        b.layer.cornerRadius = 10
        b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        return b
    }

    /// 3-finger tap anywhere opens native Server URL switcher / Cache Reset / Reload menu.
    private func setupServerShortcutGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(openServerSettings))
        tap.numberOfTouchesRequired = 3
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
    }

    private func loadGame(ignoreCache: Bool = false) {
        errorStack.isHidden = true
        guard let url = URL(string: currentServerURL) else {
            showError("URL server không hợp lệ:\n\(currentServerURL)")
            return
        }
        loader.startAnimating()
        let policy: URLRequest.CachePolicy = ignoreCache ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        var req = URLRequest(url: url, cachePolicy: policy, timeoutInterval: 25)
        req.setValue("DDTankVN-iOS/1.1", forHTTPHeaderField: "X-Client")
        webView.load(req)
    }

    private func showError(_ msg: String) {
        loader.stopAnimating()
        errorLabel.text = msg
        errorStack.isHidden = false
    }

    @objc private func retryTapped() {
        loadGame(ignoreCache: true)
    }

    @objc private func openServerSettings() {
        let alert = UIAlertController(
            title: "Cấu hình Server DDTank VN",
            message: "Nhập link Cloudflare Tunnel mới (chạm 3 ngón bất kỳ lúc nào để mở bảng này).",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = self.currentServerURL
            tf.placeholder = "https://....trycloudflare.com/play"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Lưu & Tải lại", style: .default) { _ in
            if let text = alert.textFields?.first?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.currentServerURL = text
            }
            self.loadGame(ignoreCache: true)
        })
        alert.addAction(UIAlertAction(title: "Xóa cache & Tải lại", style: .destructive) { _ in
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                self.loadGame(ignoreCache: true)
            }
        })
        alert.addAction(UIAlertAction(title: "Tải lại trang", style: .default) { _ in
            self.webView.reload()
        })
        alert.addAction(UIAlertAction(title: "Đóng", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - WKScriptMessageHandler (Taptic Engine haptics for 3D buttons)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "haptic", let level = message.body as? String else { return }
        switch level {
        case "heavy":
            heavyHaptic.impactOccurred()
        case "medium":
            mediumHaptic.impactOccurred()
        default:
            lightHaptic.impactOccurred()
        }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loader.stopAnimating()
        errorStack.isHidden = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showError("Không thể kết nối server:\n\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showError("Không thể mở server:\n\(error.localizedDescription)\n\nNếu link Cloudflare Tunnel vừa đổi, bấm 'Đổi link Server'.")
    }

    // MARK: - WKUIDelegate (keep popups in same webview)
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
