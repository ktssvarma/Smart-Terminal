#if os(macOS)
import SwiftUI

enum AppTheme {
    static let sidebarWidth: CGFloat = 160
    static let sidebarCollapsedWidth: CGFloat = 56
    static let titleBarHeight: CGFloat = 28
    static let terminalHeaderHeight: CGFloat = 40
    static let tabHeight: CGFloat = 32
    static let newTabHeight: CGFloat = 32
    static let closeSize: CGFloat = 12
    static let iconSize: CGFloat = 14
    static let corner: CGFloat = 6

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16

    static let window = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let sidebar = Color(red: 0.13, green: 0.13, blue: 0.135)
    static let header = Color(red: 0.16, green: 0.16, blue: 0.165)
    static let terminal = Color.black
    static let border = Color.white.opacity(0.08)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let fillIdle = Color.clear
    static let fillHover = Color.white.opacity(0.06)
    static let fillActive = Color.white.opacity(0.10)
    static let fillUtility = Color.white.opacity(0.06)
    static let fillUtilityHover = Color.white.opacity(0.10)

    static let motion = Animation.easeInOut(duration: 0.15)
}
#endif
