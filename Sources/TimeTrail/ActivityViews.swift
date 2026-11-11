import SwiftUI

// MARK: - 活动页

struct ActivitiesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Activity?
    @State private var editingType: ActivityType?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !store.active.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("进行中").font(.headline)
                        ForEach(store.active) { a in
                            RunningCard(activity: a) { editing = a }
                        }
                    }
                }
                ForEach(store.typeSections) { sec in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(sec.title).font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 12)], spacing: 12) {
                            ForEach(sec.types) { t in
                                TypeTile(type: t) { editingType = t }
                            }
                        }
                    }
                }
                Text("提示：点击类型开始计时；右键可用倒计时开始或编辑类型。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                TodaySummary()
            }
            .padding(20)
        }
        .navigationTitle("活动")
        .toolbar {
            ToolbarItem {
                Text(store.data.settings.allowSimultaneous ? "允许多任务同时计时" : "单任务计时")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { EditActivitySheet(activity: $0) }
        .sheet(item: $editingType) { EditTypeSheet(type: $0) }
    }
}

struct TypeTile: View {
    @EnvironmentObject var store: Store
    let type: ActivityType
    var onEditType: () -> Void

    var body: some View {
        let running = store.active.contains { $0.typeId == type.id }
        Button { store.start(type.id) } label: {
            VStack(spacing: 8) {
                TypeIcon(type: type, size: 46)
                Text(type.name).font(.callout).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(running ? Color(hex: type.colorHex).opacity(0.18) : Color.primary.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("开始计时") { store.start(type.id) }
            Menu("倒计时开始") {
                ForEach(store.data.settings.countdownPresets, id: \.self) { m in
                    Button("\(m) 分钟") { store.start(type.id, countdown: Double(m) * 60) }
                }
            }
            Divider()
            Button("编辑类型…", action: onEditType)
        }
    }
}

struct RunningCard: View {
    @EnvironmentObject var store: Store
    let activity: Activity
    var onEdit: () -> Void

    var body: some View {
        let t = store.type(activity.typeId)
        let tint = Color(hex: t?.colorHex ?? "#999999")
        HStack(spacing: 14) {
            TypeIcon(type: t, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(t?.name ?? "未知").font(.title3.bold())
                    if activity.isPomodoro { Text("🍅") }
                    if activity.state == .paused {
                        Text("已暂停").font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                }
                Text("开始于 \(activity.start.fmt("HH:mm"))" + (activity.comment.isEmpty ? "" : " · \(activity.comment)"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !activity.tagIds.isEmpty { TagChips(ids: activity.tagIds) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                LiveDuration(activity: activity)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                if activity.countdown != nil { CountdownLabel(activity: activity) }
            }
            HStack(spacing: 6) {
                if activity.countdown != nil {
                    Button("+5分") { store.addTime(activity.id, minutes: 5) }
                }
                Button {
                    if activity.state == .running { store.pause(activity.id) } else { store.resume(activity.id) }
                } label: { Image(systemName: activity.state == .running ? "pause.fill" : "play.fill") }
                    .help(activity.state == .running ? "暂停" : "继续")
                Button { store.stop(activity.id) } label: { Image(systemName: "stop.fill") }
                    .help("停止")
                Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                    .help("编辑备注、标签、字段")
            }
            .controlSize(.large)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.35)))
    }
}

struct TodaySummary: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let r = store.calendar.dateInterval(of: .day, for: Date())!
        let sl = store.slices(r, Filter())
        let total = sl.reduce(0) { $0 + $1.seconds }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日").font(.headline)
                Spacer()
                Text("合计 \(fmtHM(total))").foregroundStyle(.secondary)
            }
            if sl.isEmpty { Text("今天还没有记录").foregroundStyle(.secondary) }
            ForEach(sl) { s in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.name)
                        Spacer()
                        Text(fmtHM(s.seconds)).monospacedDigit()
                    }
                    GeometryReader { g in
                        Capsule().fill(s.color.opacity(0.7))
                            .frame(width: max(4, g.size.width * s.seconds / max(total, 1)))
                    }
                    .frame(height: 5)
                }
            }
        }
    }
}

// MARK: - 记录页

struct DayGroup: Identifiable {
    let id: Date
    let items: [Activity]
}

struct HistoryView: View {
    @EnvironmentObject var store: Store
    @State private var typeFilter: Set<UUID> = []
    @State private var tagFilter: Set<UUID> = []
    @State private var search = ""
    @State private var days = 30
    @State private var editing: Activity?

    var groups: [DayGroup] {
        let cal = store.calendar
        let cutoff = days == 0 ? Date.distantPast : cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: Date()))!
        let f = Filter(types: typeFilter, tags: tagFilter)
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let items = store.data.activities.filter { a in
            a.state == .stopped && a.start >= cutoff && store.matches(a, f) &&
                (q.isEmpty || a.comment.lowercased().contains(q) || store.name(a.typeId).lowercased().contains(q))
        }
        return Dictionary(grouping: items) { cal.startOfDay(for: $0.start) }
            .map { DayGroup(id: $0.key, items: $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        let gs = groups
        List {
            if gs.isEmpty { Text("没有符合条件的记录").foregroundStyle(.secondary) }
            ForEach(gs) { g in
                Section {
                    ForEach(g.items) { a in
                        HistoryRow(activity: a)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { editing = a }
                            .contextMenu {
                                Button("编辑…") { editing = a }
                                Button("再次开始") { store.start(a.typeId) }
                                Button("复制一条") {
                                    var c = a
                                    c.id = UUID()
                                    store.upsert(c)
                                }
                                Divider()
                                Button("删除", role: .destructive) { store.delete(a.id) }
                            }
                    }
                } header: {
                    HStack {
                        Text(g.id.fmt("M月d日 EEEE"))
                        Spacer()
                        Text(fmtHM(g.items.reduce(0) { $0 + $1.duration() }))
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索类型或备注")
        .navigationTitle("记录")
        .toolbar {
            ToolbarItemGroup {
                MultiSelectMenu(title: "类型", items: store.filterChoices, selection: $typeFilter)
                MultiSelectMenu(title: "标签", items: store.tagChoices, selection: $tagFilter)
                Picker("范围", selection: $days) {
                    Text("近7天").tag(7)
                    Text("近30天").tag(30)
                    Text("近90天").tag(90)
                    Text("近1年").tag(365)
                    Text("全部").tag(0)
                }
                .pickerStyle(.menu)
                .fixedSize()
                Button { editing = store.draftActivity() } label: { Label("补记", systemImage: "plus") }
                    .help("手动补记一条记录")
            }
        }
        .sheet(item: $editing) { EditActivitySheet(activity: $0) }
    }
}

struct HistoryRow: View {
    @EnvironmentObject var store: Store
    let activity: Activity
    var body: some View {
        HStack(spacing: 12) {
            TypeIcon(type: store.type(activity.typeId), size: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.name(activity.typeId)).fontWeight(.medium)
                    if activity.isPomodoro { Text("🍅").font(.caption) }
                    if activity.spans.count > 1 {
                        Text("\(activity.spans.count) 段").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("\(activity.start.fmt("HH:mm")) – \((activity.end ?? Date()).fmt("HH:mm"))"
                     + (activity.comment.isEmpty ? "" : "   \(activity.comment)"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if !activity.tagIds.isEmpty { TagChips(ids: activity.tagIds) }
            Spacer()
            Text(fmtHM(activity.duration())).monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 编辑记录

struct EditActivitySheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var a: Activity

    init(activity: Activity) { _a = State(initialValue: activity) }

    var isNew: Bool { !store.data.activities.contains { $0.id == a.id } }
    var valid: Bool { !a.spans.isEmpty && a.spans.allSatisfy { $0.to == nil || $0.to! > $0.from } }

    var body: some View {
        let overlaps = store.data.settings.warnOnIntersection ? store.intersections(of: a) : []
        let fields = store.data.fields.filter { $0.applies(to: a.typeId) }
        VStack(spacing: 0) {
            Form {
                Picker("类型", selection: $a.typeId) {
                    ForEach(store.leafTypes.filter { !$0.archived || $0.id == a.typeId }) { t in
                        Text(t.name).tag(t.id)
                    }
                }
                Section("时间段") {
                    ForEach($a.spans) { $s in
                        HStack {
                            DatePicker("从", selection: $s.from)
                            if let to = Binding($s.to) {
                                DatePicker("到", selection: to)
                            } else {
                                Text("进行中").foregroundStyle(.secondary)
                            }
                            if a.spans.count > 1 {
                                Button { a.spans.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    HStack {
                        Button("添加时间段") {
                            let last = a.spans.compactMap(\.to).max() ?? Date()
                            a.spans.append(TimeSpan(from: last, to: last.addingTimeInterval(1800)))
                        }
                        .disabled(a.isActive)
                        Spacer()
                        Text("合计 \(fmtClock(a.duration()))").monospacedDigit().foregroundStyle(.secondary)
                    }
                    if !overlaps.isEmpty {
                        Label("与 \(overlaps.count) 条记录时间重叠：" + overlaps.prefix(3).map { "\(store.name($0.typeId)) \($0.start.fmt("M/d HH:mm"))" }.joined(separator: "，"),
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                Section("备注") {
                    TextField("写点什么…", text: $a.comment, axis: .vertical)
                        .lineLimit(2...5)
                }
                if !store.data.tags.isEmpty {
                    Section("标签") { ChecklistGrid(choices: store.tagChoices, selection: $a.tagIds) }
                }
                if !fields.isEmpty {
                    Section("自定义字段") {
                        ForEach(fields) { f in FieldInput(field: f, values: $a.fields) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("删除", role: .destructive) {
                        store.delete(a.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") {
                    var x = a
                    x.spans.sort { $0.from < $1.from }
                    store.upsert(x)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
            .padding()
        }
        .frame(width: 560, height: 640)
    }
}

struct FieldInput: View {
    let field: CustomField
    @Binding var values: [UUID: String]

    var body: some View {
        let b = Binding<String>(
            get: { values[field.id] ?? "" },
            set: { values[field.id] = $0.isEmpty ? nil : $0 })
        switch field.kind {
        case .list:
            Picker(field.name, selection: b) {
                Text("—").tag("")
                ForEach(field.options, id: \.self) { Text($0).tag($0) }
            }
        case .number:
            TextField(field.name, text: b, prompt: Text("数字"))
        case .amountPerHour:
            TextField(field.name, text: b, prompt: Text("每小时单价，默认 \(field.defaultValue.isEmpty ? "0" : field.defaultValue)"))
        case .amountPerRecord:
            TextField(field.name, text: b, prompt: Text("金额，默认 \(field.defaultValue.isEmpty ? "0" : field.defaultValue)"))
        case .text:
            TextField(field.name, text: b)
        }
    }
}
