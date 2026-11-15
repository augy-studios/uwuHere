#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// The main window, hosting the Flutter view, and the app's own channel to Windows
// (org.uwuapps.here/desktop, lib/desktop/runner.dart): the Jump List and the taskbar's thumbnail
// buttons for the events this computer hosts.
class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  struct Favourite {
    std::wstring id;
    std::wstring name;
    std::wstring link;
  };

  void SetFavourites(const std::vector<Favourite>& favourites);
  void UpdateJumpList();
  void UpdateThumbButtons();
  void OnThumb(int button);

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  std::vector<Favourite> favourites_;
  // Unused by uwuHere (its middle thumbnail button is Refresh); kept for the channel.
  bool playing_ = false;
  bool thumbs_added_ = false;
  UINT taskbar_created_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
