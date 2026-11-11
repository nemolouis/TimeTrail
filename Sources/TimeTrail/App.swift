import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if Notifier.available {
            let c = UNUserNotificationCenter.current()
            c.delegate = self
            c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
enum Shared {
    static let store = Store()
    static let pomodoro = PomodoroEngine(store: store)
    static let ticker = Ticker(store: store, pomodoro: pomodoro)
}

@main
struct TimeTrailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 单例：即使 App 结构体被多次创建，也只有一个 Store / 计时器。
    // ticker 不作为 App 的观察对象，避免整个 App 每秒重算 body。
    @ObservedObject private var store = Shared.store
    private let pomodoro = Shared.pomodoro
    private let ticker = Shared.ticker

    var body: some Scene {
        WindowGroup("时迹", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .environmentObject(ticker)
                .frame(minWidth: 960, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .frame(width: 540, height: 480)
        }

        MenuBarExtra(isInserted: Binding(get: { store.data.settings.showMenuBar },
                                         set: { v in
                                             // SwiftUI 会在每次刷新时回写这个绑定，只在值变化时写入，避免刷新死循环
                                             if store.data.settings.showMenuBar != v { store.data.settings.showMenuBar = v }
                                         })) {
            MenuBarPanel()
                .environmentObject(store)
                .environmentObject(pomodoro)
                .environmentObject(ticker)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
                .environmentObject(ticker)
        }
        .menuBarExtraStyle(.window)
    }
}

enum Page: String, CaseIterable, Identifiable, Hashable {
    case activities, history, stats, goals, pomodoro, manage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .activities: "活动"; case .history: "记录"; case .stats: "统计"
        case .goals: "目标"; case .pomodoro: "番茄钟"; case .manage: "管理"
        }
    }
    var icon: String {
        switch self {
        case .activities: "play.circle"; case .history: "list.bullet.rectangle"; case .stats: "chart.pie"
        case .goals: "target"; case .pomodoro: "timer"; case .manage: "square.grid.2x2"
        }
    }
}

struct ContentView: View {
    @State private var page: Page? = .activities
    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(Page.allCases) { p in
                    Label(p.title, systemImage: p.icon).tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            switch page ?? .activities {
            case .activities: ActivitiesView()
            case .history: HistoryView()
            case .stats: StatsView()
            case .goals: GoalsView()
            case .pomodoro: PomodoroView()
            case .manage: ManageView()
            }
        }
    }
}

// MARK: - 菜单栏

struct MenuBarLabel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var ticker: Ticker
    var body: some View {
        if let a = store.active.first(where: { $0.state == .running }) {
            Text("⏱ \(store.name(a.typeId)) \(fmtClock(a.duration(now: ticker.now)))")
        } else {
            Image(systemName: "clock")
        }
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.active.isEmpty {
                Text("没有进行中的活动").foregroundStyle(.secondary)
            }
            ForEach(store.active) { a in
                HStack {
                    TypeIcon(type: store.type(a.typeId), size: 22)
                    Text(store.name(a.typeId))
                    Spacer()
                    LiveDuration(activity: a)
                    Button {
                        if a.state == .running { store.pause(a.id) } else { store.resume(a.id) }
                    } label: { Image(systemName: a.state == .running ? "pause.fill" : "play.fill") }
                        .buttonStyle(.borderless)
                    Button { store.stop(a.id) } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.borderless)
                }
            }
            Divider()
            Text("快速开始").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(store.visibleTypes) { t in
                    Button { store.start(t.id) } label: {
                        VStack(spacing: 3) {
                            TypeIcon(type: t, size: 28)
                            Text(t.name).font(.caption2).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Button("打开主窗口") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
