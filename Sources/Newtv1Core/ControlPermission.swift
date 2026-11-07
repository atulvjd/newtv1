import Foundation

public enum ControlPermission {
    public static func paneName(macOSMajorVersion: Int) -> String {
        macOSMajorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }
}
