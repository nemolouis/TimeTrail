# 时迹 TimeTrail

一款原生 macOS 时间记录应用（SwiftUI + Swift Charts）。功能参照 aTimeLogger 付费版的功能集合独立实现，没有任何内购或功能限制；数据只存在本机。

## 构建与运行

只需要 Command Line Tools（不需要 Xcode），macOS 14+：

```bash
./build.sh
open "build/时迹.app"
```

`build.sh` 会自动绕过某些 Command Line Tools 升级后残留的 `module.modulemap` 冲突（用 VFS overlay，不修改系统文件）。

## 应用图标

图标由 [Scripts/make_icon.swift](Scripts/make_icon.swift) 用代码绘制，生成 `Resources/AppIcon-1024.png`；`build.sh` 打包时会自动转成 `AppIcon.icns`。改完绘制代码后，重新生成图标：

```bash
swiftc Scripts/make_icon.swift -o build/make_icon && build/make_icon Resources/AppIcon-1024.png && ./build.sh
```

## 功能

| 模块 | 功能 |
|---|---|
| 活动 | 点类型开始计时；暂停 / 继续 / 停止；可选同时进行多个活动；右键「倒计时开始」，到点通知，可 +5 分钟；今日汇总 |
| 记录 | 按天分组的历史；搜索备注；按类型 / 标签 / 时间范围筛选；手动补记；编辑多段时间、备注、标签、自定义字段；时间重叠提醒；复制、再次开始、删除 |
| 统计 | 日 / 周 / 月 / 年 / 近7天 / 近30天 / 自定义，可前后翻页；饼图分布、每日堆叠柱状图、24 小时时段分布、标签统计、自定义字段汇总（数字合计与平均、选项分布、按小时 / 按条计费）、本期与上期对比；按分组汇总；保存筛选方案 |
| 目标 | 达成 / 限制两种方向；按时长或次数；按天 / 周 / 月 / 年 / 累计；可选生效日；限定类型和标签；进度条，日目标显示 16 周热力图 |
| 番茄钟 | 专注、短休息、长休息循环；自动进入下一阶段；严格模式；每日目标；专注和休息自动记为指定类型 |
| 管理 | 类型（40 个图标、自定义颜色、归档）、分组、标签、自定义字段（文本 / 数字 / 选项 / 按小时计费 / 按条计费） |
| 其他 | 菜单栏实时计时和快速开始；CSV 导出（兼容 Excel 中文）；JSON 备份与恢复；生成演示数据 |

数据文件：`~/Library/Application Support/TimeTrail/data.json`

## 和 aTimeLogger 付费版的对应

已实现：不限类型数、彩色图标、分组、标签、自定义字段、番茄钟、次数目标、每日柱状图、高级统计、多条筛选、倒计时（多个）、重叠提醒、CSV 导出、备份与恢复。

没有实现：多设备云同步和网页版（需要服务器）、日历集成、地理位置提醒、Apple Watch、Siri 快捷指令、URL Scheme。

## 代码结构

- `Models.swift`：数据模型和示例数据
- `Store.swift`：存储、计时操作、统计与目标计算、番茄钟引擎、通知、导出
- `Util.swift`：格式化、统计区间、通用组件
- `App.swift`：应用入口、侧边栏导航、菜单栏
- `ActivityViews.swift`：活动页、记录页、编辑记录
- `InsightViews.swift`：统计、目标、番茄钟
- `ManageViews.swift`：管理页和设置
