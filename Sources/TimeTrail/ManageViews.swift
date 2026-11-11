import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 管理

struct ManageView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case types = "类型与分组", tags = "标签", fields = "自定义字段"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .types

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 360).padding(12)
            Divider()
            switch tab {
            case .types: TypesManager()
            case .tags: TagsManager()
            case .fields: FieldsManager()
            }
        }
        .navigationTitle("管理")
    }
}

struct TypesManager: View {
    @EnvironmentObject var store: Store
    @State private var editing: ActivityType?

    var body: some View {
        List {
            Section("未分组") {
                ForEach(store.leafTypes.filter(store.isLoose)) { row($0) }
            }
            ForEach(store.groups) { g in
                Section {
                    let kids = store.children(of: g.id)
                    if kids.isEmpty { Text("空分组").foregroundStyle(.secondary) }
                    ForEach(kids) { row($0) }
                } header: {
                    HStack {
                        Image(systemName: g.icon)
                        Text(g.name)
                        Spacer()
                        Button("编辑分组") { editing = g }.buttonStyle(.link)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { editing = ActivityType(name: "") } label: { Label("新建类型", systemImage: "plus") }
                Button { editing = ActivityType(name: "", icon: "folder.fill", colorHex: "#64748B", isGroup: true) } label: {
                    Label("新建分组", systemImage: "folder.badge.plus")
                }
            }
        }
        .sheet(item: $editing) { EditTypeSheet(type: $0) }
    }

    func row(_ t: ActivityType) -> some View {
        HStack {
            TypeIcon(type: t, size: 26)
            Text(t.name)
            if t.archived { Text("已归档").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text("\(store.usage(ofType: t.id)) 条记录").font(.caption).foregroundStyle(.secondary)
            Button("编辑") { editing = t }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = t }
    }
}

struct EditTypeSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var t: ActivityType
    @State private var color: Color
    @State private var confirmDelete = false

    init(type: ActivityType) {
        _t = State(initialValue: type)
        _color = State(initialValue: Color(hex: type.colorHex))
    }

    var isNew: Bool { store.type(t.id) == nil }
    var usage: Int { store.usage(ofType: t.id) }
    var preview: ActivityType {
        var x = t
        x.colorHex = color.hexString
        return x
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                HStack(spacing: 12) {
                    TypeIcon(type: preview, size: 44)
                    TextField(t.isGroup ? "分组名称" : "类型名称", text: $t.name)
                }
                ColorPicker("颜色", selection: $color, supportsOpacity: false)
                if !t.isGroup {
                    Picker("所属分组", selection: $t.parentId) {
                        Text("无").tag(UUID?.none)
                        ForEach(store.groups) { g in Text(g.name).tag(UUID?.some(g.id)) }
                    }
                    Toggle("归档（不在活动页显示，历史记录保留）", isOn: $t.archived)
                }
                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 10), spacing: 8) {
                        ForEach(iconChoices, id: \.self) { name in
                            Image(systemName: name)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(t.icon == name ? Color.accentColor.opacity(0.25) : Color.clear))
                                .contentShape(Rectangle())
                                .onTapGesture { t.icon = name }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("删除", role: .destructive) { confirmDelete = true }
                        .disabled(!t.isGroup && usage > 0)
                        .help(!t.isGroup && usage > 0 ? "有记录的类型不能删除，请改为归档" : "")
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var x = preview
                    x.name = x.name.trimmingCharacters(in: .whitespaces)
                    store.upsertType(x)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(t.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 500, height: 580)
        .confirmationDialog("确定删除「\(t.name)」？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { store.deleteType(t.id); dismiss() }
        } message: {
            Text(t.isGroup ? "分组内的类型会变为未分组，记录不受影响。" : "此操作无法撤销。")
        }
    }
}

struct TagsManager: View {
    @EnvironmentObject var store: Store
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("新标签名称", text: $newName).onSubmit(add).frame(width: 240)
                Button("添加", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            List {
                ForEach(store.data.tags) { tag in
                    HStack {
                        Image(systemName: "number").foregroundStyle(.secondary)
                        TextField("名称", text: Binding(
                            get: { store.data.tags.first { $0.id == tag.id }?.name ?? "" },
                            set: { v in
                                if let i = store.data.tags.firstIndex(where: { $0.id == tag.id }) { store.data.tags[i].name = v }
                            }))
                        .textFieldStyle(.plain)
                        Spacer()
                        Text("\(store.usage(ofTag: tag.id)) 条记录").font(.caption).foregroundStyle(.secondary)
                        Button { store.deleteTag(tag.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    func add() {
        let n = newName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        store.addTag(n)
        newName = ""
    }
}

struct FieldsManager: View {
    @EnvironmentObject var store: Store
    @State private var editing: CustomField?

    var body: some View {
        List {
            if store.data.fields.isEmpty {
                Text("自定义字段可以给记录附加项目、页数、单价等信息，并在统计中汇总。").foregroundStyle(.secondary)
            }
            ForEach(store.data.fields) { f in
                HStack {
                    Image(systemName: "list.bullet.clipboard").foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(f.name)
                        Text(f.kind.label + (f.kind == .list ? "：" + f.options.joined(separator: " / ") : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(f.typeIds.isEmpty ? "全部类型" : f.typeIds.compactMap { store.type($0)?.name }.joined(separator: "、"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("编辑") { editing = f }
                }
            }
        }
        .toolbar {
            Button { editing = CustomField(name: "") } label: { Label("新建字段", systemImage: "plus") }
        }
        .sheet(item: $editing) { EditFieldSheet(field: $0) }
    }
}

struct EditFieldSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var f: CustomField
    @State private var optionsText: String

    init(field: CustomField) {
        _f = State(initialValue: field)
        _optionsText = State(initialValue: field.options.joined(separator: ", "))
    }

    var isNew: Bool { !store.data.fields.contains { $0.id == f.id } }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("字段名称", text: $f.name)
                Picker("类型", selection: $f.kind) {
                    ForEach(FieldKind.allCases) { Text($0.label).tag($0) }
                }
                if f.kind == .list {
                    TextField("选项（用逗号分隔）", text: $optionsText)
                }
                if f.kind == .amountPerHour || f.kind == .amountPerRecord {
                    TextField(f.kind == .amountPerHour ? "默认每小时单价" : "默认每条金额", text: $f.defaultValue)
                }
                Section("适用的类型（不选 = 全部）") {
                    ChecklistGrid(choices: store.visibleTypes.map { Choice(id: $0.id, name: $0.name) }, selection: $f.typeIds)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("删除", role: .destructive) { store.deleteField(f.id); dismiss() }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    var x = f
                    x.name = x.name.trimmingCharacters(in: .whitespaces)
                    x.options = optionsText
                        .split(whereSeparator: { $0 == "," || $0 == "，" })
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    store.upsertField(x)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(f.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 480, height: 480)
    }
}

// MARK: - 设置

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("通用", systemImage: "gearshape") }
            PomodoroSettings().tabItem { Label("番茄钟", systemImage: "timer") }
            DataSettings().tabItem { Label("数据", systemImage: "externaldrive") }
        }
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var store: Store
    @State private var presets = ""

    var body: some View {
        Form {
            Toggle("允许同时进行多个活动", isOn: $store.data.settings.allowSimultaneous)
            Toggle("编辑记录时提示时间重叠", isOn: $store.data.settings.warnOnIntersection)
            Toggle("每周从周一开始", isOn: $store.data.settings.weekStartsMonday)
            Toggle("在菜单栏显示计时", isOn: $store.data.settings.showMenuBar)
            Toggle("CSV 导出包含分组列", isOn: $store.data.settings.csvGroupColumn)
            Section("倒计时") {
                TextField("预设时长（分钟，逗号分隔）", text: $presets)
                    .onSubmit(applyPresets)
                Text("在活动页右键类型 › 倒计时开始。到点会发通知，可在卡片上 +5 分钟。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { presets = store.data.settings.countdownPresets.map(String.init).joined(separator: ", ") }
        .onDisappear(perform: applyPresets)
    }

    func applyPresets() {
        let v = presets.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .compactMap { Int($0) }.filter { $0 > 0 }
        if !v.isEmpty { store.data.settings.countdownPresets = v }
    }
}

struct PomodoroSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            Stepper("专注时长：\(Int(store.data.pomodoro.workMinutes)) 分钟", value: $store.data.pomodoro.workMinutes, in: 1...180)
            Stepper("短休息：\(Int(store.data.pomodoro.shortBreakMinutes)) 分钟", value: $store.data.pomodoro.shortBreakMinutes, in: 1...60)
            Stepper("长休息：\(Int(store.data.pomodoro.longBreakMinutes)) 分钟", value: $store.data.pomodoro.longBreakMinutes, in: 1...120)
            Stepper("长休息间隔：每 \(store.data.pomodoro.cyclesBeforeLongBreak) 个番茄", value: $store.data.pomodoro.cyclesBeforeLongBreak, in: 1...12)
            Stepper("每日目标：\(store.data.pomodoro.dailyTarget) 个", value: $store.data.pomodoro.dailyTarget, in: 1...30)
            Toggle("严格模式（专注时不能暂停/跳过）", isOn: $store.data.pomodoro.strict)
            Toggle("阶段结束后自动开始下一阶段", isOn: $store.data.pomodoro.autoStartNext)
            Toggle("提示音", isOn: $store.data.pomodoro.sound)
        }
        .formStyle(.grouped)
    }
}

struct DataSettings: View {
    @EnvironmentObject var store: Store
    @State private var confirmRestore = false
    @State private var confirmDemo = false
    @State private var message = ""

    var body: some View {
        Form {
            Section("导出") {
                Button("导出全部记录为 CSV…") {
                    let csv = "\u{FEFF}" + Exporter.csv(store)
                    Exporter.save(Data(csv.utf8), name: "时迹-\(Date().fmt("yyyyMMdd")).csv", type: .commaSeparatedText)
                }
                Button("备份全部数据为 JSON…") {
                    if let d = try? Store.encoder.encode(store.data) {
                        Exporter.save(d, name: "时迹备份-\(Date().fmt("yyyyMMdd-HHmm")).json", type: .json)
                    }
                }
            }
            Section("恢复") {
                Button("从 JSON 备份恢复…") { confirmRestore = true }
                Button("生成 14 天演示数据") { confirmDemo = true }
            }
            Section("数据文件") {
                Text(store.fileURL.path).font(.caption).textSelection(.enabled)
                Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.fileURL]) }
            }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .confirmationDialog("恢复会覆盖当前所有数据，确定继续？", isPresented: $confirmRestore) {
            Button("选择备份文件并恢复", role: .destructive) {
                guard let raw = Exporter.openJSON() else { return }
                if let d = try? Store.decoder.decode(AppData.self, from: raw) {
                    store.data = d
                    message = "已恢复 \(d.activities.count) 条记录"
                } else {
                    message = "文件格式不正确，未做任何修改"
                }
            }
        }
        .confirmationDialog("会在现有数据中追加过去 14 天的示例记录。", isPresented: $confirmDemo) {
            Button("生成") {
                store.generateDemo()
                message = "已生成演示数据"
            }
        }
    }
}
