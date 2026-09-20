import Foundation
public enum InputTriggerMode:String,Codable,CaseIterable { case keyboard, mouse, either, both }
public struct InputPresence:Equatable,Sendable {
    public var keyboard:Bool
    public var mouse:Bool
    public init(keyboard:Bool,mouse:Bool) { self.keyboard=keyboard; self.mouse=mouse }
}
public struct InputArrivalGate {
    private var previous:InputPresence?
    private var pending=false
    private var changedAt:TimeInterval=0
    private var lastFire:TimeInterval = -100
    public init() {}
    public mutating func reset() { previous=nil; pending=false }
    public mutating func observe(_ now:InputPresence,mode:InputTriggerMode,enabled:Bool,time:TimeInterval)->Bool {
        guard enabled else { previous=now; pending=false; return false }
        guard let old=previous else { previous=now; return false }
        if old != now {
            let k = !old.keyboard && now.keyboard
            let m = !old.mouse && now.mouse
            switch mode {
            case .keyboard: pending=k
            case .mouse: pending=m
            case .either: pending=k || m
            case .both: pending=now.keyboard && now.mouse && (k || m)
            }
            changedAt=time; previous=now; return false
        }
        guard pending,time-changedAt>=1 else { return false }
        pending=false
        guard time-lastFire>=5 else { return false }
        lastFire=time; return true
    }
}
