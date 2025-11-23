//
//  CGWindowHelper.swift
//  Gnau
//
//  Uses CGWindow API to get accurate window bounds ()
//  AXUIElement bounds are unreliable for Electron apps
//

import Foundation
import ApplicationServices

/// Helper to get window bounds using CGWindow API
/// This is more reliable than AXUIElement bounds for Electron apps
enum CGWindowHelper {

    /// Get window bounds for process using CGWindow API
    ///     static func getWindowBounds(for processID: pid_t) -> CGRect? {
        // Get window list for this process
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            let msg = "❌ CGWindowHelper: Failed to get window list"
            NSLog(msg)
            logToDebugFile(msg)
            return nil
        }

        // Find window for our process
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == processID else {
                continue
            }

            // Get window bounds
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }

            let bounds = CGRect(x: x, y: y, width: width, height: height)

            // CGWindow returns Quartz coordinates (top-left origin)
            // Return raw Quartz coordinates - parsers expect this format (like AX API)
            let msg = "✅ CGWindowHelper: Got window bounds via CGWindow API (Quartz): \(bounds)"
            NSLog(msg)
            logToDebugFile(msg)

            return bounds
        }

        let msg = "⚠️ CGWindowHelper: No window found for PID \(processID)"
        NSLog(msg)
        logToDebugFile(msg)
        return nil
    }

    /// Get main window bounds for process
    /// Filters for largest window (usually the main window)
    static func getMainWindowBounds(for processID: pid_t) -> CGRect? {
        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var mainWindow: CGRect?
        var largestArea: CGFloat = 0

        // Find largest window for this process (likely the main window)
        for windowInfo in windowList {
            guard let windowPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == processID else {
                continue
            }

            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"] else {
                continue
            }

            let area = width * height
            if area > largestArea {
                largestArea = area
                // Return raw Quartz coordinates - parsers expect this format (like AX API)
                mainWindow = CGRect(x: x, y: y, width: width, height: height)
            }
        }

        if let window = mainWindow {
            let msg = "✅ CGWindowHelper: Got main window bounds: \(window)"
            NSLog(msg)
            logToDebugFile(msg)
        }

        return mainWindow
    }
}
