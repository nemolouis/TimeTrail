import SwiftUI
import AppKit

// MARK: - 格式化

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x4C8BF5
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#4C8BF5" }
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

func fmtClock(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded(.down)))
    return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
}

func fmtMS(_ t: TimeInterval) -> String {
    let s = max(0, Int(t.rounded(.up)))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

func fmtHM(_ t: TimeInterval) -> String {
    let m = Int((t / 60).rounded())
    if m < 60 { return "\(m)分" }
    return m % 60 == 0 ? "\(m / 60)小时" : "\(m / 60)小时\(m % 60)分"
}

func fmtNum(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}

private var formatterCache: [String: DateFormatter] = [:]

extension Date {
    func fmt(_ f: String) -> String {
        if let df = formatterCache[f] { return df.string(from: self) }
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = f
        formatterCache[f] = df
        return df.string(from: self)
    }
}

// MARK: - 统计区间

enum RangeKind: String, CaseIterable, Identifiable {
    case day, week, month, year, last7, last30, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "日"; case .week: "周"; case .month: "月"; case .year: "年"
        case .last7: "近7天"; case .last30: "近30天"; case .custom: "自定义"
        }
    }
}

func makeRange(_ kind: RangeKind, offset: Int, cal: Calendar, from: Date, to: Date, now: Date = Date()) -> DateInterval {
    switch kind {
    case .day:
        return cal.dateInterval(of: .day, for: cal.date(byAdding: .day, value: offset, to: now)!)!
    case .week:
        return cal.dateInterval(of: .weekOfYear, for: cal.date(byAdding: .weekOfYear, value: offset, to: now)!)!
    case .month:
        return cal.dateInterval(of: .month, for: cal.date(byAdding: .month, value: offset, to: now)!)!
    case .year:
        return cal.dateInterval(of: .year, for: cal.date(byAdding: .year, value: offset, to: now)!)!
    case .last7, .last30:
        let n = kind == .last7 ? 7 : 30
        let end = cal.date(byAdding: .day, value: 1 + offset * n, to: cal.startOfDay(for: now))!
        return DateInterval(start: cal.date(byAdding: .day, value: -n, to: end)!, end: end)
    case .custom:
        let a = cal.startOfDay(for: min(from, to))
        let b = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(from, to)))!
        return DateInterval(start: a, end: b)
    }
}

func rangeLabel(_ r: DateInterval) -> String {
    let last = r.end.addingTimeInterval(-1)
    if Calendar.current.isDate(r.start, inSameDayAs: last) { return r.start.fmt("yyyy年M月d日 EEE") }
    return "\(r.start.fmt("yyyy/M/d")) – \(last.fmt("M/d"))"
}

func daysElapsed(_ r: DateInterval, cal: Calendar) -> Int {
    let end = min(r.end, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!)
    guard end > r.start else { return 1 }
    return max(1, Int((end.timeIntervalSince(r.start) / 86400).rounded(.up)))
}

let iconChoices = [
    "briefcase.fill", "laptopcomputer", "chevron.left.forwardslash.chevron.right", "hammer.fill", "wrench.and.screwdriver.fill",
    "graduationcap.fill", "book.fill", "text.book.closed.fill", "pencil", "brain.head.profile",
    "figure.run", "figure.walk", "bicycle", "dumbbell.fill", "heart.fill",
    "bed.double.fill", "moon.fill", "sun.max.fill", "cup.and.saucer.fill", "fork.knife",
    "tram.fill", "car.fill", "airplane", "house.fill", "cart.fill",
    "gamecontroller.fill", "film.fill", "tv.fill", "music.note", "paintbrush.fill",
    "person.2.fill", "phone.fill", "bubble.left.fill", "envelope.fill", "camera.fill",
    "leaf.fill", "shower.fill", "pills.fill", "dog.fill", "folder.fill",
]

let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
func weekdayName(_ wd: Int) -> String { ["", "日", "一", "二", "三", "四", "五", "六"][wd] }

// MARK: - 通用组件

struct TypeIcon: View {
    let type: ActivityType?
    var size: CGFloat = 32
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: type?.colorHex ?? "#999999"))
            Image(systemName: type?.icon ?? "questionmark")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct LiveDuration: View {
    @EnvironmentObject var ticker: Ticker
    let activity: Activity
    var body: some View {
        Text(fmtClock(activity.duration(now: ticker.now))).monospacedDigit()
    }
}

struct CountdownLabel: View {
    @EnvironmentObject var ticker: Ticker
    let activity: Activity
    var body: some View {
        let left = (activity.countdown ?? 0) - activity.duration(now: ticker.now)
        Text(left >= 0 ? "倒计时剩余 \(fmtClock(left))" : "已超时 \(fmtClock(-left))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(left >= 0 ? Color.secondary : Color.red)
    }
}

struct TagChips: View {
    @EnvironmentObject var store: Store
    let ids: [UUID]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ids, id: \.self) { id in
                if let n = store.tagName(id) {
                    Text("#\(n)")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

struct MultiSelectMenu: View {
    let title: String
    let items: [Choice]
    @Binding var selection: Set<UUID>
    var body: some View {
        Menu {
            Button("全部") { selection = [] }
            Divider()
            ForEach(items) { it in
                Button {
                    if selection.contains(it.id) { selection.remove(it.id) } else { selection.insert(it.id) }
                } label: {
                    if selection.contains(it.id) { Label(it.name, systemImage: "checkmark") } else { Text(it.name) }
                }
            }
        } label: {
            Text(selection.isEmpty ? "\(title)：全部" : "\(title)：已选 \(selection.count)")
        }
        .fixedSize()
    }
}

struct ChecklistGrid: View {
    let choices: [Choice]
    @Binding var selection: [UUID]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(choices) { c in
                Toggle(c.name, isOn: Binding(
                    get: { selection.contains(c.id) },
                    set: { on in
                        if on { if !selection.contains(c.id) { selection.append(c.id) } } else { selection.removeAll { $0 == c.id } }
                    }))
                .toggleStyle(.checkbox)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

struct EmptyHint: View {
    var text = "这段时间没有记录"
    var body: some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 160)
    }
}
