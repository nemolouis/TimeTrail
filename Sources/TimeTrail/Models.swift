import Foundation

// MARK: - 类型 / 分组

struct ActivityType: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var icon: String = "circle.fill"
    var colorHex: String = "#4C8BF5"
    var parentId: UUID? = nil      // 所属分组
    var isGroup = false
    var archived = false
}

struct TagItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

// MARK: - 自定义字段

enum FieldKind: String, Codable, CaseIterable, Identifiable {
    case text, number, list, amountPerHour, amountPerRecord
    var id: String { rawValue }
    var label: String {
        switch self {
        case .text: "文本"
        case .number: "数字"
        case .list: "选项列表"
        case .amountPerHour: "按小时计费"
        case .amountPerRecord: "按条计费"
        }
    }
}

struct CustomField: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var kind: FieldKind = .text
    var options: [String] = []
    var defaultValue: String = ""   // 计费类字段的默认单价
    var typeIds: [UUID] = []        // 为空表示适用于全部类型
    func applies(to typeId: UUID) -> Bool { typeIds.isEmpty || typeIds.contains(typeId) }
}

// MARK: - 记录

struct TimeSpan: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: Date
    var to: Date?

    func duration(now: Date) -> TimeInterval { max(0, (to ?? now).timeIntervalSince(from)) }
    func overlap(_ r: DateInterval, now: Date) -> TimeInterval {
        let s = max(from, r.start), e = min(to ?? now, r.end)
        return max(0, e.timeIntervalSince(s))
    }
}

enum ActivityState: String, Codable { case running, paused, stopped }

struct Activity: Identifiable, Codable, Hashable {
    var id = UUID()
    var typeId: UUID
    var spans: [TimeSpan]
    var state: ActivityState = .running
    var comment = ""
    var tagIds: [UUID] = []
    var fields: [UUID: String] = [:]
    var countdown: TimeInterval? = nil   // 倒计时目标（秒）
    var isPomodoro = false

    var start: Date { spans.map(\.from).min() ?? .distantPast }
    var end: Date? { state == .stopped ? spans.compactMap(\.to).max() : nil }
    var isActive: Bool { state != .stopped }
    func duration(now: Date = Date()) -> TimeInterval { spans.reduce(0) { $0 + $1.duration(now: now) } }
    func duration(in r: DateInterval, now: Date = Date()) -> TimeInterval { spans.reduce(0) { $0 + $1.overlap(r, now: now) } }
}

// MARK: - 目标

enum GoalBasis: String, Codable, CaseIterable { case duration, occurrence }
enum GoalDirection: String, Codable, CaseIterable { case reach, limit }
enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
    case day, week, month, year, total
    var id: String { rawValue }
    var label: String {
        switch self { case .day: "每天"; case .week: "每周"; case .month: "每月"; case .year: "每年"; case .total: "累计" }
    }
    var currentLabel: String {
        switch self { case .day: "今天"; case .week: "本周"; case .month: "本月"; case .year: "今年"; case .total: "累计" }
    }
}

struct Goal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var typeIds: [UUID] = []
    var tagIds: [UUID] = []
    var basis: GoalBasis = .duration
    var direction: GoalDirection = .reach
    var period: GoalPeriod = .day
    var targetMinutes: Double = 60
    var targetCount: Int = 1
    var weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]   // Calendar weekday：1=周日
}

// MARK: - 设置

struct PomodoroConfig: Codable, Hashable {
    var workMinutes: Double = 25
    var shortBreakMinutes: Double = 5
    var longBreakMinutes: Double = 15
    var cyclesBeforeLongBreak = 4
    var dailyTarget = 8
    var workTypeId: UUID? = nil
    var breakTypeId: UUID? = nil
    var strict = false
    var autoStartNext = true
    var sound = true
}

struct AppSettings: Codable, Hashable {
    var allowSimultaneous = false
    var warnOnIntersection = true
    var weekStartsMonday = true
    var showMenuBar = true
    var csvGroupColumn = true
    var countdownPresets: [Int] = [5, 15, 25, 45, 60]
}

struct SavedFilter: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var typeIds: [UUID] = []
    var tagIds: [UUID] = []
}

struct AppData: Codable, Equatable {
    var types: [ActivityType] = []
    var tags: [TagItem] = []
    var fields: [CustomField] = []
    var activities: [Activity] = []
    var goals: [Goal] = []
    var filters: [SavedFilter] = []
    var pomodoro = PomodoroConfig()
    var settings = AppSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        types = try c.decodeIfPresent([ActivityType].self, forKey: .types) ?? []
        tags = try c.decodeIfPresent([TagItem].self, forKey: .tags) ?? []
        fields = try c.decodeIfPresent([CustomField].self, forKey: .fields) ?? []
        activities = try c.decodeIfPresent([Activity].self, forKey: .activities) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        filters = try c.decodeIfPresent([SavedFilter].self, forKey: .filters) ?? []
        pomodoro = try c.decodeIfPresent(PomodoroConfig.self, forKey: .pomodoro) ?? PomodoroConfig()
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }

    static func sample() -> AppData {
        var d = AppData()
        let growth = ActivityType(name: "成长", icon: "leaf.fill", colorHex: "#22A06B", isGroup: true)
        let work = ActivityType(name: "工作", icon: "briefcase.fill", colorHex: "#4C8BF5")
        let study = ActivityType(name: "学习", icon: "graduationcap.fill", colorHex: "#8E5CF7", parentId: growth.id)
        let read = ActivityType(name: "阅读", icon: "book.fill", colorHex: "#F59E0B", parentId: growth.id)
        let rest = ActivityType(name: "休息", icon: "cup.and.saucer.fill", colorHex: "#14B8A6")
        d.types = [
            growth, work, study, read,
            ActivityType(name: "运动", icon: "figure.run", colorHex: "#10B981"),
            ActivityType(name: "睡眠", icon: "bed.double.fill", colorHex: "#6366F1"),
            ActivityType(name: "吃饭", icon: "fork.knife", colorHex: "#EF4444"),
            ActivityType(name: "通勤", icon: "tram.fill", colorHex: "#64748B"),
            ActivityType(name: "娱乐", icon: "gamecontroller.fill", colorHex: "#EC4899"),
            rest,
        ]
        d.tags = [TagItem(name: "专注"), TagItem(name: "会议"), TagItem(name: "线上")]
        d.fields = [
            CustomField(name: "项目", kind: .list, options: ["项目A", "项目B", "内部"], typeIds: [work.id]),
            CustomField(name: "页数", kind: .number, typeIds: [read.id]),
        ]
        d.goals = [
            Goal(name: "每天学习 1 小时", typeIds: [study.id, read.id], targetMinutes: 60),
            Goal(name: "娱乐别超过 2 小时", typeIds: [d.types[8].id], direction: .limit, targetMinutes: 120),
        ]
        d.pomodoro.workTypeId = work.id
        d.pomodoro.breakTypeId = rest.id
        return d
    }
}

struct Choice: Identifiable, Hashable {
    let id: UUID
    let name: String
}
