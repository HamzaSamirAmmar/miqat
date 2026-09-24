import Foundation
import ServiceManagement

/// Registers/unregisters Miqat as a login item via SMAppService (macOS 13+).
enum LoginItemManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Applies the change; if the system refuses it (e.g. approval required),
    /// opens Login Items settings so the user can finish enabling it there.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Miqat: login item change failed — \(error.localizedDescription)")
            if enabled {
                SMAppService.openSystemSettingsLoginItems()
            }
            return false
        }
    }
}
