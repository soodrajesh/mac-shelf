import Cocoa
import Darwin
import IOKit
import IOKit.storage

// MARK: - System stats
//
// CPU/memory/topProcess ported verbatim from mac-monitor/main.swift.
// Network and disk I/O added for MacShelf.

enum SystemStats {
    /// Reads the cumulative-since-boot CPU tick counters, summed across all cores.
    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCpus: natural_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpus, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS else { return nil }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<Int32>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for i in 0..<Int(numCpus) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)].magnitude)
            let system = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)].magnitude)
            let idle = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)].magnitude)
            let nice = UInt64(cpuInfo[offset + Int(CPU_STATE_NICE)].magnitude)
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return (busy, total)
    }

    /// Instantaneous CPU load (0–100%) computed from the delta between the
    /// previous and current tick snapshots. Cumulative counters alone report
    /// the lifetime average, which barely moves — the delta is the real load.
    static func cpuUsage(previous: inout (busy: UInt64, total: UInt64)?) -> Double {
        guard let now = cpuTicks() else { return -1 }
        defer { previous = now }
        guard let prev = previous else { return -1 } // first sample: prime only
        let busyDelta = now.busy >= prev.busy ? now.busy - prev.busy : 0
        let totalDelta = now.total >= prev.total ? now.total - prev.total : 0
        guard totalDelta > 0 else { return -1 }
        return (Double(busyDelta) / Double(totalDelta)) * 100.0
    }

    static func memoryUsage() -> (usedGB: Double, totalGB: Double, percent: Double, pressure: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0, 0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let totalPhysical = ProcessInfo.processInfo.physicalMemory
        let used = active + inactive + wired + compressed

        let gb = 1024.0 * 1024.0 * 1024.0
        let usedGB = Double(used) / gb
        let totalGB = Double(totalPhysical) / gb
        let percent = totalGB > 0 ? (usedGB / totalGB) * 100.0 : 0
        // Memory pressure ≈ non-reclaimable memory (wired + compressed) over total.
        // This tracks real strain, unlike raw "used" which stays high from caching.
        let strain = wired + compressed
        let pressure = totalPhysical > 0 ? (Double(strain) / Double(totalPhysical)) * 100.0 : 0

        return (usedGB, totalGB, percent, pressure)
    }

    /// Returns the name and CPU% of the single top CPU-consuming process.
    static func topCPUProcess() -> (name: String, cpu: Double)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pcpu,comm", "-r"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else { return nil }
        // First line is the header; second is the top process.
        let cols = lines[1].trimmingCharacters(in: .whitespaces)
        guard let spaceIdx = cols.firstIndex(of: " ") else { return nil }
        let cpuStr = String(cols[..<spaceIdx])
        let name = String(cols[cols.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
        let cpu = Double(cpuStr) ?? 0
        return (name, cpu)
    }

    /// Cumulative-since-boot bytes in/out, summed across all active
    /// (up, non-loopback) interfaces via `getifaddrs`'s link-layer entries —
    /// the same counters `netstat -ib` reads, but read directly with no
    /// subprocess. Delta this over time (same pattern as `cpuUsage`) for a
    /// live throughput reading.
    static func networkBytes() -> (rx: UInt64, tx: UInt64)? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs> = firstAddr
        while true {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp, !isLoopback, ifa.ifa_addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                rx += UInt64(networkData.ifi_ibytes)
                tx += UInt64(networkData.ifi_obytes)
            }
            guard let next = ifa.ifa_next else { break }
            ptr = next
        }
        return (rx, tx)
    }

    /// Cumulative-since-mount read/write bytes, summed across all
    /// `IOBlockStorageDriver` instances (what `iostat` itself reads) — the
    /// same delta-over-time pattern as CPU/network gives live disk
    /// throughput without shelling out to `iostat` (which needs a blocking
    /// ~1s wait between samples to report a rate instead of a lifetime average).
    static func diskBytes() -> (read: UInt64, write: UInt64)? {
        let matching = IOServiceMatching("IOBlockStorageDriver")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }
            if let read = stats["Bytes (Read)"] as? UInt64 { totalRead += read }
            if let write = stats["Bytes (Write)"] as? UInt64 { totalWrite += write }
        }
        return (totalRead, totalWrite)
    }

    /// Free/total capacity of the boot volume, via `statfs` on "/".
    static func diskCapacity() -> (freeGB: Double, totalGB: Double)? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }
        let gb = 1024.0 * 1024.0 * 1024.0
        let blockSize = Double(fs.f_bsize)
        let freeGB = (Double(fs.f_bavail) * blockSize) / gb
        let totalGB = (Double(fs.f_blocks) * blockSize) / gb
        return (freeGB, totalGB)
    }
}

// MARK: - Two-line status image

let cpuHighThreshold: Double = 90.0     // CPU load %
let memPressureThreshold: Double = 75.0 // memory pressure %

/// Renders the stacked two-line readout as an attributed string for the status
/// button (native highlight pill like Weather). `cpuHigh`/`memHigh` turn the
/// respective value red.
func makeStatusAttributedTitle(cpuValue: String, cpuHigh: Bool,
                             memValue: String, memHigh: Bool,
                             isDark: Bool) -> NSAttributedString {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
    let normal = isDark ? NSColor.labelColor : NSColor.labelColor
    let red = NSColor.systemRed

    func line(_ label: String, _ value: String, high: Bool) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "\(label) ", attributes: [.font: font, .foregroundColor: normal])
        s.append(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: high ? red : normal]))
        return s
    }

    let combined = NSMutableAttributedString()
    combined.append(line("CPU", cpuValue, high: cpuHigh))
    combined.append(NSAttributedString(string: "\n"))
    combined.append(line("MEM", memValue, high: memHigh))

    let para = NSMutableParagraphStyle()
    para.lineSpacing = -1
    para.alignment = .center
    combined.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: combined.length))
    return combined
}

/// Bitmap fallback (unused by MacShelf menu bar; kept for reference tooling).
func makeStatusImage(cpuValue: String, cpuHigh: Bool,
                      memValue: String, memHigh: Bool,
                      isDark: Bool) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)
    let normal = isDark ? NSColor.white : NSColor.black
    let red = NSColor.systemRed

    func line(_ label: String, _ value: String, high: Bool) -> NSAttributedString {
        let s = NSMutableAttributedString(string: "\(label) ", attributes: [.font: font, .foregroundColor: normal])
        s.append(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: high ? red : normal]))
        return s
    }

    let cpuLine = line("CPU", cpuValue, high: cpuHigh)
    let memLine = line("MEM", memValue, high: memHigh)

    let height = NSStatusBar.system.thickness
    let width = ceil(max(cpuLine.size().width, memLine.size().width)) + 2
    let lineH = ceil(max(cpuLine.size().height, memLine.size().height))
    let gap: CGFloat = 0
    let blockH = lineH * 2 + gap
    let bottomY = (height - blockH) / 2      // vertical centering
    let topY = bottomY + lineH + gap

    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
        memLine.draw(at: NSPoint(x: 1, y: bottomY))
        cpuLine.draw(at: NSPoint(x: 1, y: topY))
        return true
    }
    image.isTemplate = false
    return image
}
