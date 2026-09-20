import Foundation
import IOKit

struct USBInputDevice:Identifiable,Hashable {
    let id:String
    let label:String
    let keyboard:Bool
}
private func drainUSBNotification(_ context:UnsafeMutableRawPointer?,_ iterator:io_iterator_t) {
    while true { let object=IOIteratorNext(iterator); if object==0 { break }; IOObjectRelease(object) }
    guard let context else { return }
    let inventory=Unmanaged<USBInventory>.fromOpaque(context).takeUnretainedValue()
    Task { @MainActor [weak inventory] in inventory?.refresh() }
}
@MainActor final class USBInventory:ObservableObject {
    @Published var devices:[USBInputDevice]=[]
    @Published var watching=false
    var changed:(()->Void)?
    private var port:IONotificationPortRef?
    private var added:io_iterator_t=0,removed:io_iterator_t=0
    init() {
        port=IONotificationPortCreate(kIOMainPortDefault)
        if let port {
            IONotificationPortSetDispatchQueue(port,DispatchQueue.main)
            let context=Unmanaged.passUnretained(self).toOpaque()
            let first=IOServiceAddMatchingNotification(port,kIOFirstMatchNotification,IOServiceMatching("IOHIDDevice"),drainUSBNotification,context,&added)
            let last=IOServiceAddMatchingNotification(port,kIOTerminatedNotification,IOServiceMatching("IOHIDDevice"),drainUSBNotification,context,&removed)
            drainUSBNotification(nil,added); drainUSBNotification(nil,removed)
            watching=first==KERN_SUCCESS && last==KERN_SUCCESS
        }
        refresh()
    }
    deinit { if added != 0 { IOObjectRelease(added) }; if removed != 0 { IOObjectRelease(removed) }; if let port { IONotificationPortDestroy(port) } }
    func refresh() {
        guard let new=Self.scan() else { return }
        if new != devices { devices=new; changed?() }
    }
    static func scan()->[USBInputDevice]? {
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOHIDDevice"),&iterator)==KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var found:[String:USBInputDevice]=[:]
        while true {
            let service=IOIteratorNext(iterator); if service==0 { break }
            defer { IOObjectRelease(service) }
            var properties:Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service,&properties,kCFAllocatorDefault,0)==KERN_SUCCESS,
                  let p=properties?.takeRetainedValue() as? [String:Any],p["Transport"] as? String == "USB",
                  (p["PrimaryUsagePage"] as? NSNumber)?.intValue==1,let usage=(p["PrimaryUsage"] as? NSNumber)?.intValue,[2,6].contains(usage) else { continue }
            let vendor=(p["VendorID"] as? NSNumber)?.uint32Value ?? 0,product=(p["ProductID"] as? NSNumber)?.uint32Value ?? 0,location=(p["LocationID"] as? NSNumber)?.uint32Value ?? 0
            guard vendor != 0,location != 0 else { continue }
            let id=String(format:"%04X:%04X:%08X:%d",vendor,product,location,usage)
            let label=(p["Product"] as? String ?? "USB 设备")+String(format:" · %04X:%04X · 接口 %08X",vendor,product,location)
            found[id]=USBInputDevice(id:id,label:label,keyboard:usage==6)
        }
        return found.values.sorted { $0.id<$1.id }
    }
}
