import SwiftUI
import Charts

// MARK: - 统计

enum StatTab: String, CaseIterable, Identifiable {
    case pie, daily, hours, tags, fields, compare
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pie: "分布"; case .daily: "每日"; case .hours: "时段"
        case .tags: "标签"; case .fields: "字段"; case .compare: "对比"
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var store: Store
    @State private var kind: RangeKind = .week
    @State private var offset = 0
    @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var to = Date()
    @State private var filter = Filter()
    @State private var byGroup = false
    @State private var tab: StatTab = .pie
    @State private var showSave = false
    @State private var saveName = ""

    var range: DateInterval { makeRange(kind, offset: offset, cal: store.calendar, from: from, to: to) }
    var prevRange: DateInterval {
        if kind == .custom {
            return DateInterval(start: range.start.addingTimeInterval(-range.duration), duration: range.duration)
        }
        return makeRange(kind, offset: offset - 1, cal: store.calendar, from: from, to: to)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            ScrollView { content.padding(20) }
        }
        .navigationTitle("统计")
        .alert("保存筛选方案", isPresented: $showSave) {
            TextField("名称", text: $saveName)
            Button("保存") {
                let n = saveName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty {
                    store.data.filters.append(SavedFilter(name: n, typeIds: Array(filter.types), tagIds: Array(filter.tags)))
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("", selection: $kind) {
                    ForEach(RangeKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 440)
                .onChange(of: kind) { offset = 0 }
                Spacer()
                if kind == .custom {
                    DatePicker("", selection: $from, displayedComponents: .date).labelsHidden()
                    Text("–")
                    DatePicker("", selection: $to, displayedComponents: .date).labelsHidden()
                } else {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    Text(rangeLabel(range)).monospacedDigit().frame(minWidth: 180)
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }.disabled(offset >= 0)
                    Button("回到本期") { offset = 0 }.disabled(offset == 0)
                }
            }
            HStack {
                MultiSelectMenu(title: "类型", items: store.filterChoices, selection: $filter.types)
                MultiSelectMenu(title: "标签", items: store.tagChoices, selection: $filter.tags)
                Toggle("按分组汇总", isOn: $byGroup).toggleStyle(.checkbox)
                Menu("筛选方案") {
                    ForEach(store.data.filters) { f in
                        Button(f.name) { filter = Filter(types: Set(f.typeIds), tags: Set(f.tagIds)) }
                    }
                    if !store.data.filters.isEmpty {
                        Divider()
                        Menu("删除方案") {
                            ForEach(store.data.filters) { f in
                                Button(f.name) { store.data.filters.removeAll { $0.id == f.id } }
                            }
                        }
                    }
                    Divider()
                    Button("保存当前筛选…") { saveName = ""; showSave = true }
                }
                .fixedSize()
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(StatTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            }
        }
    }

    @ViewBuilder var content: some View {
        let r = range
        let sl = store.slices(r, filter, byGroup: byGroup)
        let total = sl.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                StatCard(title: "总时长", value: fmtHM(total))
                StatCard(title: "记录数", value: "\(sl.reduce(0) { $0 + $1.count })")
                StatCard(title: "日均", value: fmtHM(total / Double(daysElapsed(r, cal: store.calendar))))
                StatCard(title: byGroup ? "类别数" : "类型数", value: "\(sl.count)")
            }
            switch tab {
            case .pie:
                PieSection(slices: sl, total: total)
            case .daily:
                DailySection(entries: store.daily(r, filter, byGroup: byGroup), slices: sl)
            case .hours:
                HoursSection(bins: store.hourly(r, filter))
            case .tags:
                TagSection(items: store.tagSlices(r, filter))
            case .fields:
                FieldSection(stats: store.fieldStats(r, filter))
            case .compare:
                CompareSection(cur: sl, prev: store.slices(prevRange, filter, byGroup: byGroup),
                               curLabel: rangeLabel(r), prevLabel: rangeLabel(prevRange))
            }
        }
    }
}

struct PieSection: View {
    let slices: [TypeSlice]
    let total: Double
    var body: some View {
        if slices.isEmpty { EmptyHint() } else {
            HStack(alignment: .top, spacing: 30) {
                Chart(slices) { s in
                    SectorMark(angle: .value("时长", s.seconds), innerRadius: .ratio(0.58), angularInset: 1.5)
                        .foregroundStyle(s.color)
                        .cornerRadius(3)
                }
                .frame(width: 260, height: 260)
                .overlay {
                    VStack {
                        Text("合计").font(.caption).foregroundStyle(.secondary)
                        Text(fmtHM(total)).font(.title3.bold())
                    }
                }
                VStack(spacing: 0) {
                    ForEach(slices) { s in
                        HStack {
                            Circle().fill(s.color).frame(width: 10, height: 10)
                            Text(s.name)
                            Spacer()
                            Text("\(s.count) 次").foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                            Text(fmtHM(s.seconds)).monospacedDigit().frame(width: 100, alignment: .trailing)
                            Text(String(format: "%.1f%%", s.seconds / max(total, 1) * 100))
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
    }
}

struct DailySection: View {
    let entries: [DayEntry]
    let slices: [TypeSlice]
    var body: some View {
        if entries.isEmpty { EmptyHint() } else {
            Chart(entries) { e in
                BarMark(x: .value("日期", e.day, unit: .day), y: .value("小时", e.seconds / 3600))
                    .foregroundStyle(by: .value("类型", e.name))
            }
            .chartForegroundStyleScale(domain: slices.map(\.name), range: slices.map(\.color))
            .chartYAxisLabel("小时")
            .frame(height: 360)
        }
    }
}

struct HoursSection: View {
    let bins: [HourBin]
    var body: some View {
        if bins.allSatisfy({ $0.seconds == 0 }) { EmptyHint() } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("一天中各小时的累计时长").font(.headline)
                Chart(bins) { b in
                    BarMark(x: .value("时", b.id), y: .value("小时", b.seconds / 3600))
                        .foregroundStyle(Color.accentColor.gradient)
                }
                .chartXScale(domain: 0...23)
                .chartXAxis { AxisMarks(values: Array(stride(from: 0, through: 23, by: 2))) }
                .chartYAxisLabel("小时")
                .frame(height: 320)
            }
        }
    }
}

struct TagSection: View {
    let items: [TypeSlice]
    var body: some View {
        if items.isEmpty { EmptyHint() } else {
            VStack(alignment: .leading, spacing: 14) {
                Chart(items) { s in
                    BarMark(x: .value("小时", s.seconds / 3600), y: .value("标签", s.name))
                        .foregroundStyle(s.color)
                        .annotation(position: .trailing) { Text(fmtHM(s.seconds)).font(.caption) }
                }
                .frame(height: CGFloat(max(120, items.count * 36)))
                Text("一条记录有多个标签时，时长会分别计入每个标签。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct FieldSection: View {
    let stats: [FieldStat]
    var body: some View {
        if stats.isEmpty { EmptyHint(text: "还没有自定义字段，可在「管理 › 自定义字段」中添加") } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .top)], spacing: 14) {
                ForEach(stats) { st in
                    GroupBox {
                        VStack(spacing: 6) {
                            ForEach(st.lines) { l in
                                HStack { Text(l.label); Spacer(); Text(l.value).monospacedDigit().foregroundStyle(.secondary) }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } label: {
                        Label("\(st.field.name)（\(st.field.kind.label)）", systemImage: "list.bullet.clipboard")
                    }
                }
            }
        }
    }
}

struct CompareSection: View {
    struct Row: Identifiable { let id = UUID(); let name: String; let period: String; let hours: Double }
    let cur: [TypeSlice]
    let prev: [TypeSlice]
    let curLabel: String
    let prevLabel: String

    var body: some View {
        var names: [String] = []
        for n in cur.map(\.name) + prev.map(\.name) where !names.contains(n) { names.append(n) }
        let curMap = Dictionary(cur.map { ($0.name, $0.seconds) }, uniquingKeysWith: +)
        let prevMap = Dictionary(prev.map { ($0.name, $0.seconds) }, uniquingKeysWith: +)
        let rows = names.flatMap { n in
            [Row(name: n, period: "本期", hours: (curMap[n] ?? 0) / 3600),
             Row(name: n, period: "上期", hours: (prevMap[n] ?? 0) / 3600)]
        }
        return VStack(alignment: .leading, spacing: 16) {
            Text("本期 \(curLabel)  对比  上期 \(prevLabel)").font(.headline)
            if names.isEmpty { EmptyHint() } else {
                Chart(rows) { r in
                    BarMark(x: .value("类型", r.name), y: .value("小时", r.hours))
                        .foregroundStyle(by: .value("周期", r.period))
                        .position(by: .value("周期", r.period))
                }
                .chartForegroundStyleScale(["本期": Color.accentColor, "上期": Color.gray.opacity(0.5)])
                .frame(height: 300)
                VStack(spacing: 0) {
                    HStack {
                        Text("类型").frame(maxWidth: .infinity, alignment: .leading)
                        Text("本期").frame(width: 100, alignment: .trailing)
                        Text("上期").frame(width: 100, alignment: .trailing)
                        Text("变化").frame(width: 120, alignment: .trailing)
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                    Divider()
                    ForEach(names, id: \.self) { n in
                        let c = curMap[n] ?? 0, p = prevMap[n] ?? 0
                        let delta = c - p
                        HStack {
                            Text(n).frame(maxWidth: .infinity, alignment: .leading)
                            Text(fmtHM(c)).frame(width: 100, alignment: .trailing)
                            Text(fmtHM(p)).frame(width: 100, alignment: .trailing).foregroundStyle(.secondary)
                            Text((delta >= 0 ? "+" : "−") + fmtHM(abs(delta)) + (p > 0 ? String(format: " (%+.0f%%)", delta / p * 100) : ""))
                                .frame(width: 120, alignment: .trailing)
                                .foregroundStyle(delta > 0 ? Color.green : (delta < 0 ? Color.red : Color.secondary))
                        }
                        .monospacedDigit()
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - 目标

struct GoalsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Goal?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if store.data.goals.isEmpty {
                    Text("还没有目标，点右上角 + 新建").foregroundStyle(.secondary).padding(.top, 60)
                }
                ForEach(store.data.goals) { g in
                    GoalCard(goal: g).onTapGesture { editing = g }
                }
            }
            .padding(20)
        }
        .navigationTitle("目标")
        .toolbar {
            Button { editing = Goal(name: "") } label: { Label("新建目标", systemImage: "plus") }
        }
        .sheet(item: $editing) { EditGoalSheet(goal: $0) }
    }
}

struct GoalCard: View {
    @EnvironmentObject var store: Store
    let goal: Goal

    var body: some View {
        let r = store.goalRange(goal, at: Date())
        let v = store.goalValue(goal, in: r)
        let target = store.goalTarget(goal)
        let ratio = target > 0 ? v / target : 0
        let reach = goal.direction == .reach
        let ok = reach ? ratio >= 1 : ratio <= 1
        let restDay = goal.period == .day && !goal.weekdays.contains(store.calendar.component(.weekday, from: Date()))
        let status: String = {
            if restDay { return "今天不计入" }
            if reach { return ok ? "已达成 🎉" : "还差 \(store.goalValueText(goal, target - v))" }
            return ok ? "还剩 \(store.goalValueText(goal, target - v))" : "已超出 \(store.goalValueText(goal, v - target))"
        }()
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: reach ? "flag.checkered" : "hand.raised.fill")
                    .foregroundStyle(reach ? Color.green : Color.orange)
                Text(goal.name.isEmpty ? "未命名目标" : goal.name).font(.headline)
                Spacer()
                Text(store.goalDescription(goal)).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(ratio, 0), 1))
                .tint(!reach && ratio > 1 ? .red : (ok ? .green : .accentColor))
            HStack {
                Text("\(goal.period.currentLabel)：\(store.goalValueText(goal, v)) / \(store.goalValueText(goal, target))")
                    .monospacedDigit()
                Spacer()
                Text(status).foregroundStyle(ok ? Color.green : (reach ? Color.secondary : Color.red))
            }
            .font(.callout)
            if goal.period == .day { GoalHeatmap(goal: goal) }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
        .contentShape(Rectangle())
    }
}

struct GoalHeatmap: View {
    @EnvironmentObject var store: Store
    let goal: Goal
    let weeks = 16

    var body: some View {
        let cal = store.calendar
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: cal.dateInterval(of: .weekOfYear, for: today)!.start)!
        let target = store.goalTarget(goal)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(day: day, today: today, target: target))
                            .frame(width: 11, height: 11)
                            .help(day.fmt("M月d日"))
                    }
                }
            }
            Text("近 \(weeks) 周").font(.caption2).foregroundStyle(.secondary).padding(.leading, 6)
        }
    }

    func cellColor(day: Date, today: Date, target: Double) -> Color {
        if day > today { return .clear }
        let cal = store.calendar
        if !goal.weekdays.contains(cal.component(.weekday, from: day)) { return Color.primary.opacity(0.04) }
        let v = store.goalValue(goal, in: cal.dateInterval(of: .day, for: day)!)
        let ratio = target > 0 ? v / target : 0
        if goal.direction == .reach {
            return ratio <= 0 ? Color.primary.opacity(0.08) : Color.green.opacity(0.25 + 0.75 * min(ratio, 1))
        }
        if ratio > 1 { return Color.red.opacity(0.7) }
        return v > 0 ? Color.green.opacity(0.6) : Color.primary.opacity(0.08)
    }
}

struct EditGoalSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var g: Goal

    init(goal: Goal) { _g = State(initialValue: goal) }

    var isNew: Bool { !store.data.goals.contains { $0.id == g.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("名称", text: $g.name)
                Picker("目标方向", selection: $g.direction) {
                    Text("达成（至少）").tag(GoalDirection.reach)
                    Text("限制（不超过）").tag(GoalDirection.limit)
                }
                Picker("依据", selection: $g.basis) {
                    Text("时长").tag(GoalBasis.duration)
                    Text("次数").tag(GoalBasis.occurrence)
                }
                Picker("周期", selection: $g.period) {
                    ForEach(GoalPeriod.allCases) { Text($0.label).tag($0) }
                }
                if g.basis == .duration {
                    Stepper("小时：\(Int(g.targetMinutes) / 60)",
                            value: Binding(get: { Int(g.targetMinutes) / 60 },
                                           set: { g.targetMinutes = Double($0 * 60 + Int(g.targetMinutes) % 60) }),
                            in: 0...10000)
                    Stepper("分钟：\(Int(g.targetMinutes) % 60)",
                            value: Binding(get: { Int(g.targetMinutes) % 60 },
                                           set: { g.targetMinutes = Double(Int(g.targetMinutes) / 60 * 60 + $0) }),
                            in: 0...55, step: 5)
                } else {
                    Stepper("次数：\(g.targetCount)", value: $g.targetCount, in: 1...10000)
                }
                if g.period == .day {
                    Section("生效日") {
                        HStack {
                            ForEach(weekdayOrder, id: \.self) { wd in
                                Toggle("周" + weekdayName(wd), isOn: Binding(
                                    get: { g.weekdays.contains(wd) },
                                    set: { on in if on { g.weekdays.append(wd) } else { g.weekdays.removeAll { $0 == wd } } }))
                                .toggleStyle(.button)
                            }
                        }
                    }
                }
                Section("计入的类型（不选 = 全部）") {
                    ChecklistGrid(choices: store.typeChoices, selection: $g.typeIds)
                }
                if !store.data.tags.isEmpty {
                    Section("计入的标签（不选 = 不限）") {
                        ChecklistGrid(choices: store.tagChoices, selection: $g.tagIds)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("删除", role: .destructive) { store.deleteGoal(g.id); dismiss() }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { store.upsertGoal(g); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(g.name.trimmingCharacters(in: .whitespaces).isEmpty || store.goalTarget(g) <= 0)
            }
            .padding()
        }
        .frame(width: 520, height: 640)
    }
}

// MARK: - 番茄钟

struct PomodoroView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pomo: PomodoroEngine
    @EnvironmentObject var ticker: Ticker

    var body: some View {
        let cfg = store.data.pomodoro
        let phase = pomo.displayPhase
        let total = pomo.length(phase)
        let remaining = pomo.remaining(now: ticker.now)
        let progress = pomo.phase == .idle ? 0 : (total > 0 ? 1 - remaining / total : 0)
        VStack(spacing: 22) {
            Text(pomo.phase == .idle ? "下一阶段：\(phase.title)" : pomo.phase.title)
                .font(.title2.bold())
                .foregroundStyle(phase.color)
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(phase.color, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 4) {
                    Text(fmtMS(remaining))
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if pomo.isPaused { Text("已暂停").foregroundStyle(.secondary) }
                }
            }
            .frame(width: 260, height: 260)

            HStack(spacing: 12) {
                if pomo.phase == .idle {
                    Button { pomo.begin(phase) } label: {
                        Label(phase == .work ? "开始专注" : "开始休息", systemImage: "play.fill").frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    if phase != .work {
                        Button("跳过休息") { pomo.begin(.work) }
                    }
                } else {
                    let locked = cfg.strict && pomo.phase == .work
                    if pomo.isPaused {
                        Button { pomo.resume() } label: { Label("继续", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button { pomo.pause() } label: { Label("暂停", systemImage: "pause.fill") }
                            .disabled(locked)
                    }
                    Button(pomo.phase == .work ? "提前完成" : "跳过") { pomo.skip() }
                        .disabled(locked)
                    Button("放弃", role: .destructive) { pomo.abandon() }
                }
            }
            .controlSize(.large)
            if cfg.strict { Text("严格模式：专注期间不能暂停或跳过").font(.caption).foregroundStyle(.secondary) }

            HStack(spacing: 8) {
                ForEach(0..<max(1, cfg.cyclesBeforeLongBreak), id: \.self) { i in
                    Circle()
                        .fill(i < pomo.completedInSet ? Color.red : Color.primary.opacity(0.12))
                        .frame(width: 12, height: 12)
                }
                Text("每 \(cfg.cyclesBeforeLongBreak) 个番茄一次长休息").font(.caption).foregroundStyle(.secondary)
            }
            Text("今日完成 \(store.todayPomodoros) / \(cfg.dailyTarget) 个番茄").font(.headline)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("专注记为", selection: $store.data.pomodoro.workTypeId) {
                        Text("不记录").tag(UUID?.none)
                        ForEach(store.visibleTypes) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Picker("休息记为", selection: $store.data.pomodoro.breakTypeId) {
                        Text("不记录").tag(UUID?.none)
                        ForEach(store.visibleTypes) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    Text("时长等更多选项在「设置 › 番茄钟」中调整。").font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }
            .frame(width: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("番茄钟")
    }
}
