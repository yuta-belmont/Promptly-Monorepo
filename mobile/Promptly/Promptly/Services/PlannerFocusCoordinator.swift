import SwiftUI
import Combine

class PlannerFocusCoordinator: ObservableObject {
    @Published private(set) var focusedItemId: UUID?
    private var managers: [UUID: PlannerFocusManager] = [:]
    private var isProgrammaticUpdate = false
    
    func register(_ manager: PlannerFocusManager, for itemId: UUID) {
        managers[itemId] = manager
    }
    
    func unregister(itemId: UUID) {
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
        isProgrammaticUpdate = true
        defer { isProgrammaticUpdate = false }
        
        // Clear focus from current item if any
        if let currentId = focusedItemId, let currentManager = managers[currentId] {
            currentManager.removeAllFocus()
        }
        focusedItemId = nil
    }
} 
