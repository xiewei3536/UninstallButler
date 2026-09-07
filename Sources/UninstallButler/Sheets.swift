import SwiftUI
import AppKit
import UninstallCore

// MARK: - 解除安裝流程（確認 → 進行中 → 結果）

struct RemovalFlowSheet: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        Group {
            switch store.flow {
            case .confirm(let plan): ConfirmView(plan: plan)
            case .running(let plan): RunningView(plan: plan)
            case .done(let plan, let report): ResultView(plan: plan, report: report)
            case .none: EmptyView()
            }
        }
        .frame(width: 520)
        .interactiveDismissDisabled({ if case .running = store.flow { return true } else { return false } }())
    }
}

struct ConfirmView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var prefs = Prefs.shared
    let plan: UninstallPlan

    private var title: String {
        switch plan.kind {
        case .apps: return plan.apps.count == 1 ? L.confirmTitle.f(plan.apps[0].name) : L.confirmTitleMulti.f(plan.apps.count)
        case .leftovers: return L.confirmLeftoversTitle.f(plan.items.count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                if plan.kind == .apps, let app = plan.apps.first, plan.apps.count == 1 {
                    AppIconView(url: app.resolvedURL, size: 56)
                } else {
                    Image(systemName: "trash.fill").font(.system(size: 28)).foregroundStyle(.white)
                        .frame(width: 56, height: 56).background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.bold))
                    Text(L.confirmBody.f(plan.items.count, Fmt.bytes(plan.totalBytes))).foregroundStyle(.secondary)
                }
            }

            Picker("", selection: $prefs.deletionMode) {
                Label(L.confirmTrash.s, systemImage: "trash").tag(DeletionMode.trash)
                Label(L.confirmPermanent.s, systemImage: "xmark.bin").tag(DeletionMode.permanent)
            }
            .pickerStyle(.segmented).labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                if plan.adminCount > 0 {
                    Label(L.confirmAdminNote.f(plan.adminCount), systemImage: "lock.fill").foregroundStyle(.purple)
                }
                if plan.sharedCount > 0 {
                    Label(L.confirmSharedNote.f(plan.sharedCount), systemImage: "person.2.fill").foregroundStyle(.orange)
                }
                if plan.kind == .apps, plan.apps.contains(where: { store.isRunning($0) }) {
                    Label(L.runningNote.s, systemImage: "play.fill").foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(plan.items) { item in
                        HStack(spacing: 8) {
                            Circle().fill(CategoryStyle.color(item.category)).frame(width: 7, height: 7)
                            Text(Paths.abbreviated(item.url.path)).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.bytes(item.sizeBytes)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
            }
            .frame(height: min(260, CGFloat(plan.items.count) * 20 + 20))
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button(L.cancel.s) { store.dismissFlow() }.keyboardShortcut(.cancelAction)
                Button(plan.kind == .apps ? L.confirmBtn.s : L.removeBtn.s) { store.perform(plan, mode: prefs.deletionMode) }
                    .buttonStyle(.borderedProminent).tint(.red).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
    }
}

struct RunningView: View {
    @EnvironmentObject var store: AppStore
    let plan: UninstallPlan

    private var phaseText: String {
        switch store.progress?.phase {
        case .quitting: return L.phaseQuitting.s
        case .removing, .none: return L.phaseRemoving.s
        case .waitingForAdmin: return L.phaseAdmin.s
        case .finishing: return L.phaseFinishing.s
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(store.progress?.done ?? 0), total: Double(max(1, plan.items.count)))
                .progressViewStyle(.linear)
            Text(phaseText).font(.headline)
            if let cur = store.progress?.current {
                Text(Paths.abbreviated(cur.url.path)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if store.progress?.phase == .waitingForAdmin {
                Image(systemName: "lock.shield").font(.system(size: 28)).foregroundStyle(.purple)
            }
        }
        .padding(28)
        .frame(minHeight: 160)
    }
}

struct ResultView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var prefs = Prefs.shared
    let plan: UninstallPlan
    let report: RemovalReport

    private var allGood: Bool { report.failed.isEmpty && report.skipped.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: allGood ? "checkmark.seal.fill" : (report.adminCancelled ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill"))
                    .font(.system(size: 40)).foregroundStyle(allGood ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(allGood ? L.resultAllGood.s : (report.adminCancelled ? L.resultCancelled.s : L.resultPartial.s)).font(.title3.weight(.bold))
                    Text(L.resultFreed.f(Fmt.bytes(report.freedBytes), report.removed.count)).foregroundStyle(.secondary)
                    if Prefs.dryRun { Text(L.resultDryRun.s).font(.caption).foregroundStyle(.orange) }
                }
            }

            if !report.failed.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L.resultFailedCount.f(report.failed.count), systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout.weight(.semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.failed) { o in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Paths.abbreviated(o.item.url.path)).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                    if case .failed(let msg) = o.status { Text(msg).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 140)
                    .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if !report.skipped.isEmpty {
                Label(L.resultSkippedCount.f(report.skipped.count), systemImage: "forward.fill").foregroundStyle(.secondary).font(.callout)
            }
            if prefs.deletionMode == .trash && !report.removed.isEmpty && !Prefs.dryRun {
                HStack {
                    Text(L.resultInTrash.s).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.openTrash.s) { Finder.showTrash() }
                    Button(L.emptyTrash.s) { Finder.emptyTrash() }
                }
            }
            HStack {
                Spacer()
                Button(L.done.s) { store.dismissFlow() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
    }
}

// MARK: - 設定

struct SettingsSheet: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var prefs = Prefs.shared
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L.settingsTitle.s).font(.title3.weight(.bold))
                Spacer()
                Picker("", selection: $tab) {
                    Text(L.tabGeneral.s).tag(0)
                    Text(L.tabAbout.s).tag(1)
                }
                .pickerStyle(.segmented).frame(width: 180)
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)
            Divider()
            if tab == 0 { general } else { about }
            Divider()
            HStack {
                Spacer()
                Button(L.done.s) { store.showSettings = false }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 560)
    }

    private var general: some View {
        Form {
            Section {
                Picker(L.rowLanguage.s, selection: $prefs.language) {
                    Text(L.langAuto.s).tag("auto")
                    Text("English").tag("en")
                    Text("繁體中文").tag("zh-Hant")
                    Text("简体中文").tag("zh-Hans")
                }
                Picker(L.rowDeletion.s, selection: $prefs.deletionMode) {
                    Text(L.confirmTrash.s).tag(DeletionMode.trash)
                    Text(L.confirmPermanent.s).tag(DeletionMode.permanent)
                }
            } footer: {
                Text(L.rowDeletionSub.s).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker(L.rowUnusedDays.s, selection: $prefs.unusedDays) {
                    ForEach([30, 60, 90, 180, 365], id: \.self) { Text(L.daysFmt.f($0)).tag($0) }
                }
                Toggle(isOn: $prefs.showAppleApps) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.rowShowApple.s)
                        Text(L.rowShowAppleSub.s).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                LabeledContent(L.rowFolders.s) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(prefs.appFolders, id: \.path) { url in
                            HStack {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                Text(Paths.abbreviated(url.path)).font(.system(size: 12, design: .monospaced))
                                Spacer()
                                if prefs.extraFolders.contains(where: { ($0 as NSString).expandingTildeInPath == url.path }) {
                                    Button { prefs.extraFolders.removeAll { ($0 as NSString).expandingTildeInPath == url.path }; store.refreshApps() } label: {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Button(L.addFolder.s) { addFolder() }.controlSize(.small)
                    }
                }
            } footer: {
                Text(L.rowFoldersSub.s).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L.rowFDA.s) {
                    HStack {
                        Image(systemName: store.fdaGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(store.fdaGranted ? Color.green : Color.orange)
                        Text(store.fdaGranted ? L.fdaGranted.s : L.fdaMissing.s)
                        Spacer()
                        Button(L.btnOpenPrivacy.s) { Privileges.openFullDiskAccessSettings() }.controlSize(.small)
                    }
                }
            } footer: {
                Text(L.rowFDASub.s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 470)
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(L.appName.s).font(.title2.weight(.bold))
            Text(L.versionFmt.f(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(L.aboutLine1.s)
                Text(L.aboutLine2.s)
                Text(L.aboutLine3.s)
            }
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(L.showWelcome.s) { store.showSettings = false; store.showWelcome = true }.controlSize(.small)
            Text("© 2026 Bowei · MIT License").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(height: 470)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let p = Paths.abbreviated(url.path)
            if !prefs.extraFolders.contains(p) { prefs.extraFolders.append(p) }
            store.refreshApps()
        }
    }
}

// MARK: - 歡迎

struct WelcomeSheet: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 110, height: 110)
            VStack(spacing: 8) {
                Text(L.welcomeTitle.s).font(.system(size: 24, weight: .bold))
                Text(L.welcomeSub.s).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            VStack(alignment: .leading, spacing: 16) {
                step("1.circle.fill", .blue, L.welcome1Title.s, L.welcome1Sub.s)
                step("2.circle.fill", .green, L.welcome2Title.s, L.welcome2Sub.s)
                step("3.circle.fill", .pink, L.welcome3Title.s, L.welcome3Sub.s)
            }
            .frame(maxWidth: 440)
            HStack(spacing: 10) {
                Image(systemName: store.fdaGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(store.fdaGranted ? Color.green : Color.orange)
                Text(store.fdaGranted ? L.fdaGranted.s : L.welcomeFDA.s).font(.callout)
                Spacer()
                if !store.fdaGranted { Button(L.btnOpenPrivacy.s) { Privileges.openFullDiskAccessSettings() } }
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 440)
            Picker("", selection: $prefs.language) {
                Text(L.langAuto.s).tag("auto")
                Text("English").tag("en")
                Text("繁體中文").tag("zh-Hant")
                Text("简体中文").tag("zh-Hans")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 360)
            Button(L.welcomeStart.s) { prefs.hasSeenWelcome = true; store.showWelcome = false }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(34)
        .frame(width: 540)
    }

    private func step(_ symbol: String, _ color: Color, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(sub).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
