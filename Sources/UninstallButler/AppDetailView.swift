import SwiftUI
import UninstallCore

struct AppDetailColumn: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let apps = store.selectedApps
        if apps.count == 1, let app = apps.first {
            AppDetailView(app: app).id(app.id)
        } else if apps.count > 1 {
            MultiAppDetailView(apps: apps)
        } else {
            EmptyStateView(systemImage: "sparkles.rectangle.stack", title: L.emptyTitle.s, subtitle: L.emptySub.s)
        }
    }
}

// MARK: - 單一 App

struct AppDetailView: View {
    @EnvironmentObject var store: AppStore
    let app: InstalledApp

    private var items: [ResidueItem]? { store.residue[app.id] }
    private var loading: Bool { store.residueLoading.contains(app.id) }
    private var selected: [ResidueItem] { store.selectedItems(for: app) }
    private var running: Bool { store.isRunning(app) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    infoCard
                    if app.isRestricted {
                        Label(L.protectedApp.s, systemImage: "lock.fill")
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let items {
                        summaryCard(items)
                        ForEach(groupedCategories(items), id: \.self) { cat in
                            ResidueGroupView(app: app, category: cat, items: items.filter { $0.category == cat })
                        }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(L.scanningResidue.s).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 30).frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .onAppear { store.ensureResidue(for: app) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            AppIconView(url: app.resolvedURL, size: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 22, weight: .bold)).lineLimit(2)
                HStack(spacing: 6) {
                    if let v = app.version { Text(L.version.f(v)); Text("·") }
                    Text(app.sizeBytes == nil ? L.calculating.s : Fmt.bytes(app.sizeBytes))
                }
                .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if let id = app.bundleID {
                    Text(id).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
                FlowLayout(spacing: 6) {
                    let (t, c) = app.archBadge
                    Badge(text: t, color: c, systemImage: "cpu")
                    if running { Badge(text: L.badgeRunning.s, color: .green, systemImage: "play.fill") }
                    if app.isAppStore { Badge(text: L.badgeAppStore.s, color: .cyan, systemImage: "bag.fill") }
                    if app.isSandboxed { Badge(text: L.badgeSandboxed.s, color: .indigo, systemImage: "shippingbox") }
                    if app.isAppleApp { Badge(text: L.badgeApple.s, color: .secondary, systemImage: "apple.logo") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.rescanResidue(for: app) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help(L.refresh.s).disabled(loading)
        }
    }

    private var infoCard: some View {
        Card {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    Text(L.location.s).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        PathText(url: app.url)
                        Button(L.revealInFinder.s) { Finder.reveal(app.url) }.buttonStyle(.link).font(.caption)
                    }
                }
                GridRow {
                    Text(L.sortLastUsed.s).foregroundStyle(.secondary)
                    Text(app.lastUsed == nil ? L.neverUsedHere.s : Fmt.relative(app.lastUsed))
                }
                GridRow {
                    Text(L.sortInstalled.s).foregroundStyle(.secondary)
                    Text(Fmt.shortDate(app.installedDate))
                }
                if let team = app.teamID {
                    GridRow {
                        Text(L.developer.s).foregroundStyle(.secondary)
                        Text(team).font(.system(.body, design: .monospaced))
                    }
                }
            }
            .font(.callout)
        }
    }

    private func summaryCard(_ items: [ResidueItem]) -> some View {
        let total = items.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        var byCat: [(ResidueCategory, Int64)] = []
        for cat in ResidueCategory.displayOrder {
            let s = items.filter { $0.category == cat }.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
            if s > 0 { byCat.append((cat, s)) }
        }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(L.foundSummary.f(items.count, Fmt.bytes(total))).font(.headline)
                SizeBar(segments: byCat)
                FlowLayout(spacing: 8) {
                    ForEach(byCat.prefix(8), id: \.0) { cat, size in
                        HStack(spacing: 4) {
                            Circle().fill(CategoryStyle.color(cat)).frame(width: 7, height: 7)
                            Text(L.category(cat).s).foregroundStyle(.secondary)
                            Text(Fmt.bytes(size)).foregroundStyle(.primary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func groupedCategories(_ items: [ResidueItem]) -> [ResidueCategory] {
        ResidueCategory.displayOrder.filter { c in items.contains { $0.category == c } }
    }

    private var footer: some View {
        let sel = selected
        let bytes = sel.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.selectedSummary.f(sel.count, Fmt.bytes(bytes))).font(.callout.weight(.medium)).lineLimit(1).fixedSize()
                Toggle(isOn: $store.keepData) { Text(L.keepData.s).font(.caption).lineLimit(1).fixedSize() }
                    .toggleStyle(.checkbox).help(L.keepDataTip.s)
            }
            .layoutPriority(2)
            Spacer(minLength: 12)
            if running && !sel.isEmpty {
                Label(L.runningNote.s, systemImage: "play.circle").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 200, alignment: .trailing)
                    .layoutPriority(0)
            }
            Button {
                store.requestUninstall([app])
            } label: {
                Label(L.uninstallBtn.s, systemImage: "trash.fill")
                    .font(.body.weight(.semibold))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 3)
            }
            .layoutPriority(2)
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(sel.isEmpty || loading || app.isRestricted)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - 類別群組

struct ResidueGroupView: View {
    @EnvironmentObject var store: AppStore
    let app: InstalledApp
    let category: ResidueCategory
    let items: [ResidueItem]

    private var selectedCount: Int { items.filter { store.isSelected($0, app: app) }.count }
    private var size: Int64 { items.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    CategoryIcon(category: category)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.category(category).s).font(.system(size: 13, weight: .semibold))
                        Text(L.categoryHint(category).s).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(items.count == 1 ? L.item1.s : L.items.f(items.count)) · \(Fmt.bytes(size))")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("", isOn: Binding(
                        get: { selectedCount == items.count },
                        set: { store.setCategory(category, selected: $0, app: app) }
                    ))
                    .toggleStyle(.checkbox).labelsHidden()
                    .help(selectedCount == items.count ? L.deselectAll.s : L.selectAll.s)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                Divider().padding(.leading, 12)
                ForEach(items) { item in
                    ResidueRow(item: item, isOn: Binding(
                        get: { store.isSelected(item, app: app) },
                        set: { store.setSelected($0, item: item, app: app) }
                    ))
                    if item.id != items.last?.id { Divider().padding(.leading, 44) }
                }
            }
        }
    }
}

struct ResidueRow: View {
    let item: ResidueItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn).toggleStyle(.checkbox).labelsHidden()
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(item.isDirectory ? Color.accentColor.opacity(0.8) : Color.secondary)
                .font(.system(size: 13))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    PathText(url: item.url.deletingLastPathComponent())
                    reasonText
                }
            }
            Spacer(minLength: 6)
            ForEach(Array(item.cautions.enumerated()), id: \.offset) { _, c in
                cautionBadge(c)
            }
            Text(Fmt.bytes(item.sizeBytes)).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .contentShape(Rectangle())
        .fileContextMenu(item.url)
        .onTapGesture(count: 2) { Finder.reveal(item.url) }
        .opacity(isOn ? 1 : 0.55)
    }

    @ViewBuilder private var reasonText: some View {
        switch item.matchedBy {
        case .programPath: Text("· " + L.matchedByProgram.s).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        case .symlinkTarget: Text("· " + L.matchedByLink.s).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        case .entitlement: Text("· " + L.matchedByEntitlement.s).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        case .vendorFolder(let vendor, _): Text("· " + L.matchedByVendor.f(vendor)).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        case .containerOwner: Text("· " + L.matchedByContainer.s).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        case .vendorPrefix: Text("· " + L.matchedByDeveloper.s).font(.system(size: 10.5)).foregroundStyle(.tertiary)
        default: EmptyView()
        }
    }

    @ViewBuilder private func cautionBadge(_ c: Caution) -> some View {
        switch c {
        case .sharedWith(let apps):
            Badge(text: L.cautionShared.f(apps.joined(separator: ", ")), color: .orange, systemImage: "person.2.fill")
        case .nameMatchOnly:
            Badge(text: L.cautionNameOnly.s, color: .secondary, systemImage: "textformat")
        case .requiresAdmin:
            Badge(text: L.cautionAdmin.s, color: .purple, systemImage: "lock.fill")
        case .sameDeveloper:
            Badge(text: L.cautionSameDeveloper.s, color: .teal, systemImage: "person.crop.circle")
        }
    }
}

// MARK: - 多選

struct MultiAppDetailView: View {
    @EnvironmentObject var store: AppStore
    let apps: [InstalledApp]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            ForEach(Array(apps.prefix(3).enumerated()), id: \.offset) { i, app in
                                AppIconView(url: app.resolvedURL, size: 56).offset(x: CGFloat(i) * 14 - 14)
                            }
                        }
                        .frame(width: 90, height: 60)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.multiTitle.f(apps.count)).font(.system(size: 22, weight: .bold))
                            Text(L.multiSub.s).foregroundStyle(.secondary)
                        }
                    }
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(apps) { app in
                                HStack(spacing: 10) {
                                    AppIconView(url: app.resolvedURL, size: 30)
                                    Text(app.name).font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    if let items = store.residue[app.id] {
                                        let sel = store.selectedItems(for: app)
                                        let bytes = sel.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
                                        Text("\(L.itemsShort.f(sel.count)) · \(Fmt.bytes(bytes))").font(.caption).foregroundStyle(.secondary)
                                        Text("/ \(L.itemsShort.f(items.count))").font(.caption2).foregroundStyle(.tertiary)
                                    } else {
                                        ProgressView().controlSize(.small)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .onAppear { store.ensureResidue(for: app) }
                                if app.id != apps.last?.id { Divider().padding(.leading, 52) }
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        let allLoaded = apps.allSatisfy { store.residue[$0.id] != nil }
        let sel = apps.flatMap { store.selectedItems(for: $0) }
        let bytes = sel.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.selectedSummary.f(sel.count, Fmt.bytes(bytes))).font(.callout.weight(.medium))
                Toggle(isOn: $store.keepData) { Text(L.keepData.s).font(.caption) }.toggleStyle(.checkbox)
            }
            Spacer()
            Button {
                store.requestUninstall(apps.filter { !$0.isRestricted })
            } label: {
                Label(L.uninstallBtn.s, systemImage: "trash.fill").font(.body.weight(.semibold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            .disabled(!allLoaded || sel.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - 簡易流式排版

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
