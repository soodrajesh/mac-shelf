import SwiftUI

/// Bridges mac-monitor's stats/purge logic into SwiftUI's Stats tab.
/// Sampling runs on a background queue so `/bin/ps` and IOKit work never
/// block the main thread (tab switches / popover UI).
final class StatsController: ObservableObject {
    @Published var cpuText = "--%"
    @Published var memText = "--%"
    @Published var memDetail = ""
    @Published var topProcessText = "Top CPU: --"
    @Published var cpuHigh = false
    @Published var memHigh = false
    @Published var netDownText = "-- KB/s"
    @Published var netUpText = "-- KB/s"
    @Published var diskReadText = "-- KB/s"
    @Published var diskWriteText = "-- KB/s"
    @Published var diskCapacityText = ""
    @Published var freeMemStatus = "Free Up Memory"
    @Published var freeMemInProgress = false

    private let queue = DispatchQueue(label: "com.rajeshsood.macshelf.stats", qos: .utility)
    private var prevCPUTicks: (busy: UInt64, total: UInt64)?
    private var prevNetBytes: (rx: UInt64, tx: UInt64)?
    private var prevDiskBytes: (read: UInt64, write: UInt64)?
    private var prevSampleTime: Date?
    private var lastTopProcessSample: Date?
    private var cachedTopProcessText = "Top CPU: --"
    private let topProcessMinInterval: TimeInterval = 10

    /// `includeDetails` — network/disk/`ps` top process (expensive). Use when
    /// the Stats tab is visible; menu-bar-only ticks need CPU/memory only.
    func refresh(includeDetails: Bool) {
        queue.async { [weak self] in
            self?.sample(includeDetails: includeDetails)
        }
    }

    private func sample(includeDetails: Bool) {
        var cpuPrev = prevCPUTicks
        let cpu = SystemStats.cpuUsage(previous: &cpuPrev)
        prevCPUTicks = cpuPrev
        let mem = SystemStats.memoryUsage()
        let cpuPct = cpu >= 0 ? cpu : 0

        let cpuText = cpu >= 0 ? String(format: "%.0f%%", cpu) : "--%"
        let memText = String(format: "%.0f%%", mem.percent)
        let memDetail = String(format: "%.0f%% used, %.0f%% pressure (%.1f / %.1f GB)",
                               mem.percent, mem.pressure, mem.usedGB, mem.totalGB)
        let cpuHigh = cpuPct >= cpuHighThreshold
        let memHigh = mem.pressure >= memPressureThreshold

        var topProcessText = cachedTopProcessText
        var netDownText = "-- KB/s"
        var netUpText = "-- KB/s"
        var diskReadText = "-- KB/s"
        var diskWriteText = "-- KB/s"
        var diskCapacityText = ""

        if includeDetails {
            let now = Date()
            if lastTopProcessSample == nil
                || now.timeIntervalSince(lastTopProcessSample!) >= topProcessMinInterval
            {
                if let top = SystemStats.topCPUProcess() {
                    topProcessText = String(format: "Top CPU: %@ (%.0f%%)", top.name, top.cpu)
                    cachedTopProcessText = topProcessText
                }
                lastTopProcessSample = now
            } else {
                topProcessText = cachedTopProcessText
            }

            let elapsed = prevSampleTime.map { now.timeIntervalSince($0) } ?? 2.0
            prevSampleTime = now

            if let net = SystemStats.networkBytes() {
                if let prev = prevNetBytes, elapsed > 0 {
                    let rxDelta = net.rx >= prev.rx ? net.rx - prev.rx : 0
                    let txDelta = net.tx >= prev.tx ? net.tx - prev.tx : 0
                    netDownText = Self.formatSpeed(Double(rxDelta) / elapsed)
                    netUpText = Self.formatSpeed(Double(txDelta) / elapsed)
                }
                prevNetBytes = net
            }

            if let disk = SystemStats.diskBytes() {
                if let prev = prevDiskBytes, elapsed > 0 {
                    let readDelta = disk.read >= prev.read ? disk.read - prev.read : 0
                    let writeDelta = disk.write >= prev.write ? disk.write - prev.write : 0
                    diskReadText = Self.formatSpeed(Double(readDelta) / elapsed)
                    diskWriteText = Self.formatSpeed(Double(writeDelta) / elapsed)
                }
                prevDiskBytes = disk
            }

            if let cap = SystemStats.diskCapacity() {
                diskCapacityText = String(format: "%.0f GB free of %.0f GB", cap.freeGB, cap.totalGB)
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cpuText = cpuText
            self.memText = memText
            self.memDetail = memDetail
            self.cpuHigh = cpuHigh
            self.memHigh = memHigh
            if includeDetails {
                self.topProcessText = topProcessText
                self.netDownText = netDownText
                self.netUpText = netUpText
                self.diskReadText = diskReadText
                self.diskWriteText = diskWriteText
                self.diskCapacityText = diskCapacityText
            }
        }
    }

    private static func formatSpeed(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1024 {
            return String(format: "%.0f KB/s", kb)
        }
        return String(format: "%.1f MB/s", kb / 1024)
    }

    func freeMemory() {
        guard !freeMemInProgress else { return }
        freeMemStatus = "Freeing memory…"
        freeMemInProgress = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: PurgeResult
            if Self.tryPasswordlessPurge() {
                result = .success
            } else {
                var interactiveResult: PurgeResult = .failed
                DispatchQueue.main.sync {
                    interactiveResult = PrivilegedPurge.runInteractive()
                }
                result = interactiveResult
            }
            DispatchQueue.main.async {
                self?.applyPurgeResult(result)
            }
        }
    }

    private func applyPurgeResult(_ result: PurgeResult) {
        switch result {
        case .success:
            freeMemStatus = "Freed!"
        case .cancelled:
            freeMemStatus = "Cancelled"
        case .failed:
            freeMemStatus = "Failed"
        }
        freeMemInProgress = false
        refresh(includeDetails: true)
        let resetDelay: TimeInterval = result == .success ? 2 : (result == .cancelled ? 1.5 : 3)
        DispatchQueue.main.asyncAfter(deadline: .now() + resetDelay) { [weak self] in
            self?.freeMemStatus = "Free Up Memory"
        }
    }

    private static func tryPasswordlessPurge() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/usr/sbin/purge"]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
