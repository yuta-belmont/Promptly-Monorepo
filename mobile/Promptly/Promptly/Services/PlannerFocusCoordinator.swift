import SwiftUI
import Combine

class PlannerFocusCoordinator: ObservableObject {
    @Published private(set) var focusedItemId: UUID?
    private var managers: [UUID: PlannerFocusManager] = [:]
    private var isProgrammaticUpdate = false
    
    func register(_ manager: PlannerFocusManager, for itemId: UUID) {
        print("[PlannerFocusCoordinator] Registering manager for item: \(itemId)")
        managers[itemId] = manager
    }
    
    func unregister(itemId: UUID) {
        print("[PlannerFocusCoordinator] Unregistering manager for item: \(itemId)")
        managers[itemId] = nil
        if focusedItemId == itemId {
            focusedItemId = nil
        }
    }
    
    func updateFocus(for itemId: UUID?, hasAnyFocus: Bool) {
        // Only update if this isn't a programmatic change
        guard !isProgrammaticUpdate else { return }
        
        if hasAnyFocus {
            focusedItemId = itemId
        } else if focusedItemId == itemId {
            focusedItemId = nil
        }
    }
    
    func removeAllFocus() {
        print("[PlannerFocusCoordinator] Removing all focus")
        isProgrammaticUpdate = true
        defer { isProgrammaticUpdate = false }
        
        // Clear focus from current item if any
        if let currentId = focusedItemId, let currentManager = managers[currentId] {
            print("[PlannerFocusCoordinator] Removing focus for item: \(currentId)")
            currentManager.removeAllFocus()
        }
        focusedItemId = nil
    }
} 
