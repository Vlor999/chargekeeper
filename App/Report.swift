import Foundation

var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

var macOSVersion: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
}

var macModel: String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "?" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 else { return "?" }
    return String(cString: buf)
}

private func githubURL(_ path: String, _ params: [(String, String)]) -> URL {
    var c = URLComponents(url: repoURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    c.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
    c.percentEncodedQuery = c.percentEncodedQuery.map(plusKeptLiteralByGitHub)
    return c.url!
}

private func plusKeptLiteralByGitHub(_ percentEncodedQuery: String) -> String {
    percentEncodedQuery.replacingOccurrences(of: "+", with: "%2B")
}

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
        ("category", feedbackDiscussionCategorySlug), ("title", tr("Feedback on ChargeKeeper")), ("body", body),
    ])
}

func bugReportURL(config: Config?) -> URL {
    let fields = [("template", bugIssueFormFile), ("version", appVersion), ("os", macOSVersion), ("mac", macModel)]
    guard let config else { return githubURL("issues/new", fields) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let settings = (try? encoder.encode(config)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    let url = githubURL("issues/new", fields + [("settings", settings)])
    return url.absoluteString.count <= githubPrefillMaxURLLength ? url : githubURL("issues/new", fields)
}
