import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var desktopChannel: FlutterMethodChannel?
  var desktopReady = false
  private var terminationPending = false
  private var allowTermination = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if allowTermination || !desktopReady {
      return .terminateNow
    }
    if !terminationPending {
      terminationPending = true
      desktopChannel?.invokeMethod("requestQuit", arguments: nil) { result in
        if result != nil {
          self.terminationPending = false
          sender.reply(toApplicationShouldTerminate: false)
        }
      }
    }
    return .terminateLater
  }

  func completeQuit() {
    allowTermination = true
    if terminationPending {
      NSApp.reply(toApplicationShouldTerminate: true)
    } else {
      NSApp.terminate(nil)
    }
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if desktopReady {
      desktopChannel?.invokeMethod("showWindow", arguments: nil)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
