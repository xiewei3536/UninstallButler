import AppKit
import SwiftUI
import Combine
import UninstallCore

struct UninstallPlan: Identifiable {
    enum Kind { case apps, leftovers }
    let id = UUID()
    var kind: Kind
    var apps: [InstalledApp]
    var items: [ResidueItem]
    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var adminCount: Int { items.filter { $0.requiresAdmin || $0.receiptID != nil || $0.category == .launchDaemons || $0.category == .privilegedHelper }.count }
    var sharedCount: Int { items.filter { $0.cautions.contains { if case .sharedWith = $0 { return true } else { return false } } }.count }
}

enum RemovalFlow {
    case confirm(UninstallPlan)
    case running(UninstallPlan)
    case done(UninstallPlan, RemovalReport)
}

@MainActor
final class AppStore: ObservableObject {
    enum SmartList: Hashable, CaseIterable { case all, unused, large, intelOnly, appStore, running }
    enum Section: Hashable { case apps(SmartList), leftovers }
    enum SortKey: String, CaseIterable { case name, size, lastUsed, installed }

    let prefs = Prefs.shared

    // 導覽
    @Published var section: Section = .apps(.all)
    @Published var searchText = ""
    @Published var sortKey: SortKey = .name
    @Published var selection = Set<String>()

    // App
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isScanningApps = false
    @Published private(set) var runningPaths = Set<String>()
    @Published private(set) var fdaGranted = Privileges.hasFullDiskAccess()

    // 殘留（每個 App 一份）
    @Published private(set) var residue: [String: [ResidueItem]] = [:]
    @Published private(set) var residueLoading = Set<String>()
    @Published var itemSelection: [String: Set<String>] = [:]
    @Published var keepData = false { didSet { if keepData != oldValue { applyKeepData() } } }

    // 殘留清理
    @Published private(set) var orphans: [OrphanCandidate] = []
    @Published var orphanSelection = Set<String>()
    @Published private(set) var isScanningOrphans = false
    @Published private(set) var orphansScanned = false

    // 流程
    @Published var flow: RemovalFlow?
    @Published var progress: RemovalProgress?
    @Published var showSettings = false
    @Published var showWelcome = false

    private var cancellables = Set<AnyCancellable>()
    private var sizeTask: Task<Void, Never>?
    private var scanGeneration = 0

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshRunning() }.store(in: &cancellables)
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fdaGranted = Privileges.hasFullDiskAccess() }
            .store(in: &cancellables)
        prefs.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.objectWillChange.send() }
        }.store(in: &cancellables)
    }

    // MARK: - App 掃描

    func refreshApps() {
        scanGeneration += 1
        let gen = scanGeneration
        isScanningApps = true
        sizeTask?.cancel()
        let folders = prefs.appFolders
        Task.detached(priority: .userInitiated) {
            let found = AppScanner.scan(folders: folders)
            await MainActor.run { [weak self] in
                guard let self, gen == self.scanGeneration else { return }
                self.apps = found
                self.isScanningApps = false
                self.refreshRunning()
                self.selection = self.selection.filter { id in found.contains { $0.id == id } }
                self.residue = self.residue.filter { key, _ in found.contains { $0.id == key } }
                self.startSizeCalculation(generation: gen)
            }
        }
    }

    private func startSizeCalculation(generation gen: Int) {
        let pending = apps.filter { $0.sizeBytes == nil }.map(\.resolvedURL)
        guard !pending.isEmpty else { return }
        sizeTask = Task.detached(priority: .utility) { [weak self] in
            await withTaskGroup(of: (URL, Int64).self) { group in
                var iterator = pending.makeIterator()
                var active = 0
                func addNext(_ group: inout TaskGroup<(URL, Int64)>) -> Bool {
                    guard let url = iterator.next() else { return false }
                    group.addTask { (url, SizeCalculator.bundleSize(of: url)) }
                    return true
                }
                while active < 4, addNext(&group) { active += 1 }
                for await (url, size) in group {
                    if Task.isCancelled { break }
                    await MainActor.run { [weak self] in
                        guard let self, gen == self.scanGeneration else { return }
                        if let i = self.apps.firstIndex(where: { $0.resolvedURL == url }) { self.apps[i].sizeBytes = size }
                    }
                    if addNext(&group) { active += 1 }
                }
            }
        }
    }

    func refreshRunning() {
        var set = Set<String>()
        for app in apps where RunningApps.isRunning(app) { set.insert(app.id) }
        runningPaths = set
    }

    func isRunning(_ app: InstalledApp) -> Bool { runningPaths.contains(app.id) }

    // MARK: - 清單

    var visibleApps: [InstalledApp] {
        var list = apps
        if !prefs.showAppleApps { list = list.filter { !$0.isAppleApp } }
        if case .apps(let smart) = section {
            let unusedCutoff = Date().addingTimeInterval(-Double(prefs.unusedDays) * 86400)
            switch smart {
            case .all: break
            case .unused: list = list.filter { ($0.lastUsed ?? $0.installedDate ?? .distantPast) < unusedCutoff }
            case .large: list = list.filter { ($0.sizeBytes ?? 0) >= 1_000_000_000 }
            case .intelOnly: list = list.filter { $0.archDescription == .intel }
            case .appStore: list = list.filter { $0.isAppStore }
            case .running: list = list.filter { isRunning($0) }
            }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { app in
                app.name.localizedCaseInsensitiveContains(q)
                    || (app.bundleID?.localizedCaseInsensitiveContains(q) ?? false)
                    || (app.bundleName?.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        switch sortKey {
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: list.sort { ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }
        case .lastUsed: list.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        case .installed: list.sort { ($0.installedDate ?? .distantPast) > ($1.installedDate ?? .distantPast) }
        }
        return list
    }

    var totalAppBytes: Int64 { visibleApps.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }

    func app(for id: String) -> InstalledApp? { apps.first { $0.id == id } }
    var selectedApps: [InstalledApp] { selection.compactMap { app(for: $0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    // MARK: - 殘留

    func ensureResidue(for app: InstalledApp) {
        guard residue[app.id] == nil, !residueLoading.contains(app.id) else { return }
        residueLoading.insert(app.id)
        let context = ResidueFinder.Context(installedApps: apps)
        var snapshot = app
        Task.detached(priority: .userInitiated) { [weak self] in
            if snapshot.sizeBytes == nil { snapshot.sizeBytes = SizeCalculator.bundleSize(of: snapshot.resolvedURL) }
            let items = ResidueFinder.find(for: snapshot, context: context)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.residueLoading.remove(app.id)
                self.residue[app.id] = items
                if let i = self.apps.firstIndex(where: { $0.id == app.id }), self.apps[i].sizeBytes == nil { self.apps[i].sizeBytes = snapshot.sizeBytes }
                self.itemSelection[app.id] = Set(items.filter { self.shouldSelectByDefault($0) }.map(\.id))
            }
        }
    }

    func rescanResidue(for app: InstalledApp) {
        residue[app.id] = nil
        itemSelection[app.id] = nil
        ensureResidue(for: app)
    }

    private func shouldSelectByDefault(_ item: ResidueItem) -> Bool {
        if keepData && item.category.isPersonalData { return false }
        return item.defaultSelected
    }

    private func applyKeepData() {
        for (appID, items) in residue {
            var set = itemSelection[appID] ?? []
            for item in items where item.category.isPersonalData {
                if keepData { set.remove(item.id) } else if item.defaultSelected { set.insert(item.id) }
            }
            itemSelection[appID] = set
        }
    }

    func isSelected(_ item: ResidueItem, app: InstalledApp) -> Bool { itemSelection[app.id]?.contains(item.id) ?? false }

    func setSelected(_ selected: Bool, item: ResidueItem, app: InstalledApp) {
        var set = itemSelection[app.id] ?? []
        if selected { set.insert(item.id) } else { set.remove(item.id) }
        itemSelection[app.id] = set
    }

    func setCategory(_ category: ResidueCategory, selected: Bool, app: InstalledApp) {
        guard let items = residue[app.id] else { return }
        var set = itemSelection[app.id] ?? []
        for item in items where item.category == category {
            if selected { set.insert(item.id) } else { set.remove(item.id) }
        }
        itemSelection[app.id] = set
    }

    func selectedItems(for app: InstalledApp) -> [ResidueItem] {
        guard let items = residue[app.id] else { return [] }
        let set = itemSelection[app.id] ?? []
        return items.filter { set.contains($0.id) }
    }

    // MARK: - 殘留清理

    func scanOrphans() {
        guard !isScanningOrphans else { return }
        isScanningOrphans = true
        let installed = apps
        Task.detached(priority: .userInitiated) { [weak self] in
            let found = OrphanScanner.scan(installedApps: installed)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.orphans = found
                self.orphanSelection = Set(found.filter { $0.confidence == .high }.map(\.id))
                self.isScanningOrphans = false
                self.orphansScanned = true
            }
        }
    }

    var selectedOrphans: [OrphanCandidate] { orphans.filter { orphanSelection.contains($0.id) } }

    // MARK: - 解除安裝流程

    func requestUninstall(_ targets: [InstalledApp]) {
        var items: [ResidueItem] = []
        for app in targets { items += selectedItems(for: app) }
        guard !items.isEmpty else { return }
        flow = .confirm(UninstallPlan(kind: .apps, apps: targets, items: items))
    }

    func requestLeftoverRemoval() {
        let items = selectedOrphans.map { $0.asResidueItem() }
        guard !items.isEmpty else { return }
        flow = .confirm(UninstallPlan(kind: .leftovers, apps: [], items: items))
    }

    func perform(_ plan: UninstallPlan, mode: DeletionMode) {
        flow = .running(plan)
        progress = RemovalProgress(phase: .quitting, done: 0, total: plan.items.count, current: nil)
        let options = RemovalOptions(mode: mode, dryRun: Prefs.dryRun)
        Task.detached(priority: .userInitiated) { [weak self] in
            let report = Remover.uninstall(apps: plan.apps, items: plan.items, options: options) { p in
                Task { @MainActor [weak self] in self?.progress = p }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.flow = .done(plan, report)
                self.afterRemoval(plan, report)
            }
        }
    }

    private func afterRemoval(_ plan: UninstallPlan, _ report: RemovalReport) {
        let removedPaths = Set(report.removed.map { $0.item.url.path })
        switch plan.kind {
        case .apps:
            for app in plan.apps {
                residue[app.id] = nil
                itemSelection[app.id] = nil
                if removedPaths.contains(app.url.path) && !Prefs.dryRun {
                    apps.removeAll { $0.id == app.id }
                    selection.remove(app.id)
                } else {
                    ensureResidue(for: app)
                }
            }
            orphansScanned = false
        case .leftovers:
            if !Prefs.dryRun { orphans.removeAll { removedPaths.contains($0.url.path) } }
            orphanSelection = orphanSelection.filter { !removedPaths.contains($0) }
        }
        refreshRunning()
    }

    func dismissFlow() {
        flow = nil
        progress = nil
    }
}

// MARK: - 圖示快取

enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(for url: URL) -> NSImage {
        if let img = cache.object(forKey: url.path as NSString) { return img }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 128, height: 128)
        cache.setObject(img, forKey: url.path as NSString)
        return img
    }
}
