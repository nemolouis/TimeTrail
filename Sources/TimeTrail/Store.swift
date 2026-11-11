import SwiftUI
import AppKit
import UserNotifications
import UniformTypeIdentifiers

// MARK: - 数据存储（本地 JSON）

@MainActor
final class Store: ObservableObject {
    /// 只有数据真正变化时才通知界面刷新并保存，防止"写入相同值 → 刷新 → 再写入"的循环
    private var storage: AppData
    var data: AppData {
        get { storage }
        set {
            guard newValue != storage else { return }
            objectWillChange.send()
            storage = newValue
            scheduleSave()
        }
    }
    let fileURL: URL
    private var saveTask: Task<Void, Never>?
    private var notifiedCountdowns = Set<UUID>()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    static let decoder = JSONDecoder()

    init(fileURL custom: URL? = nil) {
        if let custom {
            fileURL = custom
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TimeTrail", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("data.json")
        }
        if let raw = try? Data(contentsOf: fileURL), let decoded = try? Store.decoder.decode(AppData.self, from: raw) {
            storage = decoded
        } else {
            storage = AppData.sample()
        }
        saveNow()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            let raw = try Store.encoder.encode(data)
            try raw.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("TimeTrail save failed: \(error)")
        }
    }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "zh_CN")
        c.firstWeekday = data.settings.weekStartsMonday ? 2 : 1
        return c
    }

    // MARK: 查询

    func type(_ id: UUID?) -> ActivityType? {
        guard let id else { return nil }
        return data.types.first { $0.id == id }
    }
    func name(_ id: UUID) -> String { type(id)?.name ?? "未知" }
    func color(_ id: UUID) -> Color { Color(hex: type(id)?.colorHex ?? "#999999") }
    func tagName(_ id: UUID) -> String? { data.tags.first { $0.id == id }?.name }

    var groups: [ActivityType] { data.types.filter(\.isGroup) }
    var leafTypes: [ActivityType] { data.types.filter { !$0.isGroup } }
    var visibleTypes: [ActivityType] { leafTypes.filter { !$0.archived } }
    func children(of g: UUID) -> [ActivityType] { data.types.filter { $0.parentId == g && !$0.isGroup } }
    func isLoose(_ t: ActivityType) -> Bool { t.parentId == nil || type(t.parentId)?.isGroup != true }

    struct TypeSection: Identifiable {
        let id: String
        let title: String
        let types: [ActivityType]
    }
    var typeSections: [TypeSection] {
        var out: [TypeSection] = []
        let loose = visibleTypes.filter(isLoose)
        if !loose.isEmpty { out.append(TypeSection(id: "_loose", title: "类型", types: loose)) }
        for g in groups {
            let c = children(of: g.id).filter { !$0.archived }
            if !c.isEmpty { out.append(TypeSection(id: g.id.uuidString, title: g.name, types: c)) }
        }
        return out
    }

    var filterChoices: [Choice] {
        groups.map { Choice(id: $0.id, name: "【\($0.name)】") } + visibleTypes.map { Choice(id: $0.id, name: $0.name) }
    }
    var typeChoices: [Choice] { data.types.filter { !$0.archived }.map { Choice(id: $0.id, name: $0.isGroup ? "【\($0.name)】" : $0.name) } }
    var tagChoices: [Choice] { data.tags.map { Choice(id: $0.id, name: $0.name) } }

    var active: [Activity] { data.activities.filter(\.isActive).sorted { $0.start < $1.start } }

    var todayPomodoros: Int {
        let r = calendar.dateInterval(of: .day, for: Date())!
        return data.activities.filter { $0.isPomodoro && $0.state == .stopped && r.contains($0.start) && $0.duration() >= 60 }.count
    }

    func usage(ofType id: UUID) -> Int { data.activities.filter { $0.typeId == id }.count }
    func usage(ofTag id: UUID) -> Int { data.activities.filter { $0.tagIds.contains(id) }.count }

    func intersections(of a: Activity) -> [Activity] {
        let now = Date()
        return data.activities.filter { o in
            o.id != a.id && o.spans.contains { s in
                a.spans.contains { t in s.from < (t.to ?? now) && t.from < (s.to ?? now) }
            }
        }
    }

    func draftActivity() -> Activity {
        let now = Date()
        let tid = visibleTypes.first?.id ?? UUID()
        return Activity(typeId: tid, spans: [TimeSpan(from: now.addingTimeInterval(-3600), to: now)], state: .stopped)
    }

    // MARK: 计时操作

    @discardableResult
    func start(_ typeId: UUID, countdown: TimeInterval? = nil, pomodoro: Bool = false) -> UUID {
        let now = Date()
        var acts = data.activities
        if !data.settings.allowSimultaneous {
            for i in acts.indices where acts[i].isActive { Store.close(&acts[i], now) }
        }
        var a = Activity(typeId: typeId, spans: [TimeSpan(from: now)])
        a.countdown = countdown
        a.isPomodoro = pomodoro
        acts.append(a)
        data.activities = acts
        return a.id
    }

    private static func close(_ a: inout Activity, _ now: Date) {
        if let i = a.spans.lastIndex(where: { $0.to == nil }) { a.spans[i].to = now }
        a.state = .stopped
    }

    func pause(_ id: UUID) {
        mutate(id) { a in
            if let i = a.spans.lastIndex(where: { $0.to == nil }) { a.spans[i].to = Date() }
            a.state = .paused
        }
    }

    func resume(_ id: UUID) {
        let now = Date()
        var acts = data.activities
        if !data.settings.allowSimultaneous {
            for i in acts.indices where acts[i].isActive && acts[i].id != id { Store.close(&acts[i], now) }
        }
        if let i = acts.firstIndex(where: { $0.id == id }) {
            acts[i].spans.append(TimeSpan(from: now))
            acts[i].state = .running
        }
        data.activities = acts
    }

    func stop(_ id: UUID) { mutate(id) { Store.close(&$0, Date()) } }

    func addTime(_ id: UUID, minutes: Double) {
        mutate(id) { $0.countdown = ($0.countdown ?? 0) + minutes * 60 }
        notifiedCountdowns.remove(id)
    }

    func delete(_ id: UUID) { data.activities.removeAll { $0.id == id } }

    func upsert(_ a: Activity) {
        if let i = data.activities.firstIndex(where: { $0.id == a.id }) { data.activities[i] = a } else { data.activities.append(a) }
    }

    private func mutate(_ id: UUID, _ f: (inout Activity) -> Void) {
        if let i = data.activities.firstIndex(where: { $0.id == id }) { f(&data.activities[i]) }
    }

    func checkCountdowns(now: Date) {
        for a in data.activities where a.state == .running {
            guard let cd = a.countdown, !notifiedCountdowns.contains(a.id), a.duration(now: now) >= cd else { continue }
            notifiedCountdowns.insert(a.id)
            Notifier.send("倒计时结束", "\(name(a.typeId)) 已进行 \(fmtHM(cd))")
        }
    }

    // MARK: 类型 / 标签 / 字段 / 目标 管理

    func upsertType(_ t: ActivityType) {
        if let i = data.types.firstIndex(where: { $0.id == t.id }) { data.types[i] = t } else { data.types.append(t) }
    }
    func deleteType(_ id: UUID) {
        var types = data.types.filter { $0.id != id }
        for i in types.indices where types[i].parentId == id { types[i].parentId = nil }
        data.types = types
    }
    func addTag(_ name: String) { data.tags.append(TagItem(name: name)) }
    func deleteTag(_ id: UUID) {
        var d = data
        d.tags.removeAll { $0.id == id }
        for i in d.activities.indices { d.activities[i].tagIds.removeAll { $0 == id } }
        for i in d.goals.indices { d.goals[i].tagIds.removeAll { $0 == id } }
        data = d
    }
    func upsertField(_ f: CustomField) {
        if let i = data.fields.firstIndex(where: { $0.id == f.id }) { data.fields[i] = f } else { data.fields.append(f) }
    }
    func deleteField(_ id: UUID) { data.fields.removeAll { $0.id == id } }
    func upsertGoal(_ g: Goal) {
        if let i = data.goals.firstIndex(where: { $0.id == g.id }) { data.goals[i] = g } else { data.goals.append(g) }
    }
    func deleteGoal(_ id: UUID) { data.goals.removeAll { $0.id == id } }

    // MARK: 演示数据

    func generateDemo(days: Int = 14) {
        let cal = calendar
        var acts = data.activities
        func tid(_ n: String) -> UUID? { data.types.first { $0.name == n && !$0.isGroup }?.id }
        let project = data.fields.first { $0.name == "项目" }
        let pages = data.fields.first { $0.name == "页数" }
        let focus = data.tags.first { $0.name == "专注" }?.id
        let meeting = data.tags.first { $0.name == "会议" }?.id
        let today = cal.startOfDay(for: Date())
        for back in 1...days {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3600 + Double(Int.random(in: -10...10)) * 60) }
            var plan: [(String, Double, Double)] = [
                ("睡眠", 0, 7.5), ("吃饭", 8, 8.4), ("工作", 9.5, 12), ("吃饭", 12, 12.7),
                ("工作", 13.5, 18), ("通勤", 18.2, 18.8),
            ]
            if back % 2 == 0 { plan.append(("运动", 19.2, 20.1)) }
            if back % 3 != 0 { plan.append(("阅读", 21, 22)) } else { plan.append(("学习", 20.3, 22.2)) }
            plan.append(("娱乐", 22.4, back % 4 == 0 ? 24.8 : 23.5))
            for (n, s, e) in plan {
                guard let t = tid(n) else { continue }
                var a = Activity(typeId: t, spans: [TimeSpan(from: at(s), to: at(e))], state: .stopped)
                if n == "工作" {
                    if let p = project { a.fields[p.id] = p.options.randomElement() }
                    if let tag = Bool.random() ? focus : meeting { a.tagIds = [tag] }
                }
                if n == "阅读", let p = pages { a.fields[p.id] = String(Int.random(in: 10...60)) }
                acts.append(a)
            }
        }
        data.activities = acts
    }
}

// MARK: - 统计

struct Filter: Hashable {
    var types: Set<UUID> = []
    var tags: Set<UUID> = []
}

struct TypeSlice: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    var seconds: Double
    var count: Int
}

struct DayEntry: Identifiable {
    let id = UUID()
    let day: Date
    let name: String
    let seconds: Double
}

struct HourBin: Identifiable {
    let id: Int
    let seconds: Double
}

struct FieldStat: Identifiable {
    struct Line: Identifiable { let id = UUID(); let label: String; let value: String }
    let id: UUID
    let field: CustomField
    let lines: [Line]
}

extension Store {
    func matches(_ a: Activity, _ f: Filter) -> Bool {
        if !f.types.isEmpty {
            let parent = type(a.typeId)?.parentId
            let hit = f.types.contains(a.typeId) || (parent.map { f.types.contains($0) } ?? false)
            if !hit { return false }
        }
        if !f.tags.isEmpty && Set(a.tagIds).isDisjoint(with: f.tags) { return false }
        return true
    }

    func key(for typeId: UUID, byGroup: Bool) -> UUID {
        if byGroup, let p = type(typeId)?.parentId, type(p)?.isGroup == true { return p }
        return typeId
    }

    func slices(_ r: DateInterval, _ f: Filter, byGroup: Bool = false, now: Date = Date()) -> [TypeSlice] {
        var dict: [UUID: TypeSlice] = [:]
        for a in data.activities where matches(a, f) {
            let d = a.duration(in: r, now: now)
            guard d > 0 else { continue }
            let k = key(for: a.typeId, byGroup: byGroup)
            dict[k, default: TypeSlice(id: k, name: name(k), color: color(k), seconds: 0, count: 0)].seconds += d
            dict[k]!.count += 1
        }
        return dict.values.sorted { $0.seconds > $1.seconds }
    }

    func daily(_ r: DateInterval, _ f: Filter, byGroup: Bool, now: Date = Date()) -> [DayEntry] {
        let cal = calendar
        let acts = data.activities.filter { matches($0, f) && $0.duration(in: r, now: now) > 0 }
        var out: [DayEntry] = []
        var day = cal.startOfDay(for: r.start)
        while day < r.end {
            let next = cal.date(byAdding: .day, value: 1, to: day)!
            let di = DateInterval(start: max(day, r.start), end: min(next, r.end))
            var dict: [UUID: Double] = [:]
            for a in acts {
                let d = a.duration(in: di, now: now)
                if d > 0 { dict[key(for: a.typeId, byGroup: byGroup), default: 0] += d }
            }
            for (k, v) in dict { out.append(DayEntry(day: day, name: name(k), seconds: v)) }
            day = next
        }
        return out
    }

    func hourly(_ r: DateInterval, _ f: Filter, now: Date = Date()) -> [HourBin] {
        let cal = calendar
        var h = Array(repeating: 0.0, count: 24)
        for a in data.activities where matches(a, f) {
            for s in a.spans {
                var t = max(s.from, r.start)
                let e = min(s.to ?? now, r.end)
                while t < e {
                    let hourEnd = cal.dateInterval(of: .hour, for: t)!.end
                    let segEnd = min(hourEnd, e)
                    h[cal.component(.hour, from: t)] += segEnd.timeIntervalSince(t)
                    t = segEnd
                }
            }
        }
        return h.enumerated().map { HourBin(id: $0.offset, seconds: $0.element) }
    }

    func tagSlices(_ r: DateInterval, _ f: Filter, now: Date = Date()) -> [TypeSlice] {
        let noneId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        var dict: [UUID: TypeSlice] = [:]
        for a in data.activities where matches(a, f) {
            let d = a.duration(in: r, now: now)
            guard d > 0 else { continue }
            let ids = a.tagIds.isEmpty ? [noneId] : a.tagIds
            for t in ids {
                let n = t == noneId ? "无标签" : (tagName(t) ?? "已删除")
                dict[t, default: TypeSlice(id: t, name: n, color: t == noneId ? .gray : .accentColor, seconds: 0, count: 0)].seconds += d
                dict[t]!.count += 1
            }
        }
        return dict.values.sorted { $0.seconds > $1.seconds }
    }

    func fieldStats(_ r: DateInterval, _ f: Filter, now: Date = Date()) -> [FieldStat] {
        let acts = data.activities.filter { matches($0, f) && $0.duration(in: r, now: now) > 0 }
        return data.fields.map { fld in
            let rel = acts.filter { fld.applies(to: $0.typeId) }
            var lines: [FieldStat.Line] = []
            switch fld.kind {
            case .number:
                let vals = rel.compactMap { Double($0.fields[fld.id] ?? "") }
                let sum = vals.reduce(0, +)
                lines = [
                    .init(label: "合计", value: fmtNum(sum)),
                    .init(label: "平均", value: vals.isEmpty ? "-" : fmtNum(sum / Double(vals.count))),
                    .init(label: "已填写记录", value: "\(vals.count) / \(rel.count)"),
                ]
            case .list:
                var d: [String: (Double, Int)] = [:]
                for a in rel {
                    let v = a.fields[fld.id] ?? "未填写"
                    d[v, default: (0, 0)].0 += a.duration(in: r, now: now)
                    d[v]!.1 += 1
                }
                lines = d.sorted { $0.value.0 > $1.value.0 }.map { .init(label: $0.key, value: "\(fmtHM($0.value.0)) · \($0.value.1) 次") }
            case .amountPerHour:
                let rate = Double(fld.defaultValue) ?? 0
                var total = 0.0, secs = 0.0
                for a in rel {
                    let s = a.duration(in: r, now: now)
                    secs += s
                    total += s / 3600 * (Double(a.fields[fld.id] ?? "") ?? rate)
                }
                lines = [.init(label: "计费时长", value: fmtHM(secs)), .init(label: "金额", value: fmtNum(total))]
            case .amountPerRecord:
                let rate = Double(fld.defaultValue) ?? 0
                let total = rel.reduce(0.0) { $0 + (Double($1.fields[fld.id] ?? "") ?? rate) }
                lines = [.init(label: "记录数", value: "\(rel.count)"), .init(label: "金额", value: fmtNum(total))]
            case .text:
                let filled = rel.filter { !($0.fields[fld.id] ?? "").isEmpty }.count
                lines = [.init(label: "已填写记录", value: "\(filled) / \(rel.count)")]
            }
            return FieldStat(id: fld.id, field: fld, lines: lines)
        }
    }

    // MARK: 目标进度

    func goalRange(_ g: Goal, at date: Date) -> DateInterval {
        let cal = calendar
        switch g.period {
        case .day: return cal.dateInterval(of: .day, for: date)!
        case .week: return cal.dateInterval(of: .weekOfYear, for: date)!
        case .month: return cal.dateInterval(of: .month, for: date)!
        case .year: return cal.dateInterval(of: .year, for: date)!
        case .total: return DateInterval(start: .distantPast, end: .distantFuture)
        }
    }

    /// 时长目标返回分钟，次数目标返回次数
    func goalValue(_ g: Goal, in r: DateInterval, now: Date = Date()) -> Double {
        let f = Filter(types: Set(g.typeIds), tags: Set(g.tagIds))
        let acts = data.activities.filter { matches($0, f) }
        switch g.basis {
        case .duration: return acts.reduce(0) { $0 + $1.duration(in: r, now: now) } / 60
        case .occurrence: return Double(acts.filter { r.contains($0.start) }.count)
        }
    }

    func goalTarget(_ g: Goal) -> Double { g.basis == .duration ? g.targetMinutes : Double(g.targetCount) }

    func goalValueText(_ g: Goal, _ v: Double) -> String {
        g.basis == .duration ? fmtHM(v * 60) : "\(Int(v.rounded())) 次"
    }

    func goalDescription(_ g: Goal) -> String {
        let dir = g.direction == .reach ? "至少" : "不超过"
        let names = g.typeIds.compactMap { type($0)?.name }
        let scope = names.isEmpty ? "全部类型" : names.joined(separator: "、")
        return "\(g.period.label)\(dir) \(goalValueText(g, goalTarget(g))) · \(scope)"
    }
}

// MARK: - 番茄钟

@MainActor
final class PomodoroEngine: ObservableObject {
    enum Phase: String {
        case idle, work, shortBreak, longBreak
        var title: String {
            switch self { case .idle: "准备就绪"; case .work: "专注中"; case .shortBreak: "短休息"; case .longBreak: "长休息" }
        }
        var color: Color {
            switch self { case .idle: .secondary; case .work: .red; case .shortBreak: .green; case .longBreak: .teal }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var phaseEnd: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var completedInSet = 0
    @Published private(set) var suggestedNext: Phase = .work
    private var activityId: UUID?
    private unowned let store: Store

    init(store: Store) { self.store = store }

    var cfg: PomodoroConfig { store.data.pomodoro }
    var isPaused: Bool { pausedRemaining != nil }
    var displayPhase: Phase { phase == .idle ? suggestedNext : phase }

    func length(_ p: Phase) -> TimeInterval {
        switch p {
        case .work, .idle: cfg.workMinutes * 60
        case .shortBreak: cfg.shortBreakMinutes * 60
        case .longBreak: cfg.longBreakMinutes * 60
        }
    }

    func remaining(now: Date) -> TimeInterval {
        if let p = pausedRemaining { return p }
        if let e = phaseEnd { return max(0, e.timeIntervalSince(now)) }
        return length(suggestedNext)
    }

    func begin(_ p: Phase) {
        endActivity()
        phase = p
        pausedRemaining = nil
        phaseEnd = Date().addingTimeInterval(length(p))
        let typeId = p == .work ? cfg.workTypeId : cfg.breakTypeId
        if let t = typeId, store.type(t) != nil { activityId = store.start(t, pomodoro: p == .work) }
    }

    func pause() {
        guard phase != .idle, let e = phaseEnd else { return }
        pausedRemaining = max(0, e.timeIntervalSinceNow)
        phaseEnd = nil
        if let id = activityId { store.pause(id) }
    }

    func resume() {
        guard let r = pausedRemaining else { return }
        pausedRemaining = nil
        phaseEnd = Date().addingTimeInterval(r)
        if let id = activityId { store.resume(id) }
    }

    func skip() { finish(notify: false) }

    func abandon() {
        endActivity()
        phase = .idle
        phaseEnd = nil
        pausedRemaining = nil
        suggestedNext = .work
    }

    func tick(now: Date) {
        if let e = phaseEnd, now >= e { finish(notify: true) }
    }

    private func endActivity() {
        if let id = activityId { store.stop(id) }
        activityId = nil
    }

    private func finish(notify: Bool) {
        let finished = phase
        guard finished != .idle else { return }
        endActivity()
        if finished == .work {
            completedInSet += 1
            suggestedNext = completedInSet >= cfg.cyclesBeforeLongBreak ? .longBreak : .shortBreak
            if notify { Notifier.send("番茄完成 🍅", "休息一下吧", sound: cfg.sound) }
        } else {
            if finished == .longBreak { completedInSet = 0 }
            suggestedNext = .work
            if notify { Notifier.send("休息结束", "开始下一个番茄吧", sound: cfg.sound) }
        }
        phase = .idle
        phaseEnd = nil
        pausedRemaining = nil
        if cfg.autoStartNext { begin(suggestedNext) }
    }
}

// MARK: - 每秒时钟（只驱动需要实时刷新的视图）

@MainActor
final class Ticker: ObservableObject {
    @Published var now = Date()
    private var timer: Timer?

    init(store: Store, pomodoro: PomodoroEngine) {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self, weak store, weak pomodoro] _ in
            MainActor.assumeIsolated {
                let n = Date()
                self?.now = n
                store?.checkCountdowns(now: n)
                pomodoro?.tick(now: n)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// MARK: - 通知

enum Notifier {
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func send(_ title: String, _ body: String, sound: Bool = true) {
        if sound { NSSound(named: "Glass")?.play() }
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

// MARK: - 导入导出

enum Exporter {
    @MainActor
    static func csv(_ store: Store) -> String {
        let fields = store.data.fields
        let withGroup = store.data.settings.csvGroupColumn
        var header = ["类型"]
        if withGroup { header.append("分组") }
        header += ["开始", "结束", "时长(小时)", "时长", "备注", "标签"] + fields.map(\.name)
        var rows = [header]
        let now = Date()
        for a in store.data.activities.sorted(by: { $0.start < $1.start }) {
            var r = [store.name(a.typeId)]
            if withGroup { r.append(store.type(store.type(a.typeId)?.parentId)?.name ?? "") }
            let d = a.duration(now: now)
            r += [
                a.start.fmt("yyyy-MM-dd HH:mm:ss"),
                a.end?.fmt("yyyy-MM-dd HH:mm:ss") ?? "",
                String(format: "%.2f", d / 3600),
                fmtClock(d),
                a.comment,
                a.tagIds.compactMap(store.tagName).joined(separator: ";"),
            ]
            r += fields.map { a.fields[$0.id] ?? "" }
            rows.append(r)
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
    }

    static func escape(_ s: String) -> String {
        s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    @MainActor
    static func save(_ content: Data, name: String, type: UTType) {
        let p = NSSavePanel()
        p.nameFieldStringValue = name
        p.allowedContentTypes = [type]
        if p.runModal() == .OK, let u = p.url { try? content.write(to: u) }
    }

    @MainActor
    static func openJSON() -> Data? {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return nil }
        return try? Data(contentsOf: u)
    }
}
