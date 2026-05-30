import SwiftUI
import AppKit

private enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case panel
    case startup
    case storage
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance:
            return "外観"
        case .panel:
            return "パネル"
        case .startup:
            return "起動"
        case .storage:
            return "保存"
        case .privacy:
            return "プライバシー"
        }
    }

    var systemImage: String {
        switch self {
        case .appearance:
            return "rectangle.grid.1x2"
        case .panel:
            return "macwindow"
        case .startup:
            return "power"
        case .storage:
            return "externaldrive"
        case .privacy:
            return "lock"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @StateObject private var launchAtLoginController = LaunchAtLoginController()
    @State private var selectedSection: SettingsSection = .appearance
    @State private var saveMessage: String?
    @State private var isResetConfirmationVisible = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sectionHeader
                    activePane
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 760, idealWidth: 760, minHeight: 540, idealHeight: 540)
        .alert(isPresented: $isResetConfirmationVisible) {
            Alert(
                title: Text("設定を初期値に戻しますか？"),
                message: Text("表示、パネル、保存、プライバシー関連の設定を初期値に戻します。"),
                primaryButton: .destructive(Text("リセット")) {
                    settingsStore.resetToDefaults()
                    saveMessage = "初期値に戻しました。"
                    refreshLaunchAtLoginState()
                },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        }
        .onAppear {
            refreshLaunchAtLoginState()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppInfo.displayName)
                .font(.title3.bold())
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 8)

            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarButton(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSection = section
                }
            }

            Spacer()

            Text(saveMessage ?? "設定は自動保存されます。")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .frame(width: 176)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedSection.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            Text(selectedSection.title)
                .font(.title2.bold())
            Spacer()
            Button("初期値に戻す") {
                isResetConfirmationVisible = true
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var activePane: some View {
        switch selectedSection {
        case .appearance:
            appearancePane
        case .panel:
            panelPane
        case .startup:
            startupPane
        case .storage:
            storagePane
        case .privacy:
            privacyPane
        }
    }

    private var appearancePane: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "テーマ", systemImage: "circle.lefthalf.filled") {
                SettingsRow(title: "表示モード", detail: "macOS の設定に合わせるか、明るい/暗い表示に固定します。") {
                    Picker("", selection: binding(\.appearanceMode)) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(localizedName(for: mode)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }

            SettingsCard(title: "履歴表示", systemImage: "rectangle.split.3x1") {
                SettingsRow(title: "履歴の表示", detail: "メニューバーから開く履歴の並び方") {
                    Picker("", selection: binding(\.historyLayout)) {
                        ForEach(HistoryLayout.allCases) { layout in
                            Text(localizedName(for: layout)).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

            }

            SettingsCard(title: "コピーのフィードバック", systemImage: "checkmark.circle") {
                SettingsToggleRow(
                    title: "サウンド",
                    detail: "保存またはコピーに成功したとき、短いクリック音を鳴らします。",
                    isOn: binding(\.copyFeedbackSoundEnabled)
                )

                SettingsToggleRow(
                    title: "メニューバーのアニメーション",
                    detail: "保存またはコピーに成功したとき、アイコンを短く弾ませます。",
                    isOn: binding(\.copyFeedbackAnimationEnabled)
                )
            }

        }
    }

    private var panelPane: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "パネルサイズ", systemImage: "arrow.up.left.and.arrow.down.right") {
                SettingsRow(title: "表示位置", detail: "履歴パネルを表示する画面端") {
                    Picker("", selection: binding(\.panelPlacement)) {
                        ForEach(PanelPlacement.allCases) { placement in
                            Text(localizedName(for: placement)).tag(placement)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }

                SettingsRow(title: "サイズ", detail: "履歴パネルの表示サイズ") {
                    Picker("", selection: binding(\.panelSizePreset)) {
                        ForEach(PanelSizePreset.allCases) { preset in
                            Text(localizedName(for: preset)).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }

                SettingsRow(title: "現在のサイズ", detail: "表示位置に合わせて画面内に収まるよう自動調整済み") {
                    SettingsBadge(text: "\(Int(effectivePanelSize.width)) x \(Int(effectivePanelSize.height)) px")
                }

                if settingsStore.settings.panelSizePreset == .custom {
                    SettingsRow(title: "幅", detail: "左右表示時のカスタム横幅") {
                        Stepper("\(Int(settingsStore.settings.customPanelWidth)) px", value: binding(\.customPanelWidth), in: AppSettings.minimumCustomPanelWidth...maxCustomPanelWidth, step: 20)
                            .frame(width: 170)
                    }

                    SettingsRow(title: "高さ", detail: "上下表示時のカスタム高さ") {
                        Stepper("\(Int(settingsStore.settings.customPanelHeight)) px", value: binding(\.customPanelHeight), in: AppSettings.minimumPanelHeight...maxCustomPanelHeight, step: 20)
                            .frame(width: 170)
                    }
                }
            }

            SettingsCard(title: "貼り付け", systemImage: "command") {
                SettingsToggleRow(
                    title: "カード選択時に自動貼り付け",
                    detail: "履歴カードをクリックしたとき、コピー後に直前のアプリへ戻って貼り付けを試みます。",
                    isOn: binding(\.autoPasteOnCardSelection)
                )
            }
        }
    }

    private var startupPane: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "ログイン項目", systemImage: "person.crop.circle.badge.checkmark") {
                SettingsToggleRow(
                    title: "ログイン時に起動",
                    detail: "macOS のログイン項目として \(AppInfo.displayName) を登録します。",
                    isOn: launchAtLoginBinding
                )
                .disabled(!launchAtLoginController.isSupported)

                SettingsRow(title: "状態", detail: "現在のログイン項目登録状態") {
                    SettingsBadge(
                        text: localizedLaunchAtLoginState,
                        style: launchAtLoginController.state.isConfiguredOn ? .success : .neutral
                    )
                }

                HStack(spacing: 10) {
                    Button("状態を更新") {
                        refreshLaunchAtLoginState()
                    }

                    Button("システム設定を開く") {
                        launchAtLoginController.openSystemSettingsLoginItems()
                    }
                    .disabled(!launchAtLoginController.isSupported)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if !launchAtLoginController.isSupported {
                SettingsInfoCard(
                    title: "この macOS では直接登録できません",
                    message: "ログイン項目の直接操作は macOS 13 以降で利用できます。"
                )
            }
        }
    }

    private var storagePane: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "読み込み", systemImage: "list.bullet.rectangle") {
                SettingsRow(title: "表示する履歴数", detail: "履歴パネルに読み込む最大件数") {
                    Stepper("\(settingsStore.settings.fetchLimit) 件", value: binding(\.fetchLimit), in: 20...1000, step: 20)
                        .frame(width: 150)
                }
            }

            SettingsCard(title: "保持期間", systemImage: "archivebox") {
                SettingsToggleRow(
                    title: "保存件数を制限",
                    detail: "古い履歴から自動的に整理します。",
                    isOn: maxStoredItemsEnabled
                )

                if settingsStore.settings.maxStoredItems != nil {
                    SettingsRow(title: "最大保存件数", detail: "SQLite に保持する履歴数") {
                        Stepper("\(settingsStore.settings.maxStoredItems ?? 500) 件", value: maxStoredItemsValue, in: 20...5000, step: 20)
                            .frame(width: 150)
                    }
                }

                SettingsToggleRow(
                    title: "古い履歴を削除",
                    detail: "指定日数を超えた履歴を整理します。",
                    isOn: maxAgeDaysEnabled
                )

                if settingsStore.settings.maxAgeDays != nil {
                    SettingsRow(title: "最大保持日数", detail: "この日数を超えた履歴を削除対象にします。") {
                        Stepper("\(settingsStore.settings.maxAgeDays ?? 30) 日", value: maxAgeDaysValue, in: 1...365, step: 1)
                            .frame(width: 150)
                    }
                }
            }
        }
    }

    private var privacyPane: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "プライベートモード", systemImage: "eye.slash") {
                SettingsToggleRow(
                    title: "起動時にプライベートモード",
                    detail: "起動直後から新規履歴の保存を停止します。メニューバーと Dashboard から一時的に切り替えできます。",
                    isOn: binding(\.privateModeOnLaunch)
                )

                SettingsPrivacyStatusRow(
                    systemImage: "hand.raised.slash",
                    title: "保存停止の範囲",
                    detail: "ON 中の新規コピーは、テキストや画像の内容を読み取る前に保存をスキップします。",
                    status: "現在の動作"
                )
            }

            SettingsCard(title: "機微情報", systemImage: "lock.shield") {
                SettingsPrivacyStatusRow(
                    systemImage: "text.viewfinder",
                    title: "秘密情報のプレビュー",
                    detail: "API キー、JWT、秘密鍵、password/token 形式の値は履歴カードで内容を隠します。",
                    status: "自動"
                )

                SettingsPrivacyStatusRow(
                    systemImage: "nosign",
                    title: "機微マーカー付きペーストボード",
                    detail: "アプリが concealed として渡したクリップボード内容は保存しません。",
                    status: "保存しない"
                )
            }

            SettingsCard(title: "アプリ除外リスト", systemImage: "hand.raised") {
                SettingsPrivacyStatusRow(
                    systemImage: "app.badge",
                    title: "除外アプリ",
                    detail: "一致した bundle identifier のアプリが前面にある場合、内容を読む前に保存をスキップします。",
                    status: "有効"
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("設定ファイル")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(blacklistPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                }

                HStack(spacing: 10) {
                    Button("Finder で表示") {
                        openBlacklistLocation()
                    }

                    Button("除外リストを再読み込み") {
                        SecurityManager.shared.reloadApplicationBlacklist()
                        saveMessage = "除外リストを再読み込みしました。"
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var blacklistPath: String {
        (try? AppPaths.blacklistURL().path) ?? "利用できません"
    }

    private var maxCustomPanelWidth: Double {
        let screenWidth = Double(NSScreen.main?.visibleFrame.width ?? 1_440)
        return max(AppSettings.minimumCustomPanelWidth, screenWidth - AppSettings.horizontalScreenInset)
    }

    private var maxCustomPanelHeight: Double {
        let screenHeight = Double(NSScreen.main?.visibleFrame.height ?? 900)
        return max(AppSettings.minimumPanelHeight, min(AppSettings.maximumPanelHeight, screenHeight - AppSettings.verticalScreenInset))
    }

    private var effectivePanelSize: CGSize {
        let visibleSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1_440, height: 900)
        return settingsStore.settings.effectivePanelSize(for: visibleSize)
    }

    private var localizedLaunchAtLoginState: String {
        switch launchAtLoginController.state {
        case .unsupported:
            return "未対応"
        case .notRegistered:
            return "オフ"
        case .enabled:
            return "オン"
        case .requiresApproval:
            return "承認が必要"
        case .notFound:
            return "未検出"
        case .error:
            return "エラー"
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.launchAtLogin },
            set: { enabled in
                if launchAtLoginController.setEnabled(enabled) {
                    settingsStore.settings.launchAtLogin = enabled
                    persistSettings(message: enabled ? "ログイン時起動を有効にしました。" : "ログイン時起動を無効にしました。")
                } else {
                    settingsStore.settings.launchAtLogin = launchAtLoginController.state.isConfiguredOn
                    persistSettings(message: launchAtLoginController.state.displayName)
                }
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.settings[keyPath: keyPath] = newValue
                persistSettings()
            }
        )
    }

    private var maxStoredItemsEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.maxStoredItems != nil },
            set: { enabled in
                settingsStore.settings.maxStoredItems = enabled ? (settingsStore.settings.maxStoredItems ?? AppSettings.defaultMaxStoredItems) : nil
                persistSettings()
            }
        )
    }

    private var maxStoredItemsValue: Binding<Int> {
        Binding(
            get: { settingsStore.settings.maxStoredItems ?? AppSettings.defaultMaxStoredItems },
            set: { value in
                settingsStore.settings.maxStoredItems = value
                persistSettings()
            }
        )
    }

    private var maxAgeDaysEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.maxAgeDays != nil },
            set: { enabled in
                settingsStore.settings.maxAgeDays = enabled ? (settingsStore.settings.maxAgeDays ?? AppSettings.defaultMaxAgeDays) : nil
                persistSettings()
            }
        )
    }

    private var maxAgeDaysValue: Binding<Int> {
        Binding(
            get: { settingsStore.settings.maxAgeDays ?? AppSettings.defaultMaxAgeDays },
            set: { value in
                settingsStore.settings.maxAgeDays = value
                persistSettings()
            }
        )
    }

    private func persistSettings(message: String? = nil) {
        saveMessage = settingsStore.save() ? (message ?? "保存しました。") : "保存に失敗しました。"
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginController.refresh()
        guard launchAtLoginController.isSupported else { return }
        settingsStore.settings.launchAtLogin = launchAtLoginController.state.isConfiguredOn
        _ = settingsStore.save()
    }

    private func openBlacklistLocation() {
        guard let url = try? AppPaths.blacklistURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func localizedName(for layout: HistoryLayout) -> String {
        switch layout {
        case .horizontal:
            return "横スクロール"
        case .grid:
            return "グリッド"
        case .list:
            return "リスト"
        }
    }

    private func localizedName(for preset: PanelSizePreset) -> String {
        switch preset {
        case .compact:
            return "コンパクト"
        case .standard:
            return "標準"
        case .large:
            return "大"
        case .custom:
            return "カスタム"
        }
    }

    private func localizedName(for placement: PanelPlacement) -> String {
        switch placement {
        case .bottom:
            return "下"
        case .top:
            return "上"
        case .left:
            return "左"
        case .right:
            return "右"
        }
    }

    private func localizedName(for visibility: FolderSidebarVisibility) -> String {
        switch visibility {
        case .automatic:
            return "自動"
        case .always:
            return "常に表示"
        case .hidden:
            return "非表示"
        }
    }

    private func localizedName(for mode: AppAppearanceMode) -> String {
        switch mode {
        case .system:
            return "システム"
        case .light:
            return "ライト"
        case .dark:
            return "ダーク"
        }
    }
}

private struct SettingsSidebarButton: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .frame(width: 18)
                Text(section.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)
            }

            VStack(spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsPrivacyStatusRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let status: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 20)

            SettingsBadge(text: status, style: .success)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SettingsBadgeStyle {
    case neutral
    case success
}

private struct SettingsBadge: View {
    let text: String
    var style: SettingsBadgeStyle = .neutral

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .cornerRadius(8)
    }

    private var foregroundColor: Color {
        switch style {
        case .neutral:
            return .secondary
        case .success:
            return .green
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral:
            return Color.secondary.opacity(0.12)
        case .success:
            return Color.green.opacity(0.14)
        }
    }
}

private struct SettingsInfoCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
    }
}
