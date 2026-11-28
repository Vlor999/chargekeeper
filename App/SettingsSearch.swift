import SwiftUI

private struct SettingsTargetKey: EnvironmentKey {
    static let defaultValue: SettingsRowID? = nil
}

extension EnvironmentValues {
    var pickedSearchResultID: SettingsRowID? {
        get { self[SettingsTargetKey.self] }
        set { self[SettingsTargetKey.self] = newValue }
    }
}

private struct SettingsRow: ViewModifier {
    let id: SettingsRowID
    @Environment(\.pickedSearchResultID) private var target

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(id == target ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 4).inset(by: -4))
    }
}

extension View {
    func searchResultAnchor(_ id: SettingsRowID) -> some View { modifier(SettingsRow(id: id)) }
}
