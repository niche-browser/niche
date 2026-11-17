import JavaScriptCore
import NicheCore
import Testing

/// The page script that notices fingerprinting, run in JavaScriptCore against stand-ins for the
/// few browser objects it wraps.
struct PrivacyProbeScriptTests {
    private static let fakeWindow = #"""
    var window = this; window.top = window;
    var reports = [];
    class CustomEvent { constructor(type, init) { this.type = type; this.detail = init.detail; } }
    var listeners = {};
    class EventTarget {
      dispatchEvent(e) { if (e.type === 'chanp') reports.push(e.detail); (listeners[e.type] || []).forEach(f => f(e)); }
      addEventListener(type, f) { (listeners[type] = listeners[type] || []).push(f); }
    }
    // A page that replaces the global afterwards must not see the reports.
    function dispatchEvent(e) { reports.push('leaked'); }
    class HTMLCanvasElement { toDataURL() { return 'data:'; } toBlob() {} }
    class CanvasRenderingContext2D {
      constructor(canvas) { this.canvas = canvas; this.font = '10px sans-serif'; }
      fillText() {} strokeText() {} getImageData() { return {}; } measureText() { return { width: 7 }; }
    }
    class WebGLRenderingContext { getParameter(p) { return 'value ' + p; } }
    class BaseAudioContext { createOscillator() { return {}; } }
    class OfflineAudioContext extends BaseAudioContext { startRendering() { return 'rendered'; } }
    class AudioContext extends BaseAudioContext {}
    // A class declaration is not a property of the global object; in a browser these are.
    Object.assign(window, { EventTarget, CustomEvent, HTMLCanvasElement, CanvasRenderingContext2D, WebGLRenderingContext, BaseAudioContext, OfflineAudioContext, AudioContext });
    """#

    private func page() throws -> JSContext {
        let js = try #require(JSContext())
        js.exceptionHandler = { _, e in Issue.record("script threw: \(e?.toString() ?? "?")") }
        js.evaluateScript(Self.fakeWindow)
        js.evaluateScript(PrivacyProbeScript.script(event: "chanp"))
        return js
    }

    private func reports(_ js: JSContext) -> [String] {
        (js.evaluateScript("reports")?.toArray() as? [String]) ?? []
    }

    @Test func textDrawnOnACanvasAndReadBackIsAProbe() throws {
        let js = try page()
        js.evaluateScript("var c = new HTMLCanvasElement(), ctx = new CanvasRenderingContext2D(c); ctx.fillText('Cwm fjordbank', 2, 2); var out = c.toDataURL();")
        #expect(reports(js).map { $0.split(separator: " ").first.map(String.init) } == ["canvas"])
        // The page still gets what the browser gave.
        #expect(js.evaluateScript("out")?.toString() == "data:")
    }

    @Test func aPictureReadBackIsNot() throws {
        let js = try page()
        js.evaluateScript("var c = new HTMLCanvasElement(), ctx = new CanvasRenderingContext2D(c); c.toDataURL(); ctx.getImageData(0, 0, 1, 1); c.toBlob();")
        #expect(reports(js).isEmpty)
    }

    @Test func askingForTheGraphicsChipIsAProbe() throws {
        let js = try page()
        js.evaluateScript("var gl = new WebGLRenderingContext(); gl.getParameter(3379); var name = gl.getParameter(37446);")
        #expect(reports(js).count == 1)
        #expect(reports(js).first?.hasPrefix("webgl") == true)
        #expect(js.evaluateScript("name")?.toString() == "value 37446")
    }

    @Test func soundRenderedOffScreenFromAnOscillatorIsAProbe() throws {
        let js = try page()
        // Playing a tone out loud is not.
        js.evaluateScript("new AudioContext().createOscillator(); new OfflineAudioContext().startRendering();")
        #expect(reports(js).isEmpty)
        js.evaluateScript("var o = new OfflineAudioContext(); o.createOscillator(); var r = o.startRendering();")
        #expect(reports(js).first?.hasPrefix("audio") == true)
        #expect(js.evaluateScript("r")?.toString() == "rendered")
    }

    @Test func measuringTextInDozensOfFontsIsAProbe() throws {
        let js = try page()
        js.evaluateScript("var ctx = new CanvasRenderingContext2D(new HTMLCanvasElement()); for (var i = 0; i < \(PrivacyProbeScript.fontThreshold - 1); i++) { ctx.font = '12px f' + i; ctx.measureText('mmm'); }")
        #expect(reports(js).isEmpty)
        js.evaluateScript("ctx.font = '12px last'; var w = ctx.measureText('mmm').width; ctx.font = '12px more'; ctx.measureText('mmm');")
        #expect(reports(js).count == 1)
        #expect(reports(js).first?.hasPrefix("fonts") == true)
        #expect(js.evaluateScript("w")?.toInt32() == 7)
    }

    @Test func aProbeIsReportedAFewTimesNotEveryTime() throws {
        let js = try page()
        js.evaluateScript("var gl = new WebGLRenderingContext(); for (var i = 0; i < 50; i++) gl.getParameter(37445);")
        #expect(reports(js).count == 3)
    }

    /// Every page has the watch, so a method it stands in front of must look as it did: a site
    /// that checks its browser for tampering sees the same name, length and place, and no code.
    @Test func aWatchedMethodLooksAsItDid() throws {
        let js = try #require(JSContext())
        js.exceptionHandler = { _, e in Issue.record("script threw: \(e?.toString() ?? "?")") }
        js.evaluateScript(Self.fakeWindow)
        js.evaluateScript("var after, before = Object.getOwnPropertyDescriptor(WebGLRenderingContext.prototype, 'getParameter'), keys = Object.keys(window).length;")
        js.evaluateScript(PrivacyProbeScript.script(event: "chanp"))
        js.evaluateScript("after = Object.getOwnPropertyDescriptor(WebGLRenderingContext.prototype, 'getParameter');")
        #expect(js.evaluateScript("after.value !== before.value")?.toBool() == true)
        #expect(js.evaluateScript("after.value.name")?.toString() == "getParameter")
        #expect(js.evaluateScript("after.value.length === before.value.length")?.toBool() == true)
        #expect(js.evaluateScript("after.enumerable === before.enumerable && after.writable === before.writable && after.configurable === before.configurable")?.toBool() == true)
        let printed = js.evaluateScript("Function.prototype.toString.call(after.value)")?.toString() ?? ""
        #expect(!printed.contains("Reflect") && !printed.contains("report"))
        #expect(js.evaluateScript("Object.keys(window).length === keys")?.toBool() == true)
        #expect(js.evaluateScript("new WebGLRenderingContext().getParameter(7)")?.toString() == "value 7")
    }

    /// Niche's own world can arrive after a page's first scripts: it asks and hears them again.
    @Test func whatWasReportedIsSaidAgainWhenAsked() throws {
        let js = try page()
        js.evaluateScript("var gl = new WebGLRenderingContext(); gl.getParameter(37445);")
        #expect(reports(js).count == 1)
        js.evaluateScript("EventTarget.prototype.dispatchEvent.call(window, new CustomEvent('chanpq', {}))")
        #expect(reports(js) == ["webgl ", "webgl "])
    }

    @Test func aFrameInsideThePageIsLeftAlone() throws {
        let js = try #require(JSContext())
        js.evaluateScript(Self.fakeWindow + "window.top = {};")
        js.evaluateScript(PrivacyProbeScript.script(event: "chanp"))
        js.evaluateScript("var gl = new WebGLRenderingContext(); gl.getParameter(37445);")
        #expect(reports(js).isEmpty)
    }

    @Test func aPageWithoutTheseObjectsIsLeftAlone() throws {
        let js = try #require(JSContext())
        var failure: String?
        js.exceptionHandler = { _, e in failure = e?.toString() }
        js.evaluateScript("var window = this; window.top = window;")
        js.evaluateScript(PrivacyProbeScript.script(event: "chanp"))
        #expect(failure == nil)
    }

    @Test func theIsolatedWorldKeepsReportsUntilTheyAreRead() throws {
        let js = try #require(JSContext())
        js.evaluateScript("var window = this; var niche = window.__niche = {}; var heard = {}; function addEventListener(t, f) { heard[t] = f; }")
        js.evaluateScript(PrivacyProbeScript.listener(event: "chanp"))
        js.evaluateScript("heard.chanp({ detail: 'webgl https://cdn.widgets.test/fp.js' }); heard.chanp({ detail: 'canvas ' });")
        #expect(js.evaluateScript(PrivacyProbeScript.drain)?.toString() == #"["webgl https://cdn.widgets.test/fp.js","canvas "]"#)
        #expect(js.evaluateScript(PrivacyProbeScript.drain)?.toString() == "[]")
        // A page with no isolated world yet answers with nothing.
        js.evaluateScript("delete window.__niche;")
        #expect(js.evaluateScript(PrivacyProbeScript.drain)?.toString() == "[]")
    }

    @Test func aReportNamesTheProbeAndTheScriptsHost() {
        let hit = PrivacyProbeScript.parse("webgl https://CDN.widgets.test/fp.js")
        #expect(hit?.probe == .webgl)
        #expect(hit?.host == "cdn.widgets.test")
        #expect(PrivacyProbeScript.parse("canvas ")?.host == "")
        #expect(PrivacyProbeScript.parse("canvas")?.probe == .canvas)
        #expect(PrivacyProbeScript.parse("battery https://a.test/x.js") == nil)
        #expect(PrivacyProbeScript.parse("") == nil)
    }
}
