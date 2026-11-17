// Entry point for every Chromium subprocess (renderer, GPU, utility, plugin,
// alerts). Enters the macOS sandbox, then loads the framework from the
// enclosing Niche.app bundle and hands control to CEF.
#include <map>
#include <string>
#include <vector>

#include "include/cef_app.h"
#include "include/cef_render_process_handler.h"
#include "include/cef_sandbox_mac.h"
#include "include/cef_v8.h"
#include "include/wrapper/cef_library_loader.h"

#include "NicheShields.h"

namespace {

// send(string) for Niche's page scripts: the string goes to the browser process as a
// "Niche.page" message. Pages never see this function (it is only an argument to Niche's
// own script) and nothing reaches the page's console.
class SendHandler : public CefV8Handler {
 public:
  bool Execute(const CefString& name, CefRefPtr<CefV8Value> object, const CefV8ValueList& arguments,
               CefRefPtr<CefV8Value>& retval, CefString& exception) override {
    if (arguments.empty() || !arguments[0]->IsString()) return true;
    CefRefPtr<CefV8Context> context = CefV8Context::GetCurrentContext();
    CefRefPtr<CefFrame> frame = context ? context->GetFrame() : nullptr;
    if (!frame || !frame->IsValid()) return true;
    CefRefPtr<CefProcessMessage> message = CefProcessMessage::Create("Niche.page");
    message->GetArgumentList()->SetString(0, arguments[0]->GetStringValue());
    frame->SendProcessMessage(PID_BROWSER, message);
    return true;
  }
  IMPLEMENT_REFCOUNTING(SendHandler);
};

// Runs Niche's page scripts ("Niche.run" from NicheCEF's RunPageScript) in the frame's page:
// the script is a function expression called with send(). Exceptions stay here, so a
// script that fails leaves nothing in DevTools either. A named script runs once per
// document; later runs call the function it returned.
class RenderHandler : public CefRenderProcessHandler {
 public:
  bool OnProcessMessageReceived(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                                CefProcessId source_process, CefRefPtr<CefProcessMessage> message) override {
    if (source_process != PID_BROWSER) return false;
    if (message->GetName() == "Niche.shieldsOff") {
        SetOffSites(message->GetArgumentList()->GetString(0).ToString());
        return true;
    }
    if (message->GetName() != "Niche.run") return false;
    CefRefPtr<CefListValue> args = message->GetArgumentList();
    std::string name = args->GetString(0).ToString();
    // What the script's function is called with, when there is something.
    CefV8ValueList data;
    if (args->GetSize() > 2) data.push_back(CefV8Value::CreateString(args->GetString(2)));
    CefRefPtr<CefV8Context> context = frame ? frame->GetV8Context() : nullptr;
    if (!context || !context->IsValid() || !context->Enter()) return true;
    if (!name.empty()) {
      for (const Installed& i : installed_) {
        if (i.name != name || !i.context->IsSame(context)) continue;
        if (i.again && i.again->IsFunction()) i.again->ExecuteFunction(nullptr, data);
        context->Exit();
        return true;
      }
    }
    CefRefPtr<CefV8Value> script;
    CefRefPtr<CefV8Exception> error;
    if (context->Eval(args->GetString(1), CefString(), 0, script, error) && script && script->IsFunction()) {
      CefRefPtr<CefV8Value> again =
          script->ExecuteFunction(nullptr, {CefV8Value::CreateFunction("send", new SendHandler())});
      if (!name.empty()) installed_.push_back({context, name, again});
      if (!data.empty() && again && again->IsFunction()) again->ExecuteFunction(nullptr, data);
    }
    context->Exit();
    return true;
  }

  // The script a browser's pages start with in their own world ("niche.start", from NicheCEF's
  // NichePageStartInfo): run here, the moment a document's script context exists and before any
  // script of the page, in every frame. Nothing of it reaches the page's console.
  void OnBrowserCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefDictionaryValue> extra_info) override {
    if (!extra_info) return;
    if (extra_info->HasKey("niche.start")) start_[browser->GetIdentifier()] = extra_info->GetString("niche.start");
    // Shields for this process: the lists' rules that inject scripts ("niche.shields", from
    // NicheCEF's NichePageStartInfo). One per process; a newer one (the lists were updated, a
    // switch in Settings changed) replaces it.
    if (CefRefPtr<CefBinaryValue> blob = extra_info->GetBinary("niche.shields")) {
      const size_t size = blob->GetSize();
      if (size != shields_size_) {
        std::vector<uint8_t> bytes(size);
        blob->GetData(bytes.data(), size, 0);
        if (NicheShieldsPage* page = niche_shields_page_load(bytes.data(), size)) {
          if (shields_) niche_shields_page_free(shields_);
          shields_ = page;
          shields_size_ = size;
        }
      }
      SetOffSites(extra_info->GetString("niche.shields.off").ToString());
    }
  }

  void OnBrowserDestroyed(CefRefPtr<CefBrowser> browser) override { start_.erase(browser->GetIdentifier()); }

  void OnContextCreated(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, CefRefPtr<CefV8Context> context) override {
    CefRefPtr<CefV8Value> result;
    CefRefPtr<CefV8Exception> error;
    auto it = start_.find(browser->GetIdentifier());
    if (it != start_.end()) context->Eval(it->second, CefString(), 0, result, error);
    // The lists' scriptlets for this document (answer a cookie notice, defuse an ad-block wall):
    // they only work when they run before the page's own scripts, which is here.
    if (!shields_) return;
    const std::string url = frame->GetURL().ToString();
    if (url.compare(0, 7, "http://") != 0 && url.compare(0, 8, "https://") != 0) return;
    if (ProtectionOff(browser, frame, url)) return;
    if (char* script = niche_shields_page_script(shields_, url.c_str())) {
      context->Eval(script, CefString(), 0, result, error);
      niche_shields_string_free(script);
    }
  }

  void OnContextReleased(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                         CefRefPtr<CefV8Context> context) override {
    for (auto i = installed_.begin(); i != installed_.end();) {
      i = i->context->IsSame(context) ? installed_.erase(i) : i + 1;
    }
  }

 private:
  struct Installed {
    CefRefPtr<CefV8Context> context;
    std::string name;
    CefRefPtr<CefV8Value> again;
  };
  // Sites where the user switched protection off, as the browser process names them (the last
  // labels of a host: NicheContentBlocker.h's SiteOrHost). A document of such a site, or inside
  // a page of one, runs no list scripts.
  void SetOffSites(const std::string& sites) {
    off_sites_.clear();
    size_t start = 0;
    while (start < sites.size()) {
      size_t end = sites.find('\n', start);
      if (end == std::string::npos) end = sites.size();
      if (end > start) off_sites_.push_back(sites.substr(start, end - start));
      start = end + 1;
    }
  }

  static std::string Host(const std::string& url) {
    size_t at = url.find("://");
    if (at == std::string::npos) return std::string();
    std::string rest = url.substr(at + 3);
    rest = rest.substr(0, rest.find_first_of("/?#"));
    if (size_t user = rest.rfind('@'); user != std::string::npos) rest = rest.substr(user + 1);
    rest = rest.substr(0, rest.find(':'));
    for (char& c : rest) if (c >= 'A' && c <= 'Z') c = char(c - 'A' + 'a');
    return rest;
  }

  bool HostIsOff(const std::string& host) const {
    for (const std::string& site : off_sites_) {
      if (host == site) return true;
      if (host.size() > site.size() && host.compare(host.size() - site.size(), site.size(), site) == 0 &&
          host[host.size() - site.size() - 1] == '.') return true;
    }
    return false;
  }

  bool ProtectionOff(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const std::string& url) const {
    if (off_sites_.empty()) return false;
    if (HostIsOff(Host(url))) return true;
    CefRefPtr<CefFrame> top = browser->GetMainFrame();
    return top && !frame->IsMain() && HostIsOff(Host(top->GetURL().ToString()));
  }

  std::vector<Installed> installed_;
  std::map<int, CefString> start_;
  NicheShieldsPage* shields_ = nullptr;
  size_t shields_size_ = 0;
  std::vector<std::string> off_sites_;
  IMPLEMENT_REFCOUNTING(RenderHandler);
};

class HelperApp : public CefApp {
 public:
  CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override { return render_handler_; }

 private:
  CefRefPtr<RenderHandler> render_handler_ = new RenderHandler();
  IMPLEMENT_REFCOUNTING(HelperApp);
};

}  // namespace

int main(int argc, char* argv[]) {
  // The seatbelt profile has to be in place before the framework loads.
  // libcef_sandbox.dylib ships inside the framework (Libraries/).
  CefScopedSandboxContext sandbox_context;
  if (!sandbox_context.Initialize(argc, argv)) {
    return 1;
  }
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }
  CefMainArgs main_args(argc, argv);
  CefRefPtr<CefApp> app = new HelperApp();
  return CefExecuteProcess(main_args, app, nullptr);
}
