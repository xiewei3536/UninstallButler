import Foundation
import UninstallCore

/// 三語字串（en / 繁中 / 簡中），支援 App 內即時切換
struct Tr {
    let en: String, hant: String, hans: String
    init(_ en: String, _ hant: String, _ hans: String) {
        self.en = en; self.hant = hant; self.hans = hans
    }
    var s: String {
        switch L.resolved {
        case .en: return en
        case .hant: return hant
        case .hans: return hans
        }
    }
    func f(_ args: CVarArg...) -> String { String(format: s, arguments: args) }
}

enum ResolvedLang { case en, hant, hans }

enum L {
    static var resolved: ResolvedLang {
        switch Prefs.shared.language {
        case "en": return .en
        case "zh-Hant": return .hant
        case "zh-Hans": return .hans
        default:
            for id in Locale.preferredLanguages {
                let l = id.lowercased()
                if l.hasPrefix("zh") {
                    if l.contains("hant") || l.contains("-tw") || l.contains("-hk") || l.contains("-mo") { return .hant }
                    return .hans
                }
                if l.hasPrefix("en") { return .en }
            }
            return .en
        }
    }

    static var localeIdentifier: String {
        switch resolved {
        case .en: return "en_US"
        case .hant: return "zh_TW"
        case .hans: return "zh_CN"
        }
    }

    // MARK: 一般
    static let appName = Tr("Uninstall Butler", "解除安裝管家", "卸载管家")
    static let ok = Tr("OK", "好", "好")
    static let cancel = Tr("Cancel", "取消", "取消")
    static let done = Tr("Done", "完成", "完成")
    static let close = Tr("Close", "關閉", "关闭")
    static let back = Tr("Back", "返回", "返回")
    static let refresh = Tr("Refresh", "重新掃描", "重新扫描")
    static let revealInFinder = Tr("Show in Finder", "在 Finder 中顯示", "在访达中显示")
    static let copyPath = Tr("Copy Path", "拷貝路徑", "拷贝路径")
    static let selectAll = Tr("Select All", "全選", "全选")
    static let deselectAll = Tr("Deselect All", "全部取消", "全部取消")
    static let items = Tr("%d items", "%d 個項目", "%d 个项目")
    static let item1 = Tr("1 item", "1 個項目", "1 个项目")
    static let searchApps = Tr("Search apps", "搜尋 App", "搜索 App")
    static let unknown = Tr("Unknown", "未知", "未知")
    static let never = Tr("Never", "從未", "从未")
    static let today = Tr("Today", "今天", "今天")
    static let yesterday = Tr("Yesterday", "昨天", "昨天")
    static let daysAgo = Tr("%d days ago", "%d 天前", "%d 天前")
    static let monthsAgo = Tr("%d months ago", "%d 個月前", "%d 个月前")
    static let yearsAgo = Tr("%d years ago", "%d 年前", "%d 年前")
    static let calculating = Tr("Calculating…", "計算中…", "计算中…")

    // MARK: 側邊欄
    static let sectionApps = Tr("Applications", "應用程式", "应用程序")
    static let sectionTools = Tr("Cleanup", "清理", "清理")
    static let listAll = Tr("All Apps", "所有 App", "所有 App")
    static let listUnused = Tr("Rarely Used", "很久沒用", "很久没用")
    static let listLarge = Tr("Large Apps", "大型 App", "大型 App")
    static let listIntelOnly = Tr("Intel-only", "僅 Intel 版", "仅 Intel 版")
    static let listAppStore = Tr("App Store", "App Store", "App Store")
    static let listRunning = Tr("Running", "執行中", "运行中")
    static let listLeftovers = Tr("Leftovers", "殘留檔案", "残留文件")
    static let listLeftoversSub = Tr("Files from apps that are gone", "已刪除 App 留下的檔案", "已删除 App 留下的文件")
    static let fdaGranted = Tr("Full Disk Access on", "已授權完整磁碟取用", "已授权完全磁盘访问")
    static let fdaMissing = Tr("Grant Full Disk Access", "授權完整磁碟取用", "授权完全磁盘访问")
    static let fdaTip = Tr("Without Full Disk Access, a few protected folders (Cookies, some containers) can't be checked.",
                           "未授權時，少數受保護的資料夾（Cookies、部分沙盒容器）無法檢查。",
                           "未授权时，少数受保护的文件夹（Cookies、部分沙盒容器）无法检查。")
    static let settings = Tr("Settings", "設定", "设置")

    // MARK: App 清單
    static let scanningApps = Tr("Scanning applications…", "正在掃描應用程式…", "正在扫描应用程序…")
    static let appsCount = Tr("%d apps · %@", "%d 個 App · %@", "%d 个 App · %@")
    static let noAppsMatch = Tr("No apps match", "沒有符合的 App", "没有符合的 App")
    static let sortBy = Tr("Sort", "排序", "排序")
    static let sortName = Tr("Name", "名稱", "名称")
    static let sortSize = Tr("Size", "大小", "大小")
    static let sortLastUsed = Tr("Last Used", "最後使用", "最后使用")
    static let sortInstalled = Tr("Date Added", "加入日期", "加入日期")
    static let badgeRunning = Tr("Running", "執行中", "运行中")
    static let badgeUniversal = Tr("Universal", "通用", "通用")
    static let badgeIntel = Tr("Intel", "Intel", "Intel")
    static let badgeAppleSilicon = Tr("Apple Silicon", "Apple 晶片", "Apple 芯片")
    static let badgeAppStore = Tr("App Store", "App Store", "App Store")
    static let badgeSandboxed = Tr("Sandboxed", "沙盒", "沙盒")
    static let badgeApple = Tr("Apple", "Apple", "Apple")
    static let lastUsedFmt = Tr("Last used %@", "最後使用：%@", "最后使用：%@")
    static let neverUsedHere = Tr("Not opened recently", "近期未開啟", "近期未打开")

    // MARK: 詳細
    static let emptyTitle = Tr("Pick an app to see everything it left behind",
                               "選擇一個 App，看看它在系統各處留下了什麼",
                               "选择一个 App，看看它在系统各处留下了什么")
    static let emptySub = Tr("Preferences, caches, support files, background services, receipts — all found and removed in one go.",
                             "偏好設定、快取、支援檔案、背景服務、安裝收據 —— 一次找齊、一次清乾淨。",
                             "偏好设置、缓存、支持文件、后台服务、安装收据 —— 一次找齐、一次清干净。")
    static let version = Tr("Version %@", "版本 %@", "版本 %@")
    static let bundleID = Tr("Bundle ID", "Bundle ID", "Bundle ID")
    static let location = Tr("Location", "位置", "位置")
    static let developer = Tr("Team ID", "Team ID", "Team ID")
    static let installedOn = Tr("Added %@", "加入於 %@", "加入于 %@")
    static let scanningResidue = Tr("Looking for related files…", "正在尋找相關檔案…", "正在查找相关文件…")
    static let foundSummary = Tr("%d related items · %@ total", "找到 %d 個相關項目 · 共 %@", "找到 %d 个相关项目 · 共 %@")
    static let selectedSummary = Tr("%d selected · %@", "已選 %d 項 · %@", "已选 %d 项 · %@")
    static let keepData = Tr("Keep settings & data", "保留設定與個人資料", "保留设置与个人数据")
    static let keepDataTip = Tr("Leaves preferences, support files and sandbox data in place, so a reinstall picks up where you left off.",
                                "保留偏好設定、支援檔案與沙盒資料，重新安裝時可以接著用。",
                                "保留偏好设置、支持文件与沙盒数据，重新安装时可以接着用。")
    static let uninstallBtn = Tr("Uninstall…", "解除安裝…", "卸载…")
    static let removeSelectedBtn = Tr("Remove Selected…", "移除所選…", "移除所选…")
    static let protectedApp = Tr("This app is protected by macOS and can't be removed.", "這個 App 受 macOS 保護，無法移除。", "这个 App 受 macOS 保护，无法移除。")
    static let runningNote = Tr("Running — it will be quit first.", "App 正在執行，會先為你結束它。", "App 正在运行，会先为你退出它。")
    static let multiTitle = Tr("%d apps selected", "已選擇 %d 個 App", "已选择 %d 个 App")
    static let multiSub = Tr("Their related files will be found and removed together.", "會一併找出並移除它們的相關檔案。", "会一并找出并移除它们的相关文件。")
    static let itemsShort = Tr("%d items", "%d 項", "%d 项")

    // MARK: 類別
    static func category(_ c: ResidueCategory) -> Tr {
        switch c {
        case .appBundle: return Tr("Application", "App 本體", "App 本体")
        case .container: return Tr("Sandbox Container", "沙盒容器", "沙盒容器")
        case .appSupport: return Tr("Application Support", "支援檔案", "支持文件")
        case .preferences: return Tr("Preferences", "偏好設定", "偏好设置")
        case .caches: return Tr("Caches", "快取", "缓存")
        case .savedState: return Tr("Saved Window State", "視窗狀態", "窗口状态")
        case .webData: return Tr("Web Data & Cookies", "網頁資料與 Cookies", "网页数据与 Cookies")
        case .logs: return Tr("Logs", "日誌", "日志")
        case .crashReports: return Tr("Crash Reports", "崩潰紀錄", "崩溃记录")
        case .launchAgents: return Tr("Login Agents", "登入時啟動的背景程式", "登录时启动的后台程序")
        case .launchDaemons: return Tr("System Daemons", "系統背景服務", "系统后台服务")
        case .privilegedHelper: return Tr("Privileged Helpers", "特權輔助工具", "特权辅助工具")
        case .receipts: return Tr("Install Receipts", "安裝收據", "安装收据")
        case .plugins: return Tr("Plug-ins & Extensions", "外掛與延伸功能", "插件与扩展")
        case .commandLine: return Tr("Command-line Shortcuts", "指令列捷徑", "命令行快捷方式")
        case .appScripts: return Tr("Application Scripts", "應用程式腳本", "应用程序脚本")
        case .recentDocuments: return Tr("Recent Documents List", "最近文件清單", "最近文件列表")
        case .groupContainer: return Tr("Shared Group Containers", "共用群組容器", "共享群组容器")
        case .temporary: return Tr("Temporary Files", "暫存檔", "临时文件")
        case .other: return Tr("Other", "其他", "其他")
        }
    }
    static func categoryHint(_ c: ResidueCategory) -> Tr {
        switch c {
        case .appBundle: return Tr("The app itself in your Applications folder", "應用程式資料夾裡的 App 本身", "应用程序文件夹里的 App 本身")
        case .container: return Tr("Documents and data the app kept inside its sandbox", "App 存放在沙盒內的文件與資料", "App 存放在沙盒内的文档与数据")
        case .appSupport: return Tr("Databases, plug-ins and other files the app created", "App 建立的資料庫、外掛與其他檔案", "App 创建的数据库、插件与其他文件")
        case .preferences: return Tr("Your settings for this app", "你對這個 App 的設定", "你对这个 App 的设置")
        case .caches: return Tr("Safe to delete — the app recreates them when needed", "可放心刪除，App 需要時會重建", "可放心删除，App 需要时会重建")
        case .savedState: return Tr("Window positions and unsaved state", "視窗位置與未儲存的狀態", "窗口位置与未保存的状态")
        case .webData: return Tr("Website storage and cookies used by the app", "App 使用的網站儲存空間與 Cookies", "App 使用的网站存储空间与 Cookies")
        case .logs: return Tr("Diagnostic logs", "診斷日誌", "诊断日志")
        case .crashReports: return Tr("Reports written when the app crashed", "App 崩潰時寫下的紀錄", "App 崩溃时写下的记录")
        case .launchAgents: return Tr("Runs in the background after you log in — will be stopped first", "登入後在背景執行，會先停止它", "登录后在后台运行，会先停止它")
        case .launchDaemons: return Tr("System-wide services — administrator password required", "全系統的服務，需要管理員密碼", "全系统的服务，需要管理员密码")
        case .privilegedHelper: return Tr("Tools that run with root privileges — administrator password required", "以 root 權限執行的工具，需要管理員密碼", "以 root 权限运行的工具，需要管理员密码")
        case .receipts: return Tr("Installer bookkeeping — administrator password required", "安裝程式的記錄，需要管理員密碼", "安装程序的记录，需要管理员密码")
        case .plugins: return Tr("Quick Look, Spotlight, audio and other plug-ins", "Quick Look、Spotlight、音訊等外掛", "快速查看、聚焦、音频等插件")
        case .commandLine: return Tr("Terminal commands that point into the app", "指向這個 App 的終端機指令", "指向这个 App 的终端命令")
        case .appScripts: return Tr("Scripts the app was allowed to run", "允許 App 執行的腳本", "允许 App 运行的脚本")
        case .recentDocuments: return Tr("The app's Open Recent menu contents", "App「最近使用」選單的內容", "App“最近使用”菜单的内容")
        case .groupContainer: return Tr("May be shared with other apps from the same developer — check before removing", "可能與同開發者的其他 App 共用，移除前請確認", "可能与同开发者的其他 App 共享，移除前请确认")
        case .temporary: return Tr("Per-user cache and temp folders", "使用者專屬的快取與暫存資料夾", "用户专属的缓存与临时文件夹")
        case .other: return Tr("Other related files", "其他相關檔案", "其他相关文件")
        }
    }

    // MARK: 警示
    static let cautionShared = Tr("Also used by: %@", "也被這些 App 使用：%@", "也被这些 App 使用：%@")
    static let cautionNameOnly = Tr("Matched by name only", "僅依名稱比對", "仅依名称匹配")
    static let cautionAdmin = Tr("Admin password", "需管理員密碼", "需管理员密码")
    static let matchedByID = Tr("Matched by bundle ID %@", "以 Bundle ID %@ 比對", "以 Bundle ID %@ 匹配")
    static let matchedByProgram = Tr("Launches a program inside the app", "會啟動 App 內的程式", "会启动 App 内的程序")
    static let matchedByLink = Tr("Links into the app", "連結指向 App 內", "链接指向 App 内")
    static let matchedByEntitlement = Tr("Declared by the app's signature", "App 簽章宣告", "App 签名声明")
    static let matchedByVendor = Tr("Inside the %@ folder", "在 %@ 資料夾內", "在 %@ 文件夹内")
    static let matchedByContainer = Tr("Container metadata points to this app", "容器中繼資料指向這個 App", "容器元数据指向这个 App")
    static let matchedByDeveloper = Tr("Developer component — this is the developer's only app here", "開發者共用元件（這是該開發者在此唯一的 App）", "开发者共用组件（这是该开发者在此唯一的 App）")
    static let cautionSameDeveloper = Tr("Same developer", "同開發者", "同开发者")

    // MARK: 確認
    static let confirmTitle = Tr("Uninstall %@?", "要解除安裝「%@」嗎？", "要卸载“%@”吗？")
    static let confirmTitleMulti = Tr("Uninstall %d apps?", "要解除安裝 %d 個 App 嗎？", "要卸载 %d 个 App 吗？")
    static let confirmLeftoversTitle = Tr("Remove %d leftover items?", "要移除 %d 個殘留項目嗎？", "要移除 %d 个残留项目吗？")
    static let confirmBody = Tr("%d items · %@ will be removed.", "將移除 %d 個項目，共 %@。", "将移除 %d 个项目，共 %@。")
    static let confirmTrash = Tr("Move to Trash (recoverable)", "移到垃圾桶（可復原）", "移到废纸篓（可恢复）")
    static let confirmPermanent = Tr("Delete immediately", "直接永久刪除", "直接永久删除")
    static let confirmAdminNote = Tr("%d items need your administrator password.", "其中 %d 項需要管理員密碼。", "其中 %d 项需要管理员密码。")
    static let confirmSharedNote = Tr("%d shared items are included — other apps may be affected.", "包含 %d 個共用項目，可能影響其他 App。", "包含 %d 个共享项目，可能影响其他 App。")
    static let confirmBtn = Tr("Uninstall", "解除安裝", "卸载")
    static let removeBtn = Tr("Remove", "移除", "移除")

    // MARK: 進行中 / 結果
    static let phaseQuitting = Tr("Quitting the app…", "正在結束 App…", "正在退出 App…")
    static let phaseRemoving = Tr("Removing files…", "正在移除檔案…", "正在移除文件…")
    static let phaseAdmin = Tr("Waiting for administrator password…", "等待輸入管理員密碼…", "等待输入管理员密码…")
    static let phaseFinishing = Tr("Finishing up…", "收尾中…", "收尾中…")
    static let resultAllGood = Tr("All clean", "清理完成", "清理完成")
    static let resultPartial = Tr("Mostly done", "大致完成", "大致完成")
    static let resultCancelled = Tr("Some items were skipped", "部分項目已略過", "部分项目已跳过")
    static let resultFreed = Tr("%@ freed · %d items removed", "釋放 %@ · 移除 %d 個項目", "释放 %@ · 移除 %d 个项目")
    static let resultFailedCount = Tr("%d items could not be removed", "%d 個項目無法移除", "%d 个项目无法移除")
    static let resultSkippedCount = Tr("%d items skipped (administrator password cancelled)", "%d 個項目已略過（未輸入管理員密碼）", "%d 个项目已跳过（未输入管理员密码）")
    static let resultDryRun = Tr("Dry run — nothing was actually removed", "模擬模式，沒有真的刪除任何檔案", "模拟模式，没有真的删除任何文件")
    static let resultInTrash = Tr("Everything is in the Trash — empty it to reclaim the space.", "所有項目都在垃圾桶裡，清空即可騰出空間。", "所有项目都在废纸篓里，清空即可腾出空间。")
    static let emptyTrash = Tr("Empty Trash", "清空垃圾桶", "清空废纸篓")
    static let openTrash = Tr("Show Trash", "顯示垃圾桶", "显示废纸篓")

    // MARK: 殘留清理
    static let leftoversTitle = Tr("Leftovers", "殘留檔案", "残留文件")
    static let leftoversIntro = Tr("Files named after apps that are no longer installed anywhere on this Mac.",
                                   "這些檔案以某個 App 的 ID 命名，但那個 App 已經不在這台 Mac 上了。",
                                   "这些文件以某个 App 的 ID 命名，但那个 App 已经不在这台 Mac 上了。")
    static let leftoversScanning = Tr("Checking your Library folders…", "正在檢查資料庫資料夾…", "正在检查资源库文件夹…")
    static let leftoversNone = Tr("No leftovers found — your Mac is clean.", "沒有找到殘留檔案，這台 Mac 很乾淨。", "没有找到残留文件，这台 Mac 很干净。")
    static let leftoversSummary = Tr("%d leftover items · %@", "%d 個殘留項目 · %@", "%d 个残留项目 · %@")
    static let confidenceHigh = Tr("Safe to remove", "可放心移除", "可放心移除")
    static let confidenceHighSub = Tr("No installed app claims these files.", "沒有任何已安裝的 App 認領這些檔案。", "没有任何已安装的 App 认领这些文件。")
    static let confidenceMedium = Tr("Check first", "請先確認", "请先确认")
    static let confidenceMediumSub = Tr("An app from the same developer is still installed; these might be shared components.",
                                        "同開發者的 App 仍安裝著，這些可能是共用元件。", "同开发者的 App 仍安装着，这些可能是共享组件。")
    static let relatedApps = Tr("Related: %@", "相關 App：%@", "相关 App：%@")
    static let modified = Tr("Modified %@", "修改於 %@", "修改于 %@")
    static let scanLeftovers = Tr("Scan for Leftovers", "掃描殘留檔案", "扫描残留文件")
    static let rescan = Tr("Scan Again", "重新掃描", "重新扫描")

    // MARK: 設定
    static let settingsTitle = Tr("Settings", "設定", "设置")
    static let rowLanguage = Tr("Language", "語言", "语言")
    static let langAuto = Tr("Follow System", "跟隨系統", "跟随系统")
    static let rowDeletion = Tr("When removing files", "移除檔案時", "移除文件时")
    static let rowDeletionSub = Tr("Moving to the Trash lets you undo. Space is reclaimed when you empty it.",
                                   "移到垃圾桶可以復原；清空垃圾桶後才會真正騰出空間。",
                                   "移到废纸篓可以恢复；清空废纸篓后才会真正腾出空间。")
    static let rowFolders = Tr("Application folders", "應用程式資料夾", "应用程序文件夹")
    static let rowFoldersSub = Tr("Where to look for apps. /Applications and ~/Applications are always included.",
                                  "掃描 App 的位置；/Applications 與 ~/Applications 一定會掃。",
                                  "扫描 App 的位置；/Applications 与 ~/Applications 一定会扫。")
    static let addFolder = Tr("Add Folder…", "加入資料夾…", "添加文件夹…")
    static let rowShowApple = Tr("Show Apple apps", "顯示 Apple 的 App", "显示 Apple 的 App")
    static let rowShowAppleSub = Tr("Apple apps in /Applications (Pages, Xcode…) can be uninstalled too", "/Applications 裡 Apple 的 App（Pages、Xcode…）也可以解除安裝", "/Applications 里 Apple 的 App（Pages、Xcode…）也可以卸载")
    static let rowUnusedDays = Tr("\"Rarely used\" means not opened for", "「很久沒用」的定義：超過", "“很久没用”的定义：超过")
    static let daysFmt = Tr("%d days", "%d 天", "%d 天")
    static let rowFDA = Tr("Full Disk Access", "完整磁碟取用", "完全磁盘访问")
    static let rowFDASub = Tr("Lets the butler check every folder, including Cookies and protected containers. Recommended.",
                              "讓管家能檢查所有資料夾，包含 Cookies 與受保護的容器。建議開啟。",
                              "让管家能检查所有文件夹，包含 Cookies 与受保护的容器。建议开启。")
    static let btnOpenPrivacy = Tr("Open System Settings", "打開系統設定", "打开系统设置")
    static let tabGeneral = Tr("General", "一般", "通用")
    static let tabAbout = Tr("About", "關於", "关于")
    static let aboutLine1 = Tr("A thorough, careful uninstaller for the Mac.", "細心又徹底的 Mac 解除安裝管家。", "细心又彻底的 Mac 卸载管家。")
    static let aboutLine2 = Tr("Universal binary — runs natively on Intel and Apple Silicon.", "通用二進位檔，在 Intel 與 Apple 晶片 Mac 上皆原生執行。", "通用二进制，在 Intel 与 Apple 芯片 Mac 上皆原生运行。")
    static let aboutLine3 = Tr("Nothing leaves your Mac. No accounts, no tracking.", "資料不會離開你的 Mac，沒有帳號、沒有追蹤。", "数据不会离开你的 Mac，没有账号、没有跟踪。")
    static let versionFmt = Tr("Version %@", "版本 %@", "版本 %@")
    static let showWelcome = Tr("Show Welcome Again", "重看歡迎畫面", "重看欢迎画面")

    // MARK: 歡迎
    static let welcomeTitle = Tr("Welcome to Uninstall Butler", "歡迎使用解除安裝管家", "欢迎使用卸载管家")
    static let welcomeSub = Tr("Dragging an app to the Trash leaves its files behind. The butler finds every one of them.",
                               "把 App 拖進垃圾桶，它的檔案其實還留在系統裡。管家會把它們全部找出來。",
                               "把 App 拖进废纸篓，它的文件其实还留在系统里。管家会把它们全部找出来。")
    static let welcome1Title = Tr("Pick an app", "選一個 App", "选一个 App")
    static let welcome1Sub = Tr("See its preferences, caches, background services and more — with sizes.", "看見它的偏好設定、快取、背景服務等等，還有各自的大小。", "看见它的偏好设置、缓存、后台服务等等，还有各自的大小。")
    static let welcome2Title = Tr("Review, then remove", "檢視後移除", "查看后移除")
    static let welcome2Sub = Tr("Everything is ticked by default; untick anything you'd rather keep. Items go to the Trash unless you say otherwise.", "預設全部勾選，想保留的取消勾選即可。除非你另有指定，項目都會進垃圾桶。", "默认全部勾选，想保留的取消勾选即可。除非你另有指定，项目都会进废纸篓。")
    static let welcome3Title = Tr("Clean up leftovers", "清理殘留", "清理残留")
    static let welcome3Sub = Tr("Find files from apps you deleted long ago.", "找出很久以前刪掉的 App 留下的檔案。", "找出很久以前删掉的 App 留下的文件。")
    static let welcomeFDA = Tr("For the most thorough scan, grant Full Disk Access.", "想掃得最徹底，請授權「完整磁碟取用」。", "想扫得最彻底，请授权“完全磁盘访问”。")
    static let welcomeStart = Tr("Get Started", "開始使用", "开始使用")

    // MARK: 更新
    static let menuCheckUpdates = Tr("Check for Updates…", "檢查更新…", "检查更新…")
    static let updateAvailable = Tr("Version %@ is available", "有新版本 %@ 可用", "有新版本 %@ 可用")
    static let updateAvailableBody = Tr("You have %@. Download the update from GitHub Releases and drag it into Applications to replace the current copy.",
                                        "目前是 %@。到 GitHub Releases 下載新版，拖進「應用程式」覆蓋即可。",
                                        "目前是 %@。到 GitHub Releases 下载新版，拖进“应用程序”覆盖即可。")
    static let updateDownload = Tr("Download", "前往下載", "前往下载")
    static let updateLater = Tr("Later", "稍後", "稍后")
    static let updateSkip = Tr("Skip This Version", "略過此版本", "跳过此版本")
    static let updateUpToDate = Tr("You're up to date", "已是最新版本", "已是最新版本")
    static let updateUpToDateBody = Tr("Uninstall Butler %@ is the latest version.", "解除安裝管家 %@ 已是最新版本。", "卸载管家 %@ 已是最新版本。")
    static let updateFailed = Tr("Couldn't check for updates", "無法檢查更新", "无法检查更新")

    // MARK: 選單
    static let menuAbout = Tr("About Uninstall Butler", "關於解除安裝管家", "关于卸载管家")
    static let menuSettings = Tr("Settings…", "設定…", "设置…")
    static let menuHide = Tr("Hide Uninstall Butler", "隱藏解除安裝管家", "隐藏卸载管家")
    static let menuHideOthers = Tr("Hide Others", "隱藏其他", "隐藏其他")
    static let menuShowAll = Tr("Show All", "顯示全部", "显示全部")
    static let menuQuit = Tr("Quit Uninstall Butler", "結束解除安裝管家", "退出卸载管家")
    static let menuFile = Tr("File", "檔案", "文件")
    static let menuClose = Tr("Close", "關閉", "关闭")
    static let menuEdit = Tr("Edit", "編輯", "编辑")
    static let menuUndo = Tr("Undo", "還原", "撤销")
    static let menuRedo = Tr("Redo", "重做", "重做")
    static let menuCut = Tr("Cut", "剪下", "剪切")
    static let menuCopy = Tr("Copy", "拷貝", "拷贝")
    static let menuPaste = Tr("Paste", "貼上", "粘贴")
    static let menuSelectAll = Tr("Select All", "全選", "全选")
    static let menuView = Tr("View", "顯示方式", "显示")
    static let menuLanguage = Tr("Language", "語言", "语言")
    static let menuWindow = Tr("Window", "視窗", "窗口")
    static let menuMinimize = Tr("Minimize", "縮到最小", "最小化")
    static let menuZoom = Tr("Zoom", "縮放", "缩放")
    static let menuHelp = Tr("Help", "輔助說明", "帮助")
    static let menuWelcome = Tr("Welcome Tour", "歡迎導覽", "欢迎导览")
    static let menuFDA = Tr("Full Disk Access…", "完整磁碟取用…", "完全磁盘访问…")
}

// MARK: - 格式化

enum Fmt {
    static func bytes(_ n: Int64?) -> String {
        guard let n else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: n)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return L.never.s }
        let days = Int(Date().timeIntervalSince(date) / 86400)
        if days <= 0 { return L.today.s }
        if days == 1 { return L.yesterday.s }
        if days < 45 { return L.daysAgo.f(days) }
        if days < 365 { return L.monthsAgo.f(max(1, days / 30)) }
        return L.yearsAgo.f(max(1, days / 365))
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: L.localeIdentifier)
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
