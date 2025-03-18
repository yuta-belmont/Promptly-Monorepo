import SwiftUI

// A utility to help with programmatic navigation in SwiftUI
struct NavigationUtil {
    // Shared navigation path that can be observed across the app
    static var navigationPath = NavigationPath()
    
    // Reset the navigation stack
    static func popToRoot() {
        navigationPath = NavigationPath()
    }
    
    // Navigate to a specific view
    static func navigate<T: Hashable>(to destination: T) {
        navigationPath.append(destination)
    }
}

// Extension to get the navigation controller from any view controller
extension UIViewController {
    var navigationController: UINavigationController? {
        return self as? UINavigationController ?? self.navigationController
    }
} 