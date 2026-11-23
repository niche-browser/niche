import NicheCore
import Testing

/// The universal app names the slice it runs as (scenario.sh's NICHE_ARCH check reads it).
struct RunningCPUTests {
    @Test func eachSliceHasItsName() {
        #expect(RunningCPU.name(arm64: true, translated: false) == "arm64")
        #expect(RunningCPU.name(arm64: false, translated: false) == "x86_64")
        #expect(RunningCPU.name(arm64: false, translated: true) == "x86_64 (Rosetta)")
    }

    @Test func thisProcessHasOne() {
        #expect(["arm64", "x86_64", "x86_64 (Rosetta)"].contains(RunningCPU.current))
    }
}
