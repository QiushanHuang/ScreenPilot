import SwiftUI
import AppKit

enum AppPalette {
    static let accent=Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(calibratedRed:0.47,green:0.91,blue:0.77,alpha:1)
        : NSColor(calibratedRed:0.05,green:0.43,blue:0.34,alpha:1)
    })
    static let canvas=Color(nsColor:.windowBackgroundColor)
    static let surface=Color(nsColor:.controlBackgroundColor)
    static let sidebar=Color(nsColor:NSColor(name:nil) { appearance in
        appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        ? NSColor(calibratedRed:0.085,green:0.10,blue:0.12,alpha:1)
        : NSColor(calibratedRed:0.925,green:0.95,blue:0.94,alpha:1)
    })
    static let border=Color(nsColor:.separatorColor).opacity(0.35)
}
