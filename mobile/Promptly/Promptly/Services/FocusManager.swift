import SwiftUI
import Combine

/// A global focus manager to handle focus state across the application
class FocusManager: ObservableObject {
    static let shared = FocusManager()
    
    // MARK: - Published Properties
    @Published private(set) var currentFocusedView: FocusedView?
    @Published private(set) var isAnyViewFocused: Bool = false
    
    // MARK: - Focus State Properties
    @Published var isEasyListFocused: Bool = false {
        didSet {
            updateFocusState(isEasyListFocused ? .easyList : nil)
        }
    }
    
    @Published var isChatFocused: Bool = false {
        didSet {
            updateFocusState(isChatFocused ? .chat : nil)
        }
    }
    
    // MARK: - Private Properties
    private var focusSubscriptions: Set<AnyCancellable> = []
    
    private init() {
        setupFocusObservers()
    }
    
    // MARK: - Public Methods
    
    /// Removes focus from all views
    func removeAllFocus() {
        isEasyListFocused = false
        isChatFocused = false
        currentFocusedView = nil
        isAnyViewFocused = false
    }
    
    /// Request focus for a specific view
    /// - Parameter view: The view requesting focus
    func requestFocus(for view: FocusedView) {
        // First, clear other views' focus states without affecting currentFocusedView
        isEasyListFocused = view == .easyList
        isChatFocused = view == .chat
        
        // Update the current focused view directly
        currentFocusedView = view
        isAnyViewFocused = true
    }
    
    // MARK: - Private Methods
    
    private func setupFocusObservers() {
        // Observe any changes to focus states
        Publishers.CombineLatest($isEasyListFocused, $isChatFocused)
            .sink { [weak self] easyList, chat in
                self?.isAnyViewFocused = easyList || chat
            }
            .store(in: &focusSubscriptions)
    }
    
    private func updateFocusState(_ newView: FocusedView?) {
        if let view = newView {
            // If a view is gaining focus, update the current focused view
            currentFocusedView = view
        } else if currentFocusedView != nil {
            // Only clear the current focused view if we're losing focus
            // and this is the currently focused view
            currentFocusedView = nil
        }
    }
}

// MARK: - Focus Types

/// Represents the different views that can have focus
enum FocusedView: Equatable {
    case easyList
    case chat
}

// MARK: - View Extension

extension View {
    /// Convenience modifier to handle focus management
    /// - Parameters:
    ///   - focusManager: The focus manager instance
    ///   - view: The view type requesting focus
    func manageFocus(using focusManager: FocusManager = .shared, for view: FocusedView) -> some View {
        self.onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if oldValue == view && newValue != view {
                // Only clear focus when we're actually transitioning away from this view
                switch view {
                case .easyList:
                    focusManager.isEasyListFocused = false
                case .chat:
                    focusManager.isChatFocused = false
                }
            }
        }
    }
    
    /// Convenience modifier to remove focus when tapped outside
    func removeFocusOnTapOutside(using focusManager: FocusManager = .shared) -> some View {
        self.onTapGesture {
            focusManager.removeAllFocus()
        }
    }
} 
