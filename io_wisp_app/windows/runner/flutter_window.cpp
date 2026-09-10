#include "flutter_window.h"

#include <optional>
#include <shobjidl.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // One native read-only selection action. No plugin installation or source
  // writing; validation and actual read-only loading live in the Dart layers.
  import_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "io_wisp/legacy_import",
      &flutter::StandardMethodCodec::GetInstance());
  import_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const bool source_file = call.method_name() == "selectSource";
    if (call.method_name() != "selectJson" && !source_file) {
      result->NotImplemented();
      return;
    }
    Microsoft::WRL::ComPtr<IFileOpenDialog> dialog;
    HRESULT hr = CoCreateInstance(CLSID_FileOpenDialog, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog));
    DWORD options = 0;
    if (SUCCEEDED(hr)) hr = dialog->GetOptions(&options);
    if (SUCCEEDED(hr)) hr = dialog->SetOptions(options | FOS_FILEMUSTEXIST |
        FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_DONTADDTORECENT |
        FOS_NODEREFERENCELINKS);
    const COMDLG_FILTERSPEC filter[] = {{source_file ? L"Source files" : L"IO Wisp project JSON", source_file ? L"*.*" : L"*.json"}};
    if (SUCCEEDED(hr)) hr = dialog->SetFileTypes(1, filter);
    if (SUCCEEDED(hr)) hr = dialog->SetTitle(source_file ? L"Select source file (read-only copy)" : L"Select legacy project JSON (read only)");
    if (SUCCEEDED(hr)) hr = dialog->Show(GetHandle());
    if (hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
      result->Success();
      return;
    }
    Microsoft::WRL::ComPtr<IShellItem> item;
    if (SUCCEEDED(hr)) hr = dialog->GetResult(&item);
    PWSTR selected = nullptr;
    if (SUCCEEDED(hr)) hr = item->GetDisplayName(SIGDN_FILESYSPATH, &selected);
    if (FAILED(hr)) {
      result->Error("file_selection", "The Windows file dialog could not open.");
      return;
    }
    const int length = WideCharToMultiByte(CP_UTF8, 0, selected, -1, nullptr, 0, nullptr, nullptr);
    std::string path(static_cast<size_t>(length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, selected, -1, path.data(), length, nullptr, nullptr);
    CoTaskMemFree(selected);
    if (!path.empty()) path.pop_back();
    result->Success(flutter::EncodableValue(path));
  });

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
  import_channel_ = nullptr;
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
