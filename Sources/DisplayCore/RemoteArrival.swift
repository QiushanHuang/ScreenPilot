import Foundation
public struct RemoteArrivalGate {
    private var seen:String?
    public init() {}
    public mutating func accept(id:String?,timestamp:Double?,now:Double)->Bool {
        guard let id,!id.isEmpty,let timestamp else { return false }
        if seen==nil { seen=id; return false }
        guard seen != id else { return false }
        seen=id
        return timestamp<=now+2 && now-timestamp<=8
    }
}
