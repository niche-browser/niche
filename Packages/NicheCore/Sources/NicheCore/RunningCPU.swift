import Foundation

/// Which slice of the universal app is running, for niche.log's first line: arm64, or x86_64 on
/// an Intel Mac or under Rosetta (`NICHE_ARCH=x86_64` scenarios check it).
public enum RunningCPU {
    public static func name(arm64: Bool, translated: Bool) -> String {
        arm64 ? "arm64" : translated ? "x86_64 (Rosetta)" : "x86_64"
    }

    public static var current: String {
        #if arch(arm64)
        return name(arm64: true, translated: false)
        #else
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        return name(arm64: false, translated: rosetta)
        #endif
    }
}
