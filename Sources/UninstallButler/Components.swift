import SwiftUI
import AppKit
import UninstallCore

// MARK: - App 圖示

struct AppIconView: View {
    let url: URL
    var size: CGFloat = 32
    var body: some View {
        Image(nsImage: IconCache.icon(for: url))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

// MARK: - 小標籤

struct Badge: View {
    let text: String
    var color: Color = .secondary
    var systemImage: String? = nil
    var filled = false
    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .foregroundStyle(filled ? Color.white : color)
        .background(filled ? color : color.opacity(0.14), in: Capsule())
    }
}

extension InstalledApp {
    var archBadge: (String, Color) {
        switch archDescription {
        case .universal: return (L.badgeUniversal.s, .green)
        case .appleSilicon: return (L.badgeAppleSilicon.s, .blue)
        case .intel: return (L.badgeIntel.s, .orange)
        case .unknown: return (L.unknown.s, .secondary)
        }
    }
}

// MARK: - 類別外觀

enum CategoryStyle {
    static func color(_ c: ResidueCategory) -> Color {
        switch c {
        case .appBundle: return .blue
        case .container: return .indigo
        case .appSupport: return .teal
        case .preferences: return .purple
        case .caches: return .orange
        case .savedState: return .mint
        case .webData: return .cyan
        case .logs: return Color(nsColor: .systemGray)
        case .crashReports: return .red
        case .launchAgents: return .yellow
        case .launchDaemons: return .brown
        case .privilegedHelper: return .pink
        case .receipts: return Color(nsColor: .systemGray)
        case .plugins: return .green
        case .commandLine: return Color(nsColor: .darkGray)
        case .appScripts: return .teal
        case .recentDocuments: return Color(nsColor: .systemGray)
        case .groupContainer: return .indigo
        case .temporary: return .orange
        case .other: return Color(nsColor: .systemGray)
        }
    }

    static func symbol(_ c: ResidueCategory) -> String {
        switch c {
        case .appBundle: return "app.fill"
        case .container: return "shippingbox.fill"
        case .appSupport: return "folder.fill"
        case .preferences: return "slider.horizontal.3"
        case .caches: return "clock.arrow.circlepath"
        case .savedState: return "macwindow"
        case .webData: return "globe"
        case .logs: return "doc.text.fill"
        case .crashReports: return "exclamationmark.triangle.fill"
        case .launchAgents: return "bolt.fill"
        case .launchDaemons: return "gearshape.2.fill"
        case .privilegedHelper: return "lock.shield.fill"
        case .receipts: return "doc.plaintext.fill"
        case .plugins: return "puzzlepiece.extension.fill"
        case .commandLine: return "terminal.fill"
        case .appScripts: return "scroll.fill"
        case .recentDocuments: return "clock.fill"
        case .groupContainer: return "person.2.fill"
        case .temporary: return "archivebox.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

struct CategoryIcon: View {
    let category: ResidueCategory
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: CategoryStyle.symbol(category))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(CategoryStyle.color(category).gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

// MARK: - 大小分布條

struct SizeBar: View {
    let segments: [(ResidueCategory, Int64)]
    var height: CGFloat = 10
    var body: some View {
        let total = max(1, segments.reduce(0) { $0 + $1.1 })
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let w = max(2, geo.size.width * CGFloat(seg.1) / CGFloat(total))
                    Rectangle().fill(CategoryStyle.color(seg.0).gradient).frame(width: w)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

// MARK: - 卡片

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

// MARK: - 空狀態

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 小工具

enum Finder {
    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    static func copyPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }
    static func showTrash() { NSWorkspace.shared.open(Paths.trash) }
    static func emptyTrash() {
        let src = "tell application \"Finder\" to empty trash"
        NSAppleScript(source: src)?.executeAndReturnError(nil)
    }
}

struct PathText: View {
    let url: URL
    var body: some View {
        Text(Paths.abbreviated(url.path))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(url.path)
    }
}

/// 檔案項目的右鍵選單
struct FileContextMenu: ViewModifier {
    let url: URL
    func body(content: Content) -> some View {
        content.contextMenu {
            Button(L.revealInFinder.s) { Finder.reveal(url) }
            Button(L.copyPath.s) { Finder.copyPath(url) }
        }
    }
}
extension View {
    func fileContextMenu(_ url: URL) -> some View { modifier(FileContextMenu(url: url)) }
}
