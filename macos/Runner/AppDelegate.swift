// SPDX-FileCopyrightText: 2026 Johannes Näder <git@pub.nextwelt.de>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
