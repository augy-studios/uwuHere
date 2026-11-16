#include "flutter_window.h"

#include <dwmapi.h>
#include <objbase.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <optional>

#include "desktop_multi_window/desktop_multi_window_plugin.h"
#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "propsys.lib")

using Microsoft::WRL::ComPtr;

namespace {

// DWMWA_USE_IMMERSIVE_DARK_MODE, by number for older SDKs.
constexpr DWORD kImmersiveDarkMode = 20;
// DWMWA_CAPTION_COLOR (Windows 11), and its "draw none" and "the system's" values.
constexpr DWORD kCaptionColor = 35;
constexpr COLORREF kColorNone = 0xFFFFFFFE;
constexpr COLORREF kColorDefault = 0xFFFFFFFF;
constexpr wchar_t kAppId[] = L"org.uwuapps.here";
constexpr int kThumbPrevious = 1001;
constexpr int kThumbPlay = 1002;
constexpr int kThumbNext = 1003;

std::wstring Widen(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(n, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, s.c_str(), static_cast<int>(s.size()), w.data(), n);
  return w;
}

std::wstring ExePath() {
  wchar_t path[MAX_PATH];
  ::GetModuleFileNameW(nullptr, path, MAX_PATH);
  return path;
}

// A white 16 px glyph for a thumbnail button, drawn in code: an arrow left or right, or a ring
// with an arrowhead for refresh.
HICON GlyphIcon(int kind, bool playing) {
  const int size = 16;
  BITMAPV5HEADER bi = {};
  bi.bV5Size = sizeof(bi);
  bi.bV5Width = size;
  bi.bV5Height = -size;
  bi.bV5Planes = 1;
  bi.bV5BitCount = 32;
  bi.bV5Compression = BI_BITFIELDS;
  bi.bV5RedMask = 0x00FF0000;
  bi.bV5GreenMask = 0x0000FF00;
  bi.bV5BlueMask = 0x000000FF;
  bi.bV5AlphaMask = 0xFF000000;
  void* bits = nullptr;
  HDC dc = ::GetDC(nullptr);
  HBITMAP colour = ::CreateDIBSection(dc, reinterpret_cast<BITMAPINFO*>(&bi), DIB_RGB_COLORS, &bits, nullptr, 0);
  ::ReleaseDC(nullptr, dc);
  if (!colour || !bits) return nullptr;
  auto* px = static_cast<uint32_t*>(bits);
  auto set = [&](int x, int y) {
    if (x >= 0 && x < size && y >= 0 && y < size) px[y * size + x] = 0xFFFFFFFF;
  };
  for (int i = 0; i < size * size; i++) px[i] = 0;
  if (kind == kThumbPrevious || kind == kThumbNext) {
    for (int i = 0; i < 6; i++) {
      for (int t = 0; t < 2; t++) {
        int x = (kind == kThumbNext) ? 5 + i + t : 10 - i - t;
        set(x, 2 + i);
        set(x, 13 - i);
      }
    }
  } else {
    // Refresh: a ring, open at the top right, with its arrowhead there.
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        const double dx = x + 0.5 - 8, dy = y + 0.5 - 8;
        const double d = dx * dx + dy * dy;
        const bool gap = dx > 0 && dy < 0 && -dy > dx * 0.4;
        if (d >= 4.2 * 4.2 && d <= 6.0 * 6.0 && !gap) set(x, y);
      }
    }
    for (int i = 0; i < 4; i++) {
      set(10 + i, 2);
      set(13, 2 + i);
    }
  }
  HBITMAP mask = ::CreateBitmap(size, size, 1, 1, nullptr);
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = colour;
  info.hbmMask = mask;
  HICON icon = ::CreateIconIndirect(&info);
  ::DeleteObject(colour);
  ::DeleteObject(mask);
  return icon;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  // Each desktop widget is a window of its own with an engine of its own
  // (lib/desktop/widgets_window.dart): it gets the same plugins.
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* view_controller = reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(view_controller->engine());
  });

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "org.uwuapps.here/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "setFavourites") {
      std::vector<Favourite> favourites;
      const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
      if (args) {
        auto it = args->find(flutter::EncodableValue("items"));
        if (it != args->end()) {
          if (const auto* list = std::get_if<flutter::EncodableList>(&it->second)) {
            for (const auto& item : *list) {
              const auto* m = std::get_if<flutter::EncodableMap>(&item);
              if (!m) continue;
              Favourite f;
              auto get = [&](const char* key) -> std::wstring {
                auto v = m->find(flutter::EncodableValue(key));
                if (v == m->end()) return L"";
                const auto* s = std::get_if<std::string>(&v->second);
                return s ? Widen(*s) : L"";
              };
              f.id = get("id");
              f.name = get("name");
              f.link = get("link");
              if (!f.link.empty()) favourites.push_back(f);
            }
          }
        }
      }
      SetFavourites(favourites);
      result->Success();
    } else if (call.method_name() == "setPlaying") {
      const auto* on = std::get_if<bool>(call.arguments());
      playing_ = on && *on;
      UpdateThumbButtons();
      result->Success();
    } else if (call.method_name() == "setBadge") {
      result->Success();
    } else if (call.method_name() == "setBackdrop") {
      // { kind: "mica" | "acrylic" | "none", dark: bool } (lib/desktop/backdrop.dart).
      std::string kind = "none";
      bool dark = false;
      if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto k = args->find(flutter::EncodableValue("kind"));
        if (k != args->end()) {
          if (const auto* s = std::get_if<std::string>(&k->second)) kind = *s;
        }
        auto d = args->find(flutter::EncodableValue("dark"));
        if (d != args->end()) {
          if (const auto* b = std::get_if<bool>(&d->second)) dark = *b;
        }
      }
      result->Success(flutter::EncodableValue(SetBackdrop(kind, dark)));
    } else {
      result->NotImplemented();
    }
  });
  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarButtonCreated");

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  flutter_controller_->ForceRedraw();

  return true;
}

// The system's own material behind the whole window (the system's glass look): Mica, or Acrylic,
// through DWMWA_SYSTEMBACKDROP_TYPE, which Windows 11 has from 22H2 (build 22621). The frame is
// extended over the whole client area so the Flutter view's see-through pixels show it, and the
// window's dark mode follows the app's, so Mica is tinted to match. False where Windows can't.
bool FlutterWindow::SetBackdrop(const std::string& kind, bool dark) {
  HWND hwnd = GetHandle();
  if (!hwnd) return false;
  // DWMWA_SYSTEMBACKDROP_TYPE and its values (dwmapi.h in newer SDKs).
  constexpr DWORD kSystemBackdropType = 38;
  constexpr int kBackdropNone = 1, kBackdropMica = 2, kBackdropAcrylic = 3;
  const int type = kind == "mica" ? kBackdropMica : kind == "acrylic" ? kBackdropAcrylic : kBackdropNone;
  backdrop_ = type != kBackdropNone;
  backdrop_dark_ = dark;

  if (backdrop_) {
    BOOL d = dark ? TRUE : FALSE;
    ::DwmSetWindowAttribute(hwnd, kImmersiveDarkMode, &d, sizeof(d));
  } else {
    // Back to the system's own light or dark.
    UpdateTheme(hwnd);
  }
  const HRESULT hr = ::DwmSetWindowAttribute(hwnd, kSystemBackdropType, &type, sizeof(type));
  const bool shown = backdrop_ && SUCCEEDED(hr);
  MARGINS margins = shown ? MARGINS{-1, -1, -1, -1} : MARGINS{0, 0, 0, 0};
  ::DwmExtendFrameIntoClientArea(hwnd, &margins);
  if (!shown) backdrop_ = false;
  SetCaptionColour();
  // The frame is worked out again, for the extended frame to take.
  ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                 SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  return shown;
}

// With the frame extended over the window, Windows paints its hidden caption's strip across the
// top of the page, in the accent colour where "Show accent colour on title bars" is on, over the
// app's own title bar. With the backdrop on it draws none, so Mica shows there as everywhere else.
void FlutterWindow::SetCaptionColour() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  const COLORREF colour = backdrop_ ? kColorNone : kColorDefault;
  ::DwmSetWindowAttribute(hwnd, kCaptionColor, &colour, sizeof(colour));
}

void FlutterWindow::OnDestroy() {
  channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetFavourites(const std::vector<Favourite>& favourites) {
  favourites_ = favourites;
  UpdateJumpList();
  UpdateThumbButtons();
}

// The Jump List (right-click the taskbar icon): one task per event you host, "Name (code)", starting the
// exe with its uwu://here/ link, which the running copy is handed (lib/desktop/desk.dart).
void FlutterWindow::UpdateJumpList() {
  ComPtr<ICustomDestinationList> list;
  if (FAILED(::CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list)))) return;
  list->SetAppID(kAppId);
  UINT max_slots = 0;
  ComPtr<IObjectArray> removed;
  if (FAILED(list->BeginList(&max_slots, IID_PPV_ARGS(&removed)))) return;
  ComPtr<IObjectCollection> tasks;
  if (FAILED(::CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&tasks)))) {
    list->AbortList();
    return;
  }
  const std::wstring exe = ExePath();
  for (const auto& f : favourites_) {
    ComPtr<IShellLinkW> link;
    if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) continue;
    link->SetPath(exe.c_str());
    link->SetArguments((L"\"" + f.link + L"\"").c_str());
    link->SetIconLocation(exe.c_str(), 0);
    link->SetDescription(f.name.c_str());
    ComPtr<IPropertyStore> props;
    if (SUCCEEDED(link.As(&props))) {
      PROPVARIANT title;
      if (SUCCEEDED(::InitPropVariantFromString(f.name.c_str(), &title))) {
        props->SetValue(PKEY_Title, title);
        props->Commit();
        ::PropVariantClear(&title);
      }
    }
    tasks->AddObject(link.Get());
  }
  ComPtr<IObjectArray> array;
  if (!favourites_.empty() && SUCCEEDED(tasks.As(&array))) list->AddUserTasks(array.Get());
  list->CommitList();
}

// The taskbar's thumbnail buttons (hover the taskbar icon): the previous event, refresh, and the
// next event, of the events this computer hosts. Refresh works without bringing the window
// forward; previous and next open that event, and are left out with fewer than two.
void FlutterWindow::UpdateThumbButtons() {
  ComPtr<ITaskbarList3> taskbar;
  if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar)))) return;
  if (FAILED(taskbar->HrInit())) return;
  THUMBBUTTON buttons[3] = {};
  const int ids[3] = {kThumbPrevious, kThumbPlay, kThumbNext};
  const wchar_t* tips[3] = {L"Previous event", L"Refresh", L"Next event"};
  const bool few = favourites_.size() < 2;
  for (int i = 0; i < 3; i++) {
    buttons[i].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    buttons[i].iId = ids[i];
    buttons[i].hIcon = GlyphIcon(ids[i], playing_);
    wcsncpy_s(buttons[i].szTip, tips[i], _TRUNCATE);
    buttons[i].dwFlags = (few && ids[i] != kThumbPlay) ? THBF_HIDDEN : THBF_ENABLED;
  }
  HWND hwnd = GetHandle();
  if (!thumbs_added_) {
    if (SUCCEEDED(taskbar->ThumbBarAddButtons(hwnd, 3, buttons))) thumbs_added_ = true;
  } else {
    taskbar->ThumbBarUpdateButtons(hwnd, 3, buttons);
  }
  for (auto& b : buttons) {
    if (b.hIcon) ::DestroyIcon(b.hIcon);
  }
}

// The app does each: refresh, or the event before or after the open one in its list
// (lib/desktop/desktop_main.dart), so they follow whatever's open rather than a count kept here.
void FlutterWindow::OnThumb(int button) {
  if (!channel_) return;
  const char* what = button == kThumbPrevious ? "previous" : button == kThumbNext ? "next" : "toggle";
  channel_->InvokeMethod("thumb", std::make_unique<flutter::EncodableValue>(std::string(what)));
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  // Explorer restarted, or the taskbar button just appeared: the buttons go on again.
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    thumbs_added_ = false;
    if (!favourites_.empty()) UpdateThumbButtons();
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DWMCOLORIZATIONCOLORCHANGED:
      // Win32Window sets the window's dark mode to the system's here; with the backdrop on, it
      // follows the app's instead.
      if (backdrop_) {
        const LRESULT handled = Win32Window::MessageHandler(hwnd, message, wparam, lparam);
        BOOL d = backdrop_dark_ ? TRUE : FALSE;
        ::DwmSetWindowAttribute(hwnd, kImmersiveDarkMode, &d, sizeof(d));
        SetCaptionColour();
        return handled;
      }
      break;
    case WM_COMMAND:
      if (HIWORD(wparam) == THBN_CLICKED) {
        OnThumb(LOWORD(wparam));
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
