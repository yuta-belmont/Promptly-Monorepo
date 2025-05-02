import SwiftUI
import UIKit

// Add preference key at the top of the file
struct IsEditingPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

// MARK: - 3D Flip Effect Modifier
struct FlipEffect: ViewModifier {
    var isFlipped: Bool
    var axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0) // Default to horizontal flip (Y axis)
    
    func body(content: Content) -> some View {
        content
            // Apply 3D rotation based on flip state
            .rotation3DEffect(
                .degrees(isFlipped ? 180 : 0),
                axis: axis,
                perspective: 0.3 // Add perspective directly in the rotation3DEffect
            )
    }
}

extension View {
    func flipEffect(isFlipped: Bool, axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0)) -> some View {
        modifier(FlipEffect(isFlipped: isFlipped, axis: axis))
    }
}

// MARK: - Delete Confirmation View
struct DeleteConfirmationView: View {
    @Binding var isPresented: Bool
    @Binding var isConfirmationActive: Bool
    let onDelete: () -> Void
    let onDeleteCompleted: () -> Void
    let onDeleteIncomplete: () -> Void
    let feedbackGenerator: UIImpactFeedbackGenerator
    @State private var deleteTimer: Timer?
    @State private var selectedOption: DeleteOption = .all
    
    enum DeleteOption {
        case all, completed, incomplete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Delete All Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if isConfirmationActive && selectedOption == .all {
                    // Second tap - perform delete
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    isConfirmationActive = false
                    onDelete()
                    isPresented = false
                } else {
                    // First tap - start confirmation timer
                    selectedOption = .all
                    isConfirmationActive = true
                    resetTimer()
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .frame(width: 24)
                    Text(isConfirmationActive && selectedOption == .all ? "Confirm" : "Delete All")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(.red)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Delete Completed Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if isConfirmationActive && selectedOption == .completed {
                    // Second tap - perform delete
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    isConfirmationActive = false
                    onDeleteCompleted()
                    isPresented = false
                } else {
                    // First tap - start confirmation timer
                    selectedOption = .completed
                    isConfirmationActive = true
                    resetTimer()
                }
            }) {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .frame(width: 24)
                    Text(isConfirmationActive && selectedOption == .completed ? "Confirm" : "Delete Completed")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(.red)
                .opacity(0.7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Delete Incomplete Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if isConfirmationActive && selectedOption == .incomplete {
                    // Second tap - perform delete
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    isConfirmationActive = false
                    onDeleteIncomplete()
                    isPresented = false
                } else {
                    // First tap - start confirmation timer
                    selectedOption = .incomplete
                    isConfirmationActive = true
                    resetTimer()
                }
            }) {
                HStack {
                    Image(systemName: "circle")
                        .frame(width: 24)
                    Text(isConfirmationActive && selectedOption == .incomplete ? "Confirm" : "Delete Incomplete")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(.red)
                .opacity(0.7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .presentationCompactAdaptation(.none)
        .onDisappear {            // Reset timer and confirmation state when popover closes
            deleteTimer?.invalidate()
            deleteTimer = nil
            isConfirmationActive = false
        }
    }
    
    private func resetTimer() {
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
            isConfirmationActive = false
        }
    }
}

// MARK: - Header Component

struct EasyListHeader: View {
    let title: String
    let isEditing: Bool
    let showingNotes: Bool
    let onDone: () -> Void
    let onNotesToggle: () -> Void
    let onImport: (Date, Bool) -> Void
    let onDeleteAll: () -> Void
    let onDeleteCompleted: () -> Void
    let onDeleteIncomplete: () -> Void
    let onUndo: () -> Void
    let canUndo: Bool
    let currentDate: Date
    @EnvironmentObject private var undoManager: UndoStateManager
    @EnvironmentObject private var viewModel: EasyListViewModel
    
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationActive = false
    @State private var showingImportPopover = false
    @State private var deleteTimer: Timer?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        HStack(alignment: .center) {
            Text(showingNotes ? "Notes from \(title)" : title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            
            HStack(spacing: 26) {
                if !showingNotes && !isEditing {
                    if undoManager.canUndo {
                        Button(action: {
                            onDone() // Remove focus
                            feedbackGenerator.impactOccurred()
                            onUndo()
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.bottom, 1)
                        }
                    }
                    
                    Button(action: {
                        onDone() // Remove focus
                        showingDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 2)
                    }
                    .popover(isPresented: $showingDeleteConfirmation, arrowEdge: .top) {
                        DeleteConfirmationView(
                            isPresented: $showingDeleteConfirmation,
                            isConfirmationActive: $deleteConfirmationActive,
                            onDelete: onDeleteAll,
                            onDeleteCompleted: onDeleteCompleted,
                            onDeleteIncomplete: onDeleteIncomplete,
                            feedbackGenerator: feedbackGenerator
                        )
                    }
                    
                    //import button
                    Button(action: {
                        onDone() // Remove focus
                        showingImportPopover = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.bottom, 2)
                    }
                    .popover(isPresented: $showingImportPopover, arrowEdge: .top) {
                        ImportPopoverView(
                            isPresented: $showingImportPopover,
                            currentDate: currentDate,
                            onImport: onImport
                        )
                        .presentationCompactAdaptation(.none)
                    }
                }
                
                if showingNotes || !isEditing {
                    Button(action: {
                        onNotesToggle()
                    }) {
                        Image(systemName: "arrow.2.squarepath")
                            .foregroundColor(.white.opacity(0.8))
                            .rotationEffect(.degrees(showingNotes ? 180 : 0))
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingNotes)
                            .padding(.trailing, showingNotes && !isEditing ? 20 : 0)
                    }
                }
                
                // Add expand/collapse button
                if !showingNotes && !isEditing {
                    Button(action: {
                        feedbackGenerator.impactOccurred()
                        viewModel.toggleAllItemsExpanded()
                    }) {
                        Image(systemName: viewModel.hasExpandedItems ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.subheadline)
                            .padding(.bottom, 2)
                            .padding(.trailing, 20)
                    }
                }
                
                if isEditing {
                    Button(action: {
                        onDone()
                    }) {
                        Text("Done")
                            .foregroundColor(.white)
                            .dynamicTypeSize(.small...DynamicTypeSize.large)
                            .padding(.trailing, 16)

                    }
                    .frame(minWidth: 44)
                }
            }
        }
        .padding(.leading, 20)
        .padding(.vertical, 8)
        .frame(height: 44) // Fixed height of 44 points
        .headerBackground()
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .onAppear {
            // Prepare haptic feedback when view appears
            feedbackGenerator.prepare()
        }
        .onDisappear {
            // Clean up timer when view disappears
            deleteTimer?.invalidate()
            deleteTimer = nil
            deleteConfirmationActive = false
        }
    }
}

// MARK: - New Item Row Component

struct NewItemRow: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onDone: () -> Void
    @Binding var isListEmpty: Bool
    @Binding var focusRequested: Bool
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "circle")
                .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0.1))
                .font(.system(size: 22))
                .zIndex(2)
                .padding(.bottom, 4)
                .padding(.leading, 4)
            
            ZStack(alignment: .leading) {
                TextField("New item...", text: $text, axis: .vertical)
                    .foregroundColor(isFocused.wrappedValue ? .white : .gray)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused(isFocused)
                    .onChange(of: isFocused.wrappedValue) { oldValue, newValue in
                    }
                    .padding(.top, 2)
                    .onChange(of: text) { oldValue, newValue in
                        // Check if user pressed return (added a newline)
                        if newValue.contains("\n") {
                            // Remove the newline character
                            if oldValue.count == 0 {
                                text = newValue.replacingOccurrences(of: "\n", with: " ")
                                // But now that we replace \n with " ", we need to make sure we're not just submitting a " " field.
                                // An empty field that a users presses return in should just remove focus and not submit anything.
                                if text.count <= 1 {
                                    text = ""
                                    isFocused.wrappedValue = false
                                    onDone()
                                    return
                                }
                            } else {
                                text = oldValue
                            }
                            
                            // Submit if text is not empty
                            if !text.isEmpty {
                                onSubmit()
                            } else {
                                isFocused.wrappedValue = false
                                onDone()
                            }
                        }
                    }
            }
            .frame(width: UIScreen.main.bounds.width * 0.80, alignment: .topLeading)
            .clipped(antialiased: true)
            .padding(.leading, 4)
            .zIndex(1)
            .accessibilityAddTraits(.isKeyboardKey)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, (isFocused.wrappedValue || isListEmpty) ? 4 : 0)
        .padding(.leading, 16)
        // Only show when focused OR list is empty
        .opacity((isFocused.wrappedValue || isListEmpty) ? 1 : 0)
        // Explicitly set height to 0 when hidden
        .frame(height: (isFocused.wrappedValue || isListEmpty) ? nil : 0, alignment: .top)
        // Hide completely when not visible
        .accessibility(hidden: !(isFocused.wrappedValue || isListEmpty))
        // Add onChange for focusRequested
        .onChange(of: focusRequested) { oldValue, newValue in
            if newValue {
                // Request focus directly from within the component
                DispatchQueue.main.async {
                    isFocused.wrappedValue = true
                    // Reset the request flag after handling it
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        focusRequested = false
                    }
                }
            }
        }
    }
}

// MARK: - List Content Component

struct ListContent: View {
    @ObservedObject var viewModel: EasyListViewModel
    @State private var newItemText: String = ""
    @FocusState var isNewItemFocused: Bool
    @Binding var isEditing: Bool
    @EnvironmentObject private var focusManager: FocusManager
    let headerTitle: String
    let removeAllFocus: () -> Void
    
    // Add a state to track focus requests
    @State private var focusRequested: Bool = false
    
    // Computed property to check if list is empty
    private var isListEmpty: Bool {
        return viewModel.items.isEmpty
    }
    
    // Haptic feedback generator for item toggling
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Consolidated scroll helper function
    private func scrollToNewItem(_ proxy: ScrollViewProxy) {
        
        // Scroll immediately with NO animation
        DispatchQueue.main.async {
            // Remove animation wrapper for instantaneous scrolling
            proxy.scrollTo("newItemRow", anchor: .top)
            
            // Request focus after scroll is complete
            // This is a key change - we request focus AFTER the scroll completes
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                focusRequested = true
                
                // Also try direct focus as a backup approach
                isNewItemFocused = true
            }
        }
    }
    
    private func handleNewItemSubmit(proxy: ScrollViewProxy) {
        if !newItemText.isEmpty {
            viewModel.addItem(newItemText)
            newItemText = ""
            if !viewModel.isItemLimitReached {
                isNewItemFocused = true
            }
        }
    }
    
    private func handleMoveItems(from: IndexSet, to: Int) {
        viewModel.moveItems(from: from, to: to)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                List {
                    // Always include the NewItemRow but it will be hidden when not focused,
                    // unless the list is empty
                    if !viewModel.isItemLimitReached {
                        NewItemRow(
                            text: $newItemText,
                            isFocused: $isNewItemFocused,
                            onSubmit: { handleNewItemSubmit(proxy: proxy) },
                            onDone: {
                                isEditing = false
                                isNewItemFocused = false
                                focusManager.isEasyListFocused = false
                            },
                            isListEmpty: Binding(
                                get: { 
                                    let isEmpty = viewModel.items.isEmpty
                                    return isEmpty
                                },
                                set: { _ in }
                            ),
                            focusRequested: $focusRequested
                        )
                        .id("newItemRow")
                        .listRowSeparator(.hidden)
                    }
                    
                    ForEach(viewModel.items, id: \.id) { item in
                        makePlannerItemView(for: item)
                            .id("stable-item-\(item.id.uuidString)")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)
                    }
                    .onMove { from, to in
                        handleMoveItems(from: from, to: to)
                    }
                    .id("items-\(viewModel.date.timeIntervalSince1970)-\(viewModel.items.count)")
                    
                    // Add spacer at bottom of list for better scrolling
                    Color.clear.frame(height: 250)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // Constrain the List to exactly match the available height
                // Use animation with structurally significant values only
                // .animation(.easeInOut(duration: 0.2), value: viewModel.items.count)
                .environment(\.defaultMinListRowHeight, 0) // Minimize row height calculations
                .onChange(of: isNewItemFocused) { oldValue, newValue in
                    // Only handle focus management
                    if newValue && !viewModel.isItemLimitReached {
                        focusManager.requestFocus(for: .easyList)
                        // Scroll to the new item field when it gets focused
                    }
                    
                    // Handle saving when losing focus
                    if !newValue && oldValue && !newItemText.isEmpty {
                        viewModel.addItem(newItemText)
                        newItemText = ""
                    }
                    
                    // Update editing state
                    updateEditingState()
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ScrollToAddItem"))) { _ in
                    // Scroll to the top of the list when the notification is received
                    // This happens before focus is set
                    scrollToNewItem(proxy)
                }
            }
            
            EasyListFooter(isEditing: $isEditing)
                .environmentObject(viewModel.counterManager)
        }
    }
    
    private func updateEditingState() {
        isEditing = isNewItemFocused
    }
    
    private func deleteItem(_ item: Models.ChecklistItem) {
        if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                viewModel.deleteItem(id: item.id)  // Use the regular deleteItem method that adds to undo stack
            }
        }
    }
    
    // Helper function to create PlannerItemView with all necessary callbacks
    private func makePlannerItemView(for item: Models.ChecklistItem) -> some View {
        let displayData = viewModel.getDisplayData(for: item)
        
        return PlannerItemView.create(
            displayData: displayData,
            onToggleItem: { itemId, itemNotification in
                // Directly update the item in the EasyListViewModel by ID
                viewModel.toggleItemCompletion(itemId: itemId)
                // No need to post notification - view handles its own state
                viewModel.updateItemNotification(itemId: itemId, with: itemNotification)
            },
            onToggleSubItem: { mainItemId, subItemId, isCompleted in
                // Update the sub-item in the EasyListViewModel
                viewModel.toggleSubItemCompletion(mainItemId, subItemId: subItemId, isCompleted: isCompleted)
                // No need to post notification - view handles its own state
            },
            onLoseFocus: nil,
            onDelete: {
                // Used for menu-based deletion
                deleteItem(item)
            },
            onNotificationChange: { date in
                viewModel.updateItemNotification(itemId: item.id, with: date)
                // No need to post notification - view handles its own state
            },
            onGroupChange: { groupId in
                viewModel.updateItemGroup(itemId: item.id, with: groupId)
            },
            onItemTap: { itemId in
                // Remove any focus first
                isNewItemFocused = false
                
                // Save checklist before opening details view
                viewModel.saveChecklist()
                
                // Post only the item ID instead of the entire item
                // This ensures that the ItemDetailsView will fetch the latest version of the item
                NotificationCenter.default.post(
                    name: Notification.Name("ShowItemDetails"),
                    object: itemId
                )
            },
            onToggleExpanded: { itemId in
                // Update the expanded state in the ViewModel
                viewModel.toggleItemExpanded(itemId)
            }
        )
        // Individual ID is now set on the row above
    }
}

// MARK: - Footer Component

struct EasyListFooter: View {
    @EnvironmentObject private var counterManager: CounterStateManager
    @Binding var isEditing: Bool
    
    var body: some View {
        ZStack {
            // Only show content when not editing
            if !isEditing {
                // Left side content
                HStack {
                    Text("\(counterManager.completedCount)/\(counterManager.totalCount) completed")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.ultraThinMaterial)
                        )
                    Spacer()
                }
                
                // Right side content
                HStack {
                    Spacer()
                    if counterManager.totalCount > 0 {
                        ProgressView(value: Double(counterManager.completedCount), total: Double(counterManager.totalCount))
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 80)
                    }
                }
            }
        }
        .padding(.bottom, 5)
        .padding(.top, 2)
        .padding(.horizontal, 32)
        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
    }
}

// MARK: - Calendar Picker Wrapper
struct CalendarPickerView: View {
    @Binding var selectedDate: Date?
    
    var body: some View {
        DatePicker(
            "Select Date",
            selection: Binding(
                get: { selectedDate ?? Date() },
                set: { selectedDate = $0 }
            ),
            displayedComponents: .date
        )
        .scaleEffect(0.9)
        .datePickerStyle(.graphical)
        .accentColor(.blue)
        .colorScheme(.dark)
    }
}

// MARK: - Import Popover View
struct ImportPopoverView: View {
    @Binding var isPresented: Bool
    @State private var showPreviousDayOptions = true
    @State private var showCalendarOptions = false
    @State private var selectedDate: Date?
    @State private var showCalendar = false
    let currentDate: Date
    let onImport: (Date, Bool) -> Void
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            // Previous Day Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                withAnimation(.linear(duration: 0.1)) {
                    showPreviousDayOptions.toggle()
                    showCalendarOptions = false
                    showCalendar = false
                }
            }) {
                HStack(spacing: 8) {
                    Text("Import Previous Day")
                        .foregroundColor(.white)
                        .dynamicTypeSize(.small...DynamicTypeSize.xLarge)
                    Spacer(minLength: 0)
                    Image(systemName: showPreviousDayOptions ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showPreviousDayOptions {
                let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? Date()
                
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    Button(action: {
                        feedbackGenerator.impactOccurred()
                        onImport(previousDay, true) // Import incomplete items only
                        isPresented = false
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .frame(width: 24)
                            Text("Import Incomplete")
                                .dynamicTypeSize(.xSmall...DynamicTypeSize.xLarge)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id("import-incomplete-previous")
                    
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    Button(action: {
                        feedbackGenerator.impactOccurred()
                        onImport(previousDay, false) // Import all items
                        isPresented = false
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down")
                                .frame(width: 24)
                            Text("Import All")
                                .dynamicTypeSize(.xSmall...DynamicTypeSize.xLarge)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .id("import-all-previous")
                    
                }
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .padding(.horizontal, 4)
                .id("previous-day-options")
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Calendar Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                withAnimation(.linear(duration: 0.2)) {
                    showCalendarOptions.toggle()
                    showPreviousDayOptions = false
                    showCalendar = showCalendarOptions
                }
            }) {
                HStack(spacing: 8) {
                    Text("Import from Calendar")
                        .foregroundColor(.white)
                        .dynamicTypeSize(.small...DynamicTypeSize.xLarge)
                    Spacer(minLength: 0)
                    Image(systemName: showCalendarOptions ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showCalendar {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.white.opacity(0.2))
                    
                    // Replace the DatePicker with the wrapper view
                    CalendarPickerView(selectedDate: $selectedDate)
                    // No need for onChange handler - the binding handles updates
                    
                    if let selectedDate = selectedDate {
                        Divider()
                            .background(Color.white.opacity(0.2))
                        
                        Button(action: {
                            feedbackGenerator.impactOccurred()
                            onImport(selectedDate, false) // Import all items
                            isPresented = false
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                    .frame(width: 24)
                                Text("Import All")
                                    .dynamicTypeSize(.small...DynamicTypeSize.xLarge)
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id("import-all-calendar")
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                        
                        Button(action: {
                            feedbackGenerator.impactOccurred()
                            onImport(selectedDate, true) // Import incomplete items only
                            isPresented = false
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .frame(width: 24)
                                Text("Import Incomplete")
                                    .dynamicTypeSize(.small...DynamicTypeSize.xLarge)
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id("import-incomplete-calendar")
                    }
                }
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .padding(.horizontal, 4)
                .id("calendar-options-\(selectedDate?.timeIntervalSince1970 ?? 0)")
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            // Prepare haptic feedback when view appears
            feedbackGenerator.prepare()
        }
    }
}

// MARK: - Main EasyList View

struct EasyListView: View {
    @EnvironmentObject private var viewModel: EasyListViewModel
    @State private var isEditing: Bool = false
    @FocusState private var isNewItemFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @EnvironmentObject private var focusManager: FocusManager
    @ObservedObject private var groupStore = GroupStore.shared
    @State private var keyboardHeight: CGFloat = 0
    @State private var isInViewTransition: Bool = false // Add flag to track transition state
    @State private var lastTransitionTime: Date? = nil // Track when transition ended
    
    init() {
        // No need to create a view model here anymore
    }
    
    private func onAddTap() {
        // Only allow add item if not in transition
        if isInViewTransition {
            return
        }
        
        // If we're in notes view, toggle back first
        if viewModel.isShowingNotes {
            onNotesToggle()
            
            // Add a bigger delay when coming from notes view
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: Notification.Name("ScrollToAddItem"), object: nil)
            }
            return
        }
        
        // Otherwise post notification immediately
        NotificationCenter.default.post(name: Notification.Name("ScrollToAddItem"), object: nil)
    }
    
    private func onNotesToggle() {
        // Prevent multiple taps during transition
        if isInViewTransition {
            return
        }
        
        // Set transition flag
        isInViewTransition = true
        
        // Remove focus
        isEditing = false
        isNewItemFocused = false
        isNotesFocused = false
        focusManager.isEasyListFocused = false
        
        // Toggle notes view with flip animation
        withAnimation(.easeInOut(duration: 0.4)) {
            viewModel.toggleNotesView()
        }
        
        // Reset transition flag after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isInViewTransition = false
            lastTransitionTime = Date() // Record when the transition ended
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            EasyListHeader(
                title: viewModel.headerTitle,
                isEditing: isEditing,
                showingNotes: viewModel.isShowingNotes,
                onDone: {
                    // Remove focus
                    isEditing = false
                    isNewItemFocused = false
                    isNotesFocused = false
                    focusManager.isEasyListFocused = false
                },
                onNotesToggle: {
                    onNotesToggle()
                },
                onImport: { sourceDate, importIncompleteOnly in
                    // Only allow import if not in transition
                    if !isInViewTransition {
                        viewModel.importItems(from: sourceDate, importIncompleteOnly: importIncompleteOnly)
                    }
                },
                onDeleteAll: {
                    // Only allow delete if not in transition
                    if !isInViewTransition {
                        viewModel.deleteAllItems()
                    }
                },
                onDeleteCompleted: {
                    // Only allow delete if not in transition
                    if !isInViewTransition {
                        viewModel.deleteCompletedItems()
                    }
                },
                onDeleteIncomplete: {
                    // Only allow delete if not in transition
                    if !isInViewTransition {
                        viewModel.deleteIncompleteItems()
                    }
                },
                onUndo: {
                    // Only allow undo if not in transition
                    if !isInViewTransition {
                        viewModel.undo()
                    }
                },
                canUndo: viewModel.canUndo,
                currentDate: viewModel.date
            )
            .environmentObject(viewModel.undoManager)
            .disabled(isInViewTransition) // Disable the entire header during transitions
            ZStack {
                // Background applied to the entire container
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
                
                // Content container with flip effect
                ZStack {
                    // List content with flip effect
                    ListContent(
                        viewModel: viewModel,
                        isNewItemFocused: _isNewItemFocused,
                        isEditing: $isEditing,
                        headerTitle: viewModel.headerTitle,
                        removeAllFocus: {
                            // Remove focus
                            isEditing = false
                            isNewItemFocused = false
                            isNotesFocused = false
                        }
                    )
                    .environmentObject(viewModel.counterManager)
                    // Apply clip shape to ensure content doesn't visually extend beyond boundaries
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16)) // Add for better hit testing
                    // Apply 3D flip effect and hide when flipped (back of card)
                    .opacity(viewModel.isShowingNotes ? 0 : 1)
                    .flipEffect(isFlipped: viewModel.isShowingNotes)
                    
                    // Notes content with flip effect
                    NotesView(
                        notes: Binding(
                            get: { viewModel.checklist.notes },
                            set: { _ in /* This is now handled by the onSave callback */ }
                        ),
                        isFocused: _isNotesFocused,
                        isEditing: $isEditing,
                        title: viewModel.headerTitle,
                        onSave: { viewModel.updateNotes($0) }
                    )
                    // Apply the same clip shape to notes view for consistency
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16)) // Add for better hit testing
                    // Apply 3D flip effect in opposite direction (negative Y axis)
                    .opacity(viewModel.isShowingNotes ? 1 : 0)
                    .flipEffect(isFlipped: !viewModel.isShowingNotes, axis: (0, -1, 0))
                }
                // Track the animation state to update the transition flag
                .onChange(of: viewModel.isShowingNotes) { _, _ in
                    // Reset transition flag after a delay to ensure animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isInViewTransition = false
                    }
                
                }
            }
        }
        .padding(.bottom, 0)
        .frame(maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
        )
        .preference(key: IsEditingPreferenceKey.self, value: isEditing)
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                focusManager.requestFocus(for: .easyList)
            }
        }
        .onChange(of: isNotesFocused) { oldValue, newValue in
            if newValue {
                focusManager.requestFocus(for: .easyList)
            }
        }
        .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if newValue != .easyList {
                isEditing = false
                isNewItemFocused = false
                isNotesFocused = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .alert("Item Limit Reached", isPresented: $viewModel.showingImportLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've reached the maximum limit of 99 items per day. Delete some items to add more.")
        }
        // Save when view disappears
        .onDisappear {
            viewModel.saveChecklist()
        }
        // Save when app backgrounds
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.saveChecklist()
        }
        // Listen for checklist updates using Combine
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewChecklistAvailable"))) { notification in
            guard let newChecklistDate = notification.object as? Date else { return }
            
            // Check if the notification is for our current date
            let calendar = Calendar.current
            if calendar.isDate(newChecklistDate, inSameDayAs: viewModel.date) {
                viewModel.reloadChecklist()
            }
        }
        .onAppear {
            // Listen for the plus button notification from BaseView
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("TriggerEasyListPlusButton"),
                object: nil,
                queue: .main
            ) { _ in
                onAddTap()
            }
        }
        .onDisappear {
            // Remove the notification observer
            NotificationCenter.default.removeObserver(self)
        }
    }
}
