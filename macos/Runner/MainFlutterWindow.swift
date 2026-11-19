import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger
    // launch_at_startup 0.5.x delegates macOS registration to the host app.
    FlutterMethodChannel(name: "launch_at_startup", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "launchAtStartupIsEnabled":
          result(SMAppService.mainApp.status == .enabled)
        case "launchAtStartupSetEnabled":
          guard let arguments = call.arguments as? [String: Any],
                let enabled = arguments["setEnabledValue"] as? Bool else {
            result(FlutterError(code: "invalid_argument", message: "Expected setEnabledValue", details: nil))
            return
          }
          do {
            if enabled {
              if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
              }
              guard SMAppService.mainApp.status == .enabled else {
                result(FlutterError(
                  code: "login_item_approval",
                  message: "Allow the app in System Settings > General > Login Items",
                  details: nil))
                return
              }
            } else {
              if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
              }
            }
            result(nil)
          } catch {
            result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    let desktopChannel = FlutterMethodChannel(name: "esurfing/macos", binaryMessenger: messenger)
    if let delegate = NSApp.delegate as? AppDelegate {
      delegate.desktopChannel = desktopChannel
      desktopChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "ready":
          delegate.desktopReady = true
          result(nil)
        case "notReady":
          delegate.desktopReady = false
          result(nil)
        case "completeQuit":
          result(nil)
          delegate.completeQuit()
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    super.awakeFromNib()
  }
}
