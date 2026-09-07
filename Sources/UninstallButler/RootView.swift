import SwiftUI
import UninstallCore

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var prefs = Prefs.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } content: {
            switch store.section {
            case .apps: AppListColumn().navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
            case .leftovers: LeftoversListColumn().navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 480)
            }
        } detail: {
            Group {
                switch store.section {
                case .apps: AppDetailColumn()
                case .leftovers: LeftoversDetailColumn()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.showSettings = true } label: { Label(L.settings.s, systemImage: "gearshape") }
                        .help(L.settings.s)
                }
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .sheet(isPresented: $store.showSettings) { SettingsSheet().environmentObject(store) }
        .sheet(isPresented: $store.showWelcome) { WelcomeSheet().environmentObject(store) }
        .sheet(isPresented: flowBinding) { RemovalFlowSheet().environmentObject(store) }
        .id(prefs.language)
    }

    private var flowBinding: Binding<Bool> {
        Binding(get: { store.flow != nil }, set: { if !$0 { store.dismissFlow() } })
    }
}

// MARK: - 側邊欄

struct SidebarView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            List(selection: sectionBinding) {
                Section(L.sectionApps.s) {
                    row(.apps(.all), L.listAll.s, "square.grid.2x2.fill", .blue)
                    row(.apps(.unused), L.listUnused.s, "moon.zzz.fill", .indigo)
                    row(.apps(.large), L.listLarge.s, "externaldrive.fill", .orange)
                    row(.apps(.intelOnly), L.listIntelOnly.s, "cpu.fill", .brown)
                    row(.apps(.appStore), L.listAppStore.s, "bag.fill", .cyan)
                    row(.apps(.running), L.listRunning.s, "play.circle.fill", .green)
                }
                Section(L.sectionTools.s) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L.listLeftovers.s)
                            Text(L.listLeftoversSub.s).font(.caption2).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles").foregroundStyle(.pink)
                    }
                    .tag(AppStore.Section.leftovers)
                }
            }
            .listStyle(.sidebar)

            Divider()
            footer
        }
    }

    private func row(_ section: AppStore.Section, _ title: String, _ symbol: String, _ color: Color) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(color) }
            .tag(section)
    }

    private var sectionBinding: Binding<AppStore.Section?> {
        Binding(get: { store.section }, set: { if let s = $0 { store.section = s } })
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if store.fdaGranted { store.showSettings = true } else { Privileges.openFullDiskAccessSettings() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.fdaGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(store.fdaGranted ? Color.green : Color.orange)
                    Text(store.fdaGranted ? L.fdaGranted.s : L.fdaMissing.s)
                        .font(.caption).foregroundStyle(store.fdaGranted ? .secondary : .primary)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help(L.fdaTip.s)

            HStack {
                Button {
                    store.showSettings = true
                } label: {
                    Label(L.settings.s, systemImage: "gearshape").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }
}
