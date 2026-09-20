import SwiftUI
import DisplayCore

struct RecoveryPicker:View {
    @Binding var mode:OutputRecoveryMode
    var body:some View {
        Picker("自动恢复",selection:$mode) {
            Text("15 秒后恢复").tag(OutputRecoveryMode.preview)
            Text("不自动恢复").tag(OutputRecoveryMode.manual)
        }.pickerStyle(.segmented).frame(maxWidth:320)
    }
}
struct OutputPresetPanel:View {
    @ObservedObject var store:DisplayStore
    @State private var editing=false
    @State private var editingID:UUID?
    @State private var name=""
    @State private var selected=Set<String>()
    @State private var recovery=OutputRecoveryMode.manual
    private var busy:Bool { store.scanning || store.connectionBusy || store.hostSwitchBusy }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                VStack(alignment:.leading,spacing:6) {
                    Text("常用组合，一键执行").font(.title3.weight(.semibold))
                    Text("保存常用的关屏组合，执行时保留至少一块输出屏幕。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { openEditor(nil) } label: { Label("新建预设",systemImage:"plus") }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            HStack(spacing:16) {
                Image(systemName:"laptopcomputer").font(.system(size:28)).foregroundStyle(AppPalette.accent).frame(width:48)
                VStack(alignment:.leading,spacing:6) {
                    Text("仅用内置屏").font(.headline)
                    Text("停止所有外屏输出 · \(store.outputRecovery.automaticallyRestores ? "15 秒后恢复" : "手动恢复")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("执行") { Task { await store.onlyBuiltIn() } }.buttonStyle(.bordered).controlSize(.large).disabled(busy || !store.displays.contains { $0.builtIn && !$0.isDisconnected })
            }.padding(22).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:16))
            if store.outputPresets.isEmpty {
                ContentUnavailableView("还没有自定义预设",systemImage:"rectangle.stack.badge.plus",description:Text("点击右上角“新建预设”，选择要关闭的屏幕。"))
            } else {
                ForEach(store.outputPresets) { preset in
                    HStack(spacing:16) {
                        Image(systemName:"rectangle.stack").font(.title2).foregroundStyle(AppPalette.accent).frame(width:48)
                        VStack(alignment:.leading,spacing:6) {
                            Text(preset.name).font(.headline)
                            Text("停止 \(preset.targets.count) 块屏幕 · \(preset.recovery.automaticallyRestores ? "15 秒后恢复" : "手动恢复")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("执行") { Task { await store.applyOutputPreset(preset) } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                        Menu {
                            Button("编辑预设…") { openEditor(preset) }
                            Button("删除预设",role:.destructive) { store.deleteOutputPreset(preset.id) }
                        } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("预设选项")
                    }.padding(22).background(AppPalette.surface,in:RoundedRectangle(cornerRadius:16))
                }
            }
        }.sheet(isPresented:$editing) { editor }
    }
    private func openEditor(_ preset:OutputPreset?) {
        editingID=preset?.id;name=preset?.name ?? "";selected=Set(preset?.targets.map(\.uuid) ?? []);recovery=preset?.recovery ?? .manual;editing=true
    }
    private var editor:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack { Text(editingID==nil ? "新建关屏预设" : "编辑关屏预设").font(.title2.bold());Spacer() }
            TextField("预设名称",text:$name).textFieldStyle(.roundedBorder)
            Text("选择要停止输出的屏幕").font(.headline)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    ForEach(store.displays) { d in
                        Toggle(isOn:Binding(get:{selected.contains(d.key.uuid)},set:{ if $0 { selected.insert(d.key.uuid) } else { selected.remove(d.key.uuid) } })) {
                            HStack { Image(systemName:d.builtIn ? "laptopcomputer" : "display").frame(width:28);Text(d.title);Spacer();Text(d.builtIn ? "内置" : "外置").font(.caption).foregroundStyle(.secondary) }
                        }.toggleStyle(.checkbox)
                    }
                    if !selected.isSubset(of:Set(store.displays.map { $0.key.uuid })) {
                        Text("原预设含当前缺失的屏幕，请重新选择。").font(.caption).foregroundStyle(.orange)
                        Button("清除缺失屏幕") { selected.formIntersection(Set(store.displays.map { $0.key.uuid })) }
                    }
                }.padding(2)
            }.frame(maxHeight:240)
            Divider()
            RecoveryPicker(mode:$recovery)
            Text("不自动恢复时将保持停止输出，直到手动恢复或退出应用。保存不会立即关屏。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer();Button("取消") { editing=false }.keyboardShortcut(.cancelAction)
                Button("保存预设") {
                    if store.saveOutputPreset(name:name,uuids:selected,recovery:recovery,replacing:editingID) { editing=false }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || !selected.isSubset(of:Set(store.displays.map { $0.key.uuid })) || name.trimmingCharacters(in:.whitespaces).isEmpty || busy)
            }
        }.padding(28).frame(width:520).tint(AppPalette.accent)
    }
}
