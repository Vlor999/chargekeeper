import AppKit
import SwiftUI

/// Settings > Diagnostic: the service's log settings and its latest entries. Read when the pane opens and on Reload only.
struct DiagnosticView: View {
    @EnvironmentObject var m: AppModel
    @State private var minLevel = LogLevel.info
    @State private var lines: [LogLine]?
    @State private var error: String?
    /// Only the latest load publishes: an earlier one finishing late is dropped.
    @State private var generation = 0

    var body: some View {
        Form {
            Section {
                Picker(tr("Sampling interval"), selection: m.config(\.powerInterval)) {
                    Text(tr("Off")).tag(PowerInterval.off)
                    ForEach(PowerInterval.allCases.filter { $0 != .off }, id: \.self) { Text(tr("%d s", $0.rawValue)).tag($0) }
                }
                .settingsRow("powerInterval")
            } header: {
                Text(tr("Power by component"))
            } footer: {
                Text(tr("CPU, GPU and Neural Engine power, measured by the service with powermetrics even when no window is open. Shorter is finer but costs more: about 3 % CPU at 1 s, 0.7 % at 5 s. Off hides the graphs."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(tr("Keep a diagnostic log"), isOn: m.config(\.logEnabled))
                    .settingsRow("logEnabled")
                Stepper(m.config(\.logDays).wrappedValue == 1 ? tr("Keep: 1 day") : tr("Keep: %d days", m.config(\.logDays).wrappedValue), value: m.config(\.logDays), in: logDaysRange)
                    .settingsRow("logDays")
                LabeledContent(tr("Folder")) {
                    HStack {
                        Text(logDir).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Button(tr("Open Folder")) { NSWorkspace.shared.open(URL(fileURLWithPath: logDir, isDirectory: true)) }
                    }
                }
                .settingsRow("logFolder")
            } header: {
                Text(tr("Log"))
            } footer: {
                Text(tr("Written by the ChargeKeeper service on this Mac only: service start and stop, charge decisions, errors. Nothing is sent. Whole days older than the retention are deleted."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Picker(tr("Level"), selection: $minLevel) {
                        Text(tr("All")).tag(LogLevel.info)
                        Text(tr("Warnings")).tag(LogLevel.warn)
                        Text(tr("Errors")).tag(LogLevel.error)
                    }
                    .pickerStyle(.segmented).fixedSize()
                    Spacer()
                    Button(tr("Reload"), action: load)
                    Button(tr("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString((lines ?? []).map(logLineText).joined(), forType: .string)
                    }
                    .disabled(lines?.isEmpty ?? true)
                }
                .settingsRow("logViewer")
                if m.status.map({ !$0.config.logEnabled }) == true {
                    Text(tr("Log off: no new entry.")).font(.caption).foregroundStyle(.secondary)
                }
                if let error {
                    Text(tr("Error: %@", error)).font(.caption).foregroundStyle(.red)
                }
                if let lines, lines.isEmpty {
                    Text(tr("No entry")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                } else if let lines {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(lines.indices, id: \.self) { i in LogRow(line: lines[i]) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
            } header: {
                Text(tr("Latest entries"))
            } footer: {
                Text(tr("The %d most recent, newest first.", logViewLimit)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: minLevel) { _, _ in load() }
    }

    /// Files read off the main thread: a day's file can reach a few MB.
    func load() {
        let level = minLevel
        generation += 1
        let g = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let r = Result { try readLog(limit: logViewLimit, minLevel: level) }
            DispatchQueue.main.async {
                guard g == generation else { return }
                switch r {
                case .success(let l): lines = l; error = nil
                case .failure(let e): error = e.localizedDescription
                }
            }
        }
    }
}

struct LogRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.date.formatted(Date.FormatStyle().month(.twoDigits).day(.twoDigits).hour().minute().second().locale(appLocale)))
                .foregroundStyle(.secondary)
            Text(line.level.rawValue.uppercased())
                .foregroundStyle(line.level == .error ? .red : line.level == .warn ? .orange : .secondary)
                .frame(width: 44, alignment: .leading)
            Text(line.message).textSelection(.enabled)
        }
        .font(.caption.monospaced())
    }
}

/// Latest entries at `minLevel` or above, newest first, from the newest files back. Files are opened without following a
/// link and must be regular; unreadable files and lines are skipped. No folder yet (service never logged): no entry; a folder
/// that exists but cannot be listed: error.
func readLog(limit: Int, minLevel: LogLevel) throws -> [LogLine] {
    let names: [String]
    do { names = try FileManager.default.contentsOfDirectory(atPath: logDir) } catch {
        if FileManager.default.fileExists(atPath: logDir) { throw error }
        return []
    }
    var out: [LogLine] = []
    for (_, name) in names.compactMap({ n in logFileDay(n).map { ($0, n) } }).sorted(by: { $0.0 > $1.0 }) {
        let fd = open(logDir + "/" + name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { continue }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG,
              let data = try? h.read(upToCount: logMaxFileBytes + logFullReserveBytes) else { continue }
        for l in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed() {
            guard let e = parseLogLine(l), e.level >= minLevel else { continue }
            out.append(e)
            if out.count >= limit { return out }
        }
    }
    return out
}
