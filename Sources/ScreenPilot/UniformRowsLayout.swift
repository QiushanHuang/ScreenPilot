import SwiftUI
import DisplayCore

/// Cards in a row occupy the same measured height; no empty rectangle below a shorter card.
struct UniformRowsLayout:Layout {
    var minimumWidth:CGFloat=360
    var spacing:CGFloat=16
    private func metrics(_ proposal:ProposedViewSize,_ subviews:Subviews)->(width:CGFloat,columns:Int,heights:[CGFloat]) {
        let sizing=CardGridMetrics(proposedWidth:proposal.width.map(Double.init),itemCount:subviews.count,minimumWidth:Double(minimumWidth),spacing:Double(spacing))
        let width=CGFloat(sizing.width),columns=sizing.columns,cell=CGFloat(sizing.cellWidth)
        var heights:[CGFloat]=[]
        for index in subviews.indices {
            let row=index/columns
            if heights.count<=row { heights.append(0) }
            heights[row]=max(heights[row],subviews[index].sizeThatFits(ProposedViewSize(width:cell,height:nil)).height)
        }
        return (width,columns,heights)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let m=metrics(proposal,subviews)
        return CGSize(width:m.width,height:m.heights.reduce(0,+)+CGFloat(max(0,m.heights.count-1))*spacing)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let m=metrics(ProposedViewSize(width:bounds.width,height:nil),subviews)
        let width=max(0,(bounds.width-spacing*CGFloat(m.columns-1))/CGFloat(m.columns))
        var y=bounds.minY
        for (row,height) in m.heights.enumerated() {
            for column in 0..<m.columns {
                let index=row*m.columns+column
                if index<subviews.count { subviews[index].place(at:CGPoint(x:bounds.minX+CGFloat(column)*(width+spacing),y:y),anchor:.topLeading,proposal:ProposedViewSize(width:width,height:height)) }
            }
            y+=height+spacing
        }
    }
}
