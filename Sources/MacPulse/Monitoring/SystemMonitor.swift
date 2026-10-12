#if os(macOS)
import Foundation
import Darwin
import IOKit.ps
import MacPulseCore

struct ProcessUsage: Identifiable {
    let id: Int
    let name: String
    let cpu: Double
    let residentBytes: Double
}
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
    var compressedMemory: Double? = nil
    var swapUsed: Double? = nil
    var transferredIn: Double = 0
    var transferredOut: Double = 0
    var deviceModel = "Mac"
    var processorName = "Apple Silicon / Mac processor"
    var processes: [ProcessUsage]? = nil
    var memoryRatio: Double { totalMemory > 0 ? memory / totalMemory : 0 }
    static var demo: Self { Self(cpu: 0.18, memory: 14.72e9, totalMemory: 32e9, battery: 0.82, charging: false, storageTotal: 1e12, storageFree: 438e9, upload: 84_000, download: 2_400_000, uptime: 184_000, memoryAvailable: true, storageAvailable: true, compressedMemory: 2.1e9, swapUsed: 320e6, transferredIn: 720e6, transferredOut: 260e6, deviceModel: "MacBook Pro · sample", processorName: "Apple M3 Pro · sample", processes: [ProcessUsage(id: 1, name: "Xcode", cpu: 12.4, residentBytes: 1.2e9), ProcessUsage(id: 2, name: "Logic Pro", cpu: 6.1, residentBytes: 2.3e9), ProcessUsage(id: 3, name: "Safari", cpu: 3.2, residentBytes: 720e6)]) }
}
struct PerformancePoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
    let memory: Double
    var upload: Double? = nil
    var download: Double? = nil
}
actor SystemMonitor {
    private var cached = SystemSnapshot()
    private var lastBattery: Double = -100
    private var lastStorage: Double = -100
    private var lastMemory: Double = -100
    private var interfacesBefore: [String: (UInt64, UInt64)] = [:]
    private var lastNetworkTime: Double?
    private var lastProcesses: Double = -100
    private var previousCPU: [UInt64]?
    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
    private func processSnapshot() -> [ProcessUsage]? {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,pcpu=,rss=,comm=", "-r"]
        task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
        do {
            try task.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            guard task.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
            return Array(text.split(separator: "\n").compactMap { line -> ProcessUsage? in
                let pieces = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
                guard pieces.count == 4, let pid = Int(pieces[0]), let cpu = Double(pieces[1]), let memory = Double(pieces[2]), cpu.isFinite, memory.isFinite else { return nil }
                return ProcessUsage(id: pid, name: URL(fileURLWithPath: String(pieces[3])).lastPathComponent, cpu: cpu, residentBytes: memory * 1024)
            }.prefix(8))
        } catch { return nil }
    }
    func sample(includeProcesses: Bool = false) -> SystemSnapshot {
        var value = cached
        value.cpu = nil; value.upload = nil; value.download = nil
        let tick = ProcessInfo.processInfo.systemUptime
        if cached.deviceModel == "Mac" {
            value.deviceModel = sysctlString("hw.model") ?? "Mac"
            value.processorName = sysctlString("machdep.cpu.brand_string") ?? "\(ProcessInfo.processInfo.processorCount)-core Mac processor"
        }
        value.totalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        value.uptime = ProcessInfo.processInfo.systemUptime
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if result == KERN_SUCCESS {
            let ticks = [UInt64(info.cpu_ticks.0), UInt64(info.cpu_ticks.1), UInt64(info.cpu_ticks.2), UInt64(info.cpu_ticks.3)]
            if let previousCPU { value.cpu = SampleMath.cpu(previous: previousCPU, current: ticks) }
            previousCPU = ticks
        }
        if tick - lastMemory >= 3 {
        lastMemory = tick
        value.memoryAvailable = false
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if vmResult == KERN_SUCCESS {
            value.memoryAvailable = true
            // Active + wired + compressed pages; this is an estimate, not macOS memory pressure.
            value.memory = min(value.totalMemory, Double(UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * Double(vm_kernel_page_size))
            value.compressedMemory = Double(vm.compressor_page_count) * Double(vm_kernel_page_size)
        }
        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { value.swapUsed = Double(swap.xsu_used) }
        }
        if tick - lastBattery >= 15 {
        lastBattery = tick; value.battery = nil
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let current = description[kIOPSCurrentCapacityKey] as? Double, let maximum = description[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
                value.battery = current / maximum
                value.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            }
        }
        }
        if tick - lastStorage >= 60 {
        lastStorage = tick
        value.storageAvailable = false
        if let disk = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            value.storageAvailable = disk.volumeTotalCapacity != nil && disk.volumeAvailableCapacityForImportantUsage != nil
            value.storageTotal = Double(disk.volumeTotalCapacity ?? 0)
            value.storageFree = Double(disk.volumeAvailableCapacityForImportantUsage ?? 0)
        }
        }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0, let head = interfaces {
            defer { freeifaddrs(head) }
            var cursor: UnsafeMutablePointer<ifaddrs>? = head
            var current: [String: (UInt64, UInt64)] = [:]
            while let item = cursor {
                defer { cursor = item.pointee.ifa_next }
                guard let address = item.pointee.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                      item.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                      item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                      let raw = item.pointee.ifa_data else { continue }
                let data = raw.assumingMemoryBound(to: if_data.self).pointee
                current[String(cString: item.pointee.ifa_name)] = (UInt64(data.ifi_ibytes), UInt64(data.ifi_obytes))
            }
            if let last = lastNetworkTime, tick - last < 120 {
                var incoming = 0.0, outgoing = 0.0, valid = 0
                for (name, counters) in current {
                    if let old = interfacesBefore[name], let down = SampleMath.rate(previous: old.0, current: counters.0, seconds: tick - last), let up = SampleMath.rate(previous: old.1, current: counters.1, seconds: tick - last) {
                        incoming += down; outgoing += up; valid += 1
                    }
                }
                if valid > 0 {
                    value.download = incoming; value.upload = outgoing
                    value.transferredIn += incoming * (tick - last); value.transferredOut += outgoing * (tick - last)
                }
            }
            interfacesBefore = current; lastNetworkTime = tick
        }
        if includeProcesses && tick - lastProcesses >= 15 { value.processes = processSnapshot(); lastProcesses = tick }
        cached = value
        return value
    }
}
#endif
