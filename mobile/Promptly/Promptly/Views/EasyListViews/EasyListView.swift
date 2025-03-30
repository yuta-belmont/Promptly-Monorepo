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

// MARK: - Custom TextField Component
// Remove CustomTextField implementation since it's now in its own file

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
    let currentDate: Date
    
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
                if !showingNotes {
                    Button(action: {
                        onDone() // Remove focus
                        feedbackGenerator.impactOccurred()
                        showingDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
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
                        feedbackGenerator.impactOccurred()
                        showingImportPopover = true
                    }) {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(.white)
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
                
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    onNotesToggle()
                }) {
                    Image(systemName: "arrow.2.squarepath")
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(showingNotes ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingNotes)
                }
                if isEditing {
                    Button(action: {
                        // Add haptic feedback before calling onDone
                        feedbackGenerator.prepare()
                        feedbackGenerator.impactOccurred()
                        onDone()
                    }) {
                        Text("Done")
                            .foregroundColor(.white)
                            .dynamicTypeSize(.small...DynamicTypeSize.large)
                            //.padding(.bottom, ) // Match the padding used by the image buttons
                    }
                    .frame(minWidth: 44)
                }
            }
        }
        .padding(.horizontal, 20)
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
    
    var body: some View {
        HStack {
            Image(systemName: "circle")
                .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0))
                .font(.system(size: 22))
                .zIndex(2)
            
            CustomTextField(
                text: $text,
                textColor: isFocused.wrappedValue ? .white : .gray,
                placeholder: isFocused.wrappedValue ? "New item" : "Add new item...",
                placeholderColor: .gray,
                onReturn: {
                    if !text.isEmpty {
                        onSubmit()
                    } else {
                        isFocused.wrappedValue = false
                    }
                }
            )
            .foregroundColor(isFocused.wrappedValue ? .white : .gray)
            .focused(isFocused)
            .frame(width: UIScreen.main.bounds.width * 0.80, alignment: .topTrailing)
            .clipped(antialiased: true)
            .padding(.leading, 4)
            .zIndex(1)
            // Make sure the text field has higher priority for keyboard focus
            .accessibilityAddTraits(.isKeyboardKey)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
        .padding(.leading, 16)
        // Add a minimum height to ensure it's always fully visible
        .frame(minHeight: 44)
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
    let availableHeight: CGFloat
    let removeAllFocus: () -> Void
    
    // Haptic feedback generator for item toggling
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Consolidated scroll helper function
    private func scrollToNewItem(_ proxy: ScrollViewProxy) {
         // Delay the first scroll by 0.1 seconds, then animate for 0.1 seconds
         DispatchQueue.main.asyncAfter(deadline: .now()) {
             withAnimation(.easeInOut(duration: 0.1)) {
                 proxy.scrollTo("newItemRow", anchor: .center)
         
             }
        }
    }
    
    private func handleNewItemSubmit(proxy: ScrollViewProxy) {
        if !newItemText.isEmpty {
            viewModel.addItem(newItemText)
            newItemText = ""
            if !viewModel.isItemLimitReached {
                isNewItemFocused = true
                scrollToNewItem(proxy)
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
                    ForEach(viewModel.items, id: \.id) { item in
                        makePlannerItemView(for: item)
                            .id("item-\(item.id.uuidString)-\(item.isCompleted)-\(item.title.hashValue)")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)
                    }
                    .onMove { from, to in
                        handleMoveItems(from: from, to: to)
                    }
                    .id("items-\(viewModel.date.timeIntervalSince1970)-\(viewModel.items.count)")
                    
                    if !viewModel.isItemLimitReached {
                        NewItemRow(
                            text: $newItemText,
                            isFocused: $isNewItemFocused,
                            onSubmit: { handleNewItemSubmit(proxy: proxy) }
                        )
                        .id("newItemRow")
                        .listRowSeparator(.hidden)
                    }
                    
                    Color.clear.frame(height: 44)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // Constrain the List to exactly match the available height
                .frame(height: availableHeight)
                // Use animation with structurally significant values only
                .animation(.easeInOut(duration: 0.2), value: viewModel.items.count)
                .environment(\.defaultMinListRowHeight, 0) // Minimize row height calculations
                .onChange(of: isNewItemFocused) { oldValue, newValue in
                    // Only handle focus management
                    if newValue && !viewModel.isItemLimitReached {
                        focusManager.requestFocus(for: .easyList)
                    }
                    
                    // Handle saving when losing focus
                    if !newValue && oldValue && !newItemText.isEmpty {
                        viewModel.addItem(newItemText)
                        newItemText = ""
                    }
                    
                    // Update editing state
                    updateEditingState()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                    //Only scroll when the keyboard has completely finished appearing
                    if isNewItemFocused {
                        scrollToNewItem(proxy)
                    }
                }
            }
            
            EasyListFooter(
                completedCount: viewModel.items.filter(\.isCompleted).count,
                totalCount: viewModel.items.count
            )
            .opacity(isEditing ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: isEditing)
        }
        .onChange(of: isEditing) { oldValue, newValue in
            if !newValue {
                let emptyItems = viewModel.items.enumerated().filter { $0.element.title.isEmpty }
                if !emptyItems.isEmpty {
                    viewModel.deleteItems(at: IndexSet(emptyItems.map { $0.offset }))
                }
                focusManager.isEasyListFocused = newValue
            }
        }
        .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if newValue != .easyList {
                finishEditing()
            }
        }
        .manageFocus(for: .easyList)
    }
    
    func finishEditing() {
        if !newItemText.isEmpty {
            viewModel.addItem(newItemText)
            newItemText = ""
        }
        isNewItemFocused = false
    }
    
    private func updateEditingState() {
        isEditing = isNewItemFocused
    }
    
    private func deleteItem(_ item: Models.ChecklistItem) {
        if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
            viewModel.deleteItems(at: IndexSet([index]))
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
                //print("EasyListView - onToggleItem - updating notification with: item.date=\(item.date), //item.notification=\(String(describing: item.notification))")
                viewModel.updateItemNotification(itemId: itemId, with: itemNotification)
            },
            onToggleSubItem: { mainItemId, subItemId, isCompleted in
                // Update the sub-item in the EasyListViewModel
                viewModel.toggleSubItemCompletion(mainItemId, subItemId: subItemId, isCompleted: isCompleted)
                // No need to post notification - view handles its own state
            },
            onLoseFocus: { text in
                // Only used for deletion through the menu
                if text.isEmpty {
                    deleteItem(item)
                }
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
            }
        )
        // Individual ID is now set on the row above
    }
}

// MARK: - Footer Component

struct EasyListFooter: View {
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        ZStack {
            // Left side content
            HStack {
                Text("\(completedCount)/\(totalCount) completed")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.ultraThinMaterial.opacity(0.9))
                    )
                Spacer()
            }
            
            // Right side content
            HStack {
                Spacer()
                if totalCount > 0 {
                    ProgressView(value: Double(completedCount), total: Double(totalCount))
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                        .frame(width: 80)
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
    @State private var showPreviousDayOptions = false
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
    
    init() {
        // No need to create a view model here anymore
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
                },
                onNotesToggle: {
                    // Remove focus
                    isEditing = false
                    isNewItemFocused = false
                    isNotesFocused = false
                    
                    // Toggle notes view with flip animation
                    withAnimation(.easeInOut(duration: 0.4)) {
                        viewModel.toggleNotesView()
                    }
                },
                onImport: { sourceDate, importIncompleteOnly in
                    viewModel.importItems(from: sourceDate, importIncompleteOnly: importIncompleteOnly)
                },
                onDeleteAll: {
                    viewModel.deleteAllItems()
                },
                onDeleteCompleted: {
                    viewModel.deleteCompletedItems()
                },
                onDeleteIncomplete: {
                    viewModel.deleteIncompleteItems()
                },
                currentDate: viewModel.date
            )
            
            // Use GeometryReader to coordinate the size of the background and the scrollable content
            GeometryReader { geometry in
                ZStack {
                    // Background applied to the entire container
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.5))
                        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
                    
                    // Content container with flip effect
                    ZStack {
                        // List content with flip effect
                        ListContent(
                            viewModel: viewModel,
                            isNewItemFocused: _isNewItemFocused,
                            isEditing: $isEditing,
                            headerTitle: viewModel.headerTitle,
                            availableHeight: geometry.size.height,
                            removeAllFocus: {
                                // Remove focus
                                isEditing = false
                                isNewItemFocused = false
                                isNotesFocused = false
                            }
                        )
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
                    // Constrain the content to the available space
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .padding(.bottom, 0)
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
        .onAppear() {
           // viewModel.reloadChecklist()
        }
    }
}
