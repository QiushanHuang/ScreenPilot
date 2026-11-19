import Foundation
public enum InputTriggerMode:String,Codable,CaseIterable { case keyboard, mouse, either, both }
public struct InputPresence:Equatable,Sendable {
    public var keyboard:Bool
    public var mouse:Bool
    public init(keyboard:Bool,mouse:Bool) { self.keyboard=keyboard; self.mouse=mouse }
}
public struct InputArrivalGate {
    private var previous:Set<String>?
    private var pending=Set<String>()
    private var changedAt:TimeInterval=0
    private var lastFire:TimeInterval = -100
    public init() {}
    public mutating func reset() { previous=nil; pending.removeAll() }

    public static func matches(_ candidate:String, selection:String, anyPort:Bool) -> Bool {
        guard !selection.isEmpty else { return false }
        if candidate == selection { return true }
        let a=candidate.split(separator:":"), b=selection.split(separator:":")
        return anyPort && a.count==4 && b.count==4 && a[0]==b[0] && a[1]==b[1] && a[3]==b[3]
    }

    public mutating func observe(_ now:InputPresence,mode:InputTriggerMode,enabled:Bool,time:TimeInterval)->Bool {
        observe(keyboards:now.keyboard ? ["keyboard"] : [], mice:now.mouse ? ["mouse"] : [],
                mode:mode,enabled:enabled,time:time)
    }

    public mutating func observe(keyboards:Set<String>, mice:Set<String>, mode:InputTriggerMode, enabled:Bool,time:TimeInterval)->Bool {
        let eligible:Set<String>
        switch mode {
        case .keyboard: eligible=keyboards
        case .mouse: eligible=mice
        case .either: eligible=keyboards.union(mice)
        case .both: eligible=keyboards.isEmpty || mice.isEmpty ? [] : keyboards.union(mice)
        }
        let old=previous
        previous=eligible
        guard enabled, let old else { pending.removeAll(); return false }
        pending.formIntersection(eligible)
        let arrivals=eligible.subtracting(old)
        if !arrivals.isEmpty { pending.formUnion(arrivals); changedAt=time }
        guard !pending.isEmpty,time-changedAt>=1 else { return false }
        pending.removeAll()
        guard time-lastFire>=5 else { return false }
        lastFire=time;return true
    }
}
