import SwiftUI
import Foundation

@MainActor
class ChecklistViewState: ObservableObject {
    @Published var isEditing = false
    @Published var editingItem: ChecklistItem?
    @Published var editedTitle = ""
    @Published var editedNotification: Date?
    @Published var newItemText = ""
    @Published var isFullyExpanded = false
    
    // Import confirmation dialogs
    @Published var showingImportYesterdayConfirmation = false
    @Published var showingImportYesterdayOptions = false
    @Published var showingImportDateConfirmation = false
    @Published var showingImportDateOptions = false
    @Published var selectedImportDate: Date = Date()
    @Published var showingSaveAlert = false
    
    private let viewModel: ChecklistViewModel
    
    init(viewModel: ChecklistViewModel, isFullyExpanded: Bool = false) {
        self.viewModel = viewModel
        self.isFullyExpanded = isFullyExpanded
    }
    
    // Get the current checklist date
    var checklistDate: Date {
        return viewModel.checklist.date
    }
    
    // Check if there are any unsaved changes
    var hasUnsavedChanges: Bool {
        // Check if there's an item being edited
        if editingItem != nil {
            return true
        }
        
        // Check if there's text in the new item field
        if !newItemText.isEmpty {
            return true
        }
        
        // Check if the current items differ from the snapshot
        return viewModel.hasChanges
    }
    
    // MARK: - Editing State Management
    func startEditing(_ item: ChecklistItem) {
        editingItem = item
        editedTitle = item.title
        editedNotification = item.notification
        isEditing = true
        viewModel.saveSnapshot() // Save state when starting to edit
    }
    
    func saveEdit() {
        guard let editingItem = editingItem else { return }
        var updatedItem = editingItem
        updatedItem.title = editedTitle
        
        // Handle notification changes
        if editedNotification != updatedItem.notification {
            updatedItem.notification = editedNotification
        }
        
        viewModel.updateItem(updatedItem)
        discardEdit()
    }
    
    func saveEditWithoutClosing() {
        guard let editingItem = editingItem else { return }
        var updatedItem = editingItem
        updatedItem.title = editedTitle
        
        // Handle notification changes
        if editedNotification != updatedItem.notification {
            updatedItem.notification = editedNotification
        }
        
        viewModel.updateItem(updatedItem)
        // Note: We don't call discardEdit() here to keep the item in editing mode
    }
    
    func discardEdit() {
        editingItem = nil
        editedTitle = ""
        editedNotification = nil
    }
    
    func discardChanges() {
        viewModel.restoreSnapshot()
        isEditing = false
        discardEdit()
        newItemText = ""
    }
    
    // MARK: - Item Actions
    func addNewItem() {
        guard !newItemText.isEmpty else { return }
        let item = ChecklistItem(
            title: newItemText, 
            date: viewModel.checklist.date,
            isCompleted: false,
            notification: nil,
            group: nil
        )
        viewModel.addItem(item)
        newItemText = ""
    }
    
    func toggleItem(_ item: ChecklistItem) {
        var updatedItem = item
        updatedItem.isCompleted.toggle()
        
        // When toggling completion, we need to update the item
        // The updateItem method in ViewModel will handle removing/rescheduling notifications
        viewModel.updateItem(updatedItem)
    }
    
    func deleteItems(at offsets: IndexSet) {
        viewModel.deleteItems(at: offsets)
    }
    
    func moveItems(from source: IndexSet, to destination: Int) {
        viewModel.moveItems(from: source, to: destination)
    }
    
    // MARK: - Import Actions
    @MainActor
    func importFromYesterday() async {
        // Check if current checklist is empty
        if viewModel.items.isEmpty {
            // Show simple confirmation for empty checklist
            showingImportYesterdayConfirmation = true
        } else {
            // Show options dialog for non-empty checklist
            showingImportYesterdayOptions = true
        }
    }
    
    @MainActor
    func importFromDate(_ date: Date) async {
        selectedImportDate = date
        // Check if current checklist is empty
        if viewModel.items.isEmpty {
            // Show simple confirmation for empty checklist
            showingImportDateConfirmation = true
        } else {
            // Show options dialog for non-empty checklist
            showingImportDateOptions = true
        }
    }
    
    @MainActor
    func confirmImportFromYesterday() async {
        await viewModel.importFromYesterday()
    }
    
    @MainActor
    func confirmImportFromDate() async {
        await viewModel.importFromDate(selectedImportDate)
    }
    
    @MainActor
    func overwriteWithYesterday() async {
        // Clear current items and then import
        viewModel.clearItems()
        await viewModel.importFromYesterday()
    }
    
    @MainActor
    func overwriteWithDate() async {
        await viewModel.clearAndImportFromDate(selectedImportDate)
    }
    
    @MainActor
    func importFromCalendar() async {
        // This method is no longer used as we've removed the calendar button
        // We're using the date picker popover instead
        await viewModel.importFromCalendar()
    }
} 
