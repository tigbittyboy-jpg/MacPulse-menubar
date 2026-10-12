#if os(macOS)
import Foundation
import Darwin
import IOKit.ps

struct SystemSnapshot {
    var cpu: Double? = nil
    var memory: Double = 0
    var totalMemory: Double = 0
    var battery: Double? = nil
    var charging = false
    var storageTotal: Double = 0
    var storageFree: Double = 0
    var upload: Double? = nil
    var download: Double? = nil
    var uptime: Double = 0
    var memoryAvailable = false
    var storageAvailable = false
    var memoryRatio: Double { totalMemory > 0 ? memory / totalMemory : 0 }
    static var demo: Self { Self(cpu: 0.18, memory: 14.72e9, totalMemory: 32e9, battery: 0.82, charging: false, storageTotal: 1e12, storageFree: 438e9, upload: 84_000, download: 2_400_000, uptime: 184_000, memoryAvailable: true, storageAvailable: true) }
}
struct PerformancePoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
}
final class SystemMonitor {
    private var previousCPU: [UInt64]?
    private var previousNetwork: (Date, UInt64, UInt64)?
    func sample() -> SystemSnapshot {
        var value = SystemSnapshot()
        value.totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        value.uptime = ProcessInfo.processInfo.systemUptime
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if result == KERN_SUCCESS {
            let ticks = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
            if let previousCPU, zip(ticks, previousCPU).allSatisfy({ $0 >= $1 }) {
                let delta = zip(ticks, previousCPU).map { $0 - $1 }
                let total = delta.reduce(0, +)
                if total > 0 { value.cpu = 1 - Double(delta[2]) / Double(total) }
            }
            previousCPU = ticks
        }
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if vmResult == KERN_SUCCESS {
            value.memoryAvailable = true
            // Active + wired + compressed pages; this is an estimate, not macOS memory pressure.
            value.memory = min(value.totalMemory, Double(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * Double(vm_kernel_page_size))
        }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let current = description[kIOPSCurrentCapacityKey] as? Double, let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
                value.battery = current / maximum
                value.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            }
        }
        if let disk = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            value.storageAvailable = disk.volumeTotalCapacity != nil && disk.volumeAvailableCapacityForImportantUsage != nil
            value.storageTotal = Double(disk.volumeTotalCapacity ?? 0)
            value.storageFree = Double(disk.volumeAvailableCapacityForImportantUsage ?? 0)
        }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0, let head = interfaces {
            defer { freeifaddrs(head) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = head
            var inbound: UInt64 = 0, outbound: UInt64 = 0
            while let item = cursor {
                defer { cursor = item.pointee.ifa_next }
                guard let address = item.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                      item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                      item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                      let raw = item.pointee.ifa_data else { continue }
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                inbound += UInt64(data.ifi_ibytes); outbound += UInt64(data.ifi_obytes)
            }
            let now = Date()
            if let (last, oldIn, oldOut) = previousNetwork, inbound >= oldIn, outbound >= oldOut {
                let seconds = now.timeIntervalSince(last)
                if seconds > 0 { value.download = Double(inbound - oldIn) / seconds; value.upload = Double(outbound - oldOut) / seconds }
            }
            previousNetwork = (now, inbound, outbound)
        }
        return value
    }
}
#endif
