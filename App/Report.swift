import Foundation

// Prefilled GitHub pages: the app only opens an address, the user writes and posts in the browser.
// No API call, no token, nothing identifying in the text.

var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

/// "macOS 26.1".
var macOSVersion: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
}

private func githubURL(_ path: String, _ params: [(String, String)]) -> URL {
    var c = URLComponents(url: repoURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    c.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
    // URLComponents leaves "+" as is, which GitHub reads as a space.
    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return c.url!
}

/// "Send feedback": discussion in the ideas category, message written in the browser, context below.
func feedbackURL() -> URL {
    let body = [
        tr("<!-- Your idea, question or remark. The context below helps understand it. -->"),
        "",
        "---",
        "### " + tr("Context"),
        "- " + tr("Version: %@", appVersion),
        "- " + tr("System: %@", macOSVersion),
    ].joined(separator: "\n")
    return githubURL("discussions/new", [
        ("category", feedbackDiscussionCategory), ("title", tr("Feedback on ChargeKeeper")), ("body", body),
    ])
}
