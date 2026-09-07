import SwiftUI
import UninstallCore

struct LeftoversListColumn: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.isScanningOrphans {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L.leftoversScanning.s).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.orphansScanned {
                VStack(spacing: 16) {
                    Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.pink)
                    Text(L.leftoversIntro.s).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
                    Button(L.scanLeftovers.s) { store.scanOrphans() }.buttonStyle(.borderedProminent)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.orphans.isEmpty {
                EmptyStateView(systemImage: "checkmark.seal.fill", title: L.leftoversNone.s)
            } else {
                List {
                    let high = store.orphans.filter { $0.confidence == .high }
                    let medium = store.orphans.filter { $0.confidence == .medium }
                    if !high.isEmpty {
                        Section {
                            ForEach(high) { OrphanRow(candidate: $0) }
                        } header: {
                            sectionHeader(L.confidenceHigh.s, L.confidenceHighSub.s, "checkmark.circle.fill", .green, high)
                        }
                    }
                    if !medium.isEmpty {
                        Section {
                            ForEach(medium) { OrphanRow(candidate: $0) }
                        } header: {
                            sectionHeader(L.confidenceMedium.s, L.confidenceMediumSub.s, "questionmark.circle.fill", .orange, medium)
                        }
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                let bytes = store.orphans.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
                Text(L.leftoversSummary.f(store.orphans.count, Fmt.bytes(bytes))).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { store.scanOrphans() } label: { Label(L.rescan.s, systemImage: "arrow.clockwise") }
                    .help(L.rescan.s).disabled(store.isScanningOrphans)
            }
        }
        .onAppear { if !store.orphansScanned && !store.isScanningOrphans && !store.apps.isEmpty { store.scanOrphans() } }
        .onChange(of: store.isScanningApps) { scanning in
            if !scanning, !store.orphansScanned, !store.isScanningOrphans { store.scanOrphans() }
        }
    }

    private func sectionHeader(_ title: String, _ sub: String, _ symbol: String, _ color: Color, _ group: [OrphanCandidate]) -> some View {
        let allOn = group.allSatisfy { store.orphanSelection.contains($0.id) }
        return HStack(alignment: .top) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(allOn ? L.deselectAll.s : L.selectAll.s) {
                for c in group { if allOn { store.orphanSelection.remove(c.id) } else { store.orphanSelection.insert(c.id) } }
            }
            .buttonStyle(.link).font(.caption)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

struct OrphanRow: View {
    @EnvironmentObject var store: AppStore
    let candidate: OrphanCandidate

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { store.orphanSelection.contains(candidate.id) },
                set: { if $0 { store.orphanSelection.insert(candidate.id) } else { store.orphanSelection.remove(candidate.id) } }
            )).toggleStyle(.checkbox).labelsHidden()
            CategoryIcon(category: candidate.category, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.url.lastPathComponent).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(L.category(candidate.category).s)
                    if let d = candidate.lastModified { Text("·"); Text(L.modified.f(Fmt.relative(d))) }
                    if !candidate.relatedApps.isEmpty { Text("·"); Text(L.relatedApps.f(candidate.relatedApps.joined(separator: ", "))).lineLimit(1) }
                }
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if candidate.requiresAdmin { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.purple).help(L.cautionAdmin.s) }
            Text(Fmt.bytes(candidate.sizeBytes)).font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .fileContextMenu(candidate.url)
        .onTapGesture(count: 2) { Finder.reveal(candidate.url) }
    }
}

struct LeftoversDetailColumn: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        let sel = store.selectedOrphans
        let bytes = sel.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L.leftoversTitle.s).font(.system(size: 22, weight: .bold))
                            Text(L.leftoversIntro.s).foregroundStyle(.secondary)
                        }
                    }
                    if store.orphansScanned && !store.orphans.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L.selectedSummary.f(sel.count, Fmt.bytes(bytes))).font(.headline)
                                var byCat: [(ResidueCategory, Int64)] {
                                    ResidueCategory.displayOrder.compactMap { cat in
                                        let s = sel.filter { $0.category == cat }.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
                                        return s > 0 ? (cat, s) : nil
                                    }
                                }
                                SizeBar(segments: byCat)
                                ForEach(byCat, id: \.0) { cat, size in
                                    HStack(spacing: 8) {
                                        CategoryIcon(category: cat, size: 20)
                                        Text(L.category(cat).s)
                                        Spacer()
                                        Text(L.itemsShort.f(sel.filter { $0.category == cat }.count)).foregroundStyle(.secondary)
                                        Text(Fmt.bytes(size)).frame(minWidth: 70, alignment: .trailing)
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                        if store.orphans.contains(where: { $0.confidence == .medium }) {
                            Label(L.confidenceMediumSub.s, systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text(L.selectedSummary.f(sel.count, Fmt.bytes(bytes))).font(.callout.weight(.medium))
                Spacer()
                Button {
                    store.requestLeftoverRemoval()
                } label: {
                    Label(L.removeSelectedBtn.s, systemImage: "trash.fill").font(.body.weight(.semibold)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 6).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
                .disabled(sel.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
        }
    }
}
