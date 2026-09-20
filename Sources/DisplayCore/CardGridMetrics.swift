import Foundation
public struct CardGridMetrics {
    public let width:Double
    public let columns:Int
    public let cellWidth:Double
    public init(proposedWidth:Double?,itemCount:Int,minimumWidth:Double=360,spacing:Double=16) {
        let fallback=minimumWidth*Double(min(2,max(1,itemCount)))+spacing*Double(min(1,max(0,itemCount-1)))
        width=proposedWidth.flatMap { $0.isFinite ? max(minimumWidth,$0) : nil } ?? fallback
        let possible=min(Double(max(1,itemCount)),max(1,(width+spacing)/(minimumWidth+spacing)))
        columns=Int(possible)
        cellWidth=max(0,(width-spacing*Double(columns-1))/Double(columns))
    }
}
