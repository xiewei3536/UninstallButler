import SwiftUI
import UninstallCore

struct AppListColumn: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isScanningApps && store.apps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L.scanningApps.s).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.visibleApps.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: L.noAppsMatch.s)
            } else {
                List(selection: $store.selection) {
                    ForEach(store.visibleApps) { app in
                        AppRow(app: app, running: store.isRunning(app))
                            .tag(app.id)
                            .fileContextMenu(app.url)
                    }
                }
                .listStyle(.inset)
                .onChange(of: store.selection) { sel in
                    if sel.count == 1, let id = sel.first, let app = store.app(for: id) { store.ensureResidue(for: app) }
                }
            }
            Divider()
            footer
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: L.searchApps.s)
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Menu {
                    Picker(L.sortBy.s, selection: $store.sortKey) {
                        Text(L.sortName.s).tag(AppStore.SortKey.name)
                        Text(L.sortSize.s).tag(AppStore.SortKey.size)
                        Text(L.sortLastUsed.s).tag(AppStore.SortKey.lastUsed)
                        Text(L.sortInstalled.s).tag(AppStore.SortKey.installed)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(L.sortBy.s, systemImage: "arrow.up.arrow.down")
                }
                .help(L.sortBy.s)
                Button { store.refreshApps() } label: { Label(L.refresh.s, systemImage: "arrow.clockwise") }
                    .help(L.refresh.s)
                    .disabled(store.isScanningApps)
            }
        }
    }

    private var footer: some View {
        HStack {
            if store.isScanningApps {
                ProgressView().controlSize(.mini)
            }
            Text(L.appsCount.f(store.visibleApps.count, Fmt.bytes(store.totalAppBytes)))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

struct AppRow: View {
    let app: InstalledApp
    let running: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(url: app.resolvedURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if running { Circle().fill(.green).frame(width: 7, height: 7).help(L.badgeRunning.s) }
                }
                HStack(spacing: 6) {
                    if let v = app.version { Text(v).lineLimit(1) }
                    if app.version != nil { Text("·") }
                    Text(app.sizeBytes == nil ? L.calculating.s : Fmt.bytes(app.sizeBytes))
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            let (t, c) = app.archBadge
            Badge(text: t, color: c)
        }
        .padding(.vertical, 3)
    }
}
