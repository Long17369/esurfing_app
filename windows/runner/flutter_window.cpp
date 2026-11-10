#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

// PROCESS_POWER_THROTTLING_* 是 Windows 10 1709 / SDK 10.0.16299 起才有的，
// 老 SDK 上退回等价的自定义定义，保证能编过。
#if defined(PROCESS_POWER_THROTTLING_CURRENT_VERSION)
using ThrottlingState = PROCESS_POWER_THROTTLING_STATE;
constexpr ULONG kThrottlingVersion = PROCESS_POWER_THROTTLING_CURRENT_VERSION;
constexpr ULONG kThrottlingExecutionSpeed =
    PROCESS_POWER_THROTTLING_EXECUTION_SPEED;
constexpr PROCESS_INFORMATION_CLASS kProcessPowerThrottling =
    ProcessPowerThrottling;
#else
struct ThrottlingState {
  ULONG Version;
  ULONG ControlMask;
  ULONG StateMask;
};
constexpr ULONG kThrottlingVersion = 1;
constexpr ULONG kThrottlingExecutionSpeed = 0x1;
constexpr PROCESS_INFORMATION_CLASS kProcessPowerThrottling =
    static_cast<PROCESS_INFORMATION_CLASS>(4);
#endif

using SetProcessInformationFn = BOOL(WINAPI*)(HANDLE, PROCESS_INFORMATION_CLASS,
                                              LPVOID, DWORD);

// 「效率模式」（EcoQoS）：把进程标记成可降速执行的后台任务，任务管理器里会显示
// 「效率模式」。Windows 10 1709+ 才支持，更老的系统返回 false。
bool SetEfficiencyMode(bool enable) {
  static const auto set_process_information =
      reinterpret_cast<SetProcessInformationFn>(GetProcAddress(
          GetModuleHandleW(L"kernel32.dll"), "SetProcessInformation"));
  if (set_process_information == nullptr) {
    return false;
  }
  ThrottlingState state{};
  state.Version = kThrottlingVersion;
  state.ControlMask = kThrottlingExecutionSpeed;
  state.StateMask = enable ? kThrottlingExecutionSpeed : 0;
  return set_process_information(GetCurrentProcess(), kProcessPowerThrottling,
                                 &state, sizeof(state)) != FALSE;
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

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "esurfing/windows",
          &flutter::StandardMethodCodec::GetInstance());
  platform_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "setEfficiencyMode") {
          const auto* args = call.arguments();
          const bool* value =
              args == nullptr ? nullptr : std::get_if<bool>(args);
          const bool ok = SetEfficiencyMode(value != nullptr && *value);
          result->Success(flutter::EncodableValue(ok));
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  platform_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
