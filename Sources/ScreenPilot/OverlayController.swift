import AppKit
import SwiftUI
import DisplayCore

private final class ShadePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class OverlayController {
    private var windows: [UInt32:NSPanel] = [:]
    private var badges: [NSPanel] = []
    private var identifyTask: Task<Void,Never>?
    var count: Int { windows.count }
    func update(_ display: DisplayModel,restore: @escaping ()->Void,keep: @escaping ()->Void) {
        guard display.shade.opacity>0 else { windows.removeValue(forKey:display.id)?.close(); return }
        let panel=windows[display.id] ?? makePanel(frame:display.frame)
        windows[display.id]=panel
        panel.setFrame(display.frame,display:true)
        panel.ignoresMouseEvents = !display.shade.blackedOut
        panel.alphaValue=display.shade.opacity
        panel.contentView=NSHostingView(rootView:BlackoutSurface(number:display.number,blackedOut:display.shade.blackedOut,preview:display.preview,restore:restore,keep:keep))
        panel.orderFrontRegardless()
    }
    private func makePanel(frame: CGRect) -> NSPanel {
        let p=ShadePanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.backgroundColor = .black; p.isOpaque=true; p.hasShadow=false
        p.level=NSWindow.Level(rawValue:NSWindow.Level.screenSaver.rawValue+1)
        p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        p.isReleasedWhenClosed=false; p.hidesOnDeactivate=false
        return p
    }
    func removeMissing(_ ids: Set<UInt32>) { for key in Array(windows.keys) where !ids.contains(key) { windows.removeValue(forKey:key)?.close() } }
    func removeAll() { windows.values.forEach { $0.close() }; windows.removeAll(); badges.forEach { $0.close() }; badges.removeAll() }
    func identify(_ displays: [DisplayModel]) {
        identifyTask?.cancel(); badges.forEach { $0.close() }; badges.removeAll()
        for d in displays {
            let rect=CGRect(x:d.frame.midX-115,y:d.frame.midY-85,width:230,height:170)
            let p=makePanel(frame:rect); p.backgroundColor = .clear; p.isOpaque=false; p.ignoresMouseEvents=true
            p.level=NSWindow.Level(rawValue:NSWindow.Level.screenSaver.rawValue+2)
            p.contentView=NSHostingView(rootView:VStack(spacing:6) {
                Text("\(d.number)").font(.system(size:68,weight:.bold,design:.rounded))
                Text(d.title).font(.system(size:16,weight:.medium)).lineLimit(1)
                Text(d.isMain ? "主显示器" : "显示器").font(.caption).foregroundStyle(.secondary)
            }.foregroundStyle(.white).frame(width:230,height:170).background(.black.opacity(0.85),in:RoundedRectangle(cornerRadius:24)))
            p.orderFrontRegardless(); badges.append(p)
        }
        identifyTask=Task { [weak self] in
            do { try await Task.sleep(nanoseconds:3_000_000_000) } catch { return }
            self?.badges.forEach { $0.close() }; self?.badges.removeAll()
        }
    }
}
private struct BlackoutSurface: View {
    let number: Int
    let blackedOut: Bool
    let preview: Bool
    let restore: ()->Void
    let keep: ()->Void
    var body: some View {
        ZStack {
            Color.black.contentShape(Rectangle()).onTapGesture { if blackedOut { restore() } }
            if preview {
                VStack(spacing:12) {
                    Image(systemName:"moon.fill").font(.system(size:28)).foregroundStyle(.mint)
                    Text("屏幕 \(number) 已黑屏").font(.title2.weight(.semibold))
                    Text("12 秒后自动恢复。保持后，点击屏幕即可恢复。").font(.callout).foregroundStyle(.secondary)
                    HStack(spacing:14) {
                        Button("恢复屏幕",action:restore).buttonStyle(.bordered)
                        Button("保持黑屏",action:keep).buttonStyle(.borderedProminent).tint(.mint)
                    }
                    Text("全部恢复：⌃⌥⌘ R").font(.caption).foregroundStyle(.secondary)
                }.padding(28).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:22))
            }
        }.preferredColorScheme(.dark).ignoresSafeArea()
    }
}
