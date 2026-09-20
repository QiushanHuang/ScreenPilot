import Foundation
public struct LayoutReadiness {
    private var previous:[TopologyEntry]?
    private var stableSince:TimeInterval=0
    public init() {}
    public mutating func observe(_ displays:[TopologyEntry],target:String,busy:Bool,uptime:TimeInterval)->Bool {
        guard !busy,let display=displays.first(where: { $0.uuid==target }),display.active != 0,
              display.width>0,display.height>0,display.mode>0 else { previous=nil; return false }
        let ordered=displays.sorted { $0.uuid<$1.uuid }
        if previous != ordered { previous=ordered; stableSince=uptime; return false }
        return uptime-stableSince>=1
    }
}
