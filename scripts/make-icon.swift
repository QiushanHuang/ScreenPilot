import AppKit
let destination=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:destination,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let s=CGFloat(size)/1024
    let transform=NSAffineTransform(); transform.scale(by:s); transform.concat()
    NSColor(calibratedRed:0.07,green:0.10,blue:0.13,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:28,y:28,width:968,height:968),xRadius:214,yRadius:214).fill()
    // Original ScreenPilot mark: paired displays and a directional cursor.
    let mint=NSColor(calibratedRed:0.47,green:0.91,blue:0.77,alpha:1)
    func rounded(_ r:NSRect,_ radius:CGFloat,_ color:NSColor) {
        color.setFill(); NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius).fill()
    }
    rounded(NSRect(x:360,y:430,width:450,height:330),44,NSColor(calibratedRed:0.21,green:0.46,blue:0.43,alpha:1))
    rounded(NSRect(x:388,y:458,width:394,height:274),22,NSColor(calibratedRed:0.07,green:0.10,blue:0.13,alpha:1))
    rounded(NSRect(x:180,y:300,width:540,height:370),48,mint)
    rounded(NSRect(x:210,y:330,width:480,height:310),22,NSColor(calibratedRed:0.07,green:0.10,blue:0.13,alpha:1))
    rounded(NSRect(x:424,y:226,width:52,height:80),12,mint)
    rounded(NSRect(x:338,y:210,width:224,height:30),15,mint)
    mint.setFill()
    let pilot=NSBezierPath();pilot.move(to:NSPoint(x:403,y:553));pilot.line(to:NSPoint(x:570,y:481));pilot.line(to:NSPoint(x:490,y:453));pilot.line(to:NSPoint(x:458,y:377));pilot.close();pilot.fill()
    NSGraphicsContext.restoreGraphicsState()
    let names: [String]
    switch size { case 16:names=["icon_16x16"]; case 32:names=["icon_16x16@2x","icon_32x32"]; case 64:names=["icon_32x32@2x"]; case 128:names=["icon_128x128"]; case 256:names=["icon_128x128@2x","icon_256x256"]; case 512:names=["icon_256x256@2x","icon_512x512"]; default:names=["icon_512x512@2x"] }
    for name in names { try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination).appendingPathComponent(name+".png")) }
}
