import NicheCore
import Testing

/// "Quit Niche?" is asked once per quit (13 Nov 2026: the Dock's Quit asked twice).
struct QuitConfirmationTests {
    @Test func aQuitIsAskedAboutOnce() {
        var quit = QuitConfirmation()
        #expect(quit.asks(warnBeforeQuitting: true, relaunching: false))
        quit.answered(quit: true)
        // AppKit's Apple Event handler asked; `terminate:` asks the delegate again.
        #expect(!quit.asks(warnBeforeQuitting: true, relaunching: false))
    }

    @Test func cancelAsksAgainNextTime() {
        var quit = QuitConfirmation()
        quit.answered(quit: false)
        #expect(quit.asks(warnBeforeQuitting: true, relaunching: false))
    }

    @Test func theSettingAndARelaunchNeverAsk() {
        let quit = QuitConfirmation()
        #expect(!quit.asks(warnBeforeQuitting: false, relaunching: false))
        #expect(!quit.asks(warnBeforeQuitting: true, relaunching: true))
    }
}
