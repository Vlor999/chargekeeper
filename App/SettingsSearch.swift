import SwiftUI

private struct SettingsTargetKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// Id of the search result picked in the sidebar.
    var settingsTarget: String? {
        get { self[SettingsTargetKey.self] }
        set { self[SettingsTargetKey.self] = newValue }
    }
}

private struct SettingsRow: ViewModifier {
    let id: String
    @Environment(\.settingsTarget) private var target

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(id == target ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4).inset(by: -4))
    }
}

extension View {
    /// Scroll anchor and highlight of the settings row with this `SettingsEntry` id.
    func settingsRow(_ id: String) -> some View { modifier(SettingsRow(id: id)) }
}
