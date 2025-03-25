import SwiftUI

// Add preference key at the top of the file
struct IsEditingPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
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
        .onDisappear {
            // Reset timer and confirmation state when popover closes
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
                    }
                    .frame(minWidth: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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

// MARK: - Time Picker View
struct TimePickerView: View {
    @Binding var selectedTime: Date
    let onBack: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
            }
            .padding(.trailing, 8)
            
            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.horizontal)
    }
}

// MARK: - Checklist Item Row Component

struct ChecklistItemRow: View {
    let item: Models.ChecklistItem
    let isEditing: Bool
    let onToggle: () -> Void
    let onSubmit: (String) -> Void
    let onLoseFocus: (String) -> Void
    let onStartEdit: () -> Void
    let onTextChange: (String) -> Void
    let onNotificationChange: ((Date?) -> Void)?
    let onGroupChange: ((UUID?) -> Void)?
    @State private var text: String
    @State private var showingPopover = false
    @State private var isDeleting = false
    @State private var opacity: Double = 1.0
    @State private var isGroupSectionExpanded: Bool = false //we need this binding to prevent bug behavior in the group dropdown (closing)
    @ObservedObject private var groupStore = GroupStore.shared
    
    init(item: Models.ChecklistItem, isEditing: Bool, onToggle: @escaping () -> Void, onSubmit: @escaping (String) -> Void, onLoseFocus: @escaping (String) -> Void, onStartEdit: @escaping () -> Void, onTextChange: @escaping (String) -> Void, onNotificationChange: ((Date?) -> Void)? = nil, onGroupChange: ((UUID?) -> Void)? = nil) {
        self.item = item
        self.isEditing = isEditing
        self.onToggle = onToggle
        self.onSubmit = onSubmit
        self.onLoseFocus = onLoseFocus
        self.onStartEdit = onStartEdit
        self.onTextChange = onTextChange
        self.onNotificationChange = onNotificationChange
        self.onGroupChange = onGroupChange
        _text = State(initialValue: item.title)
    }
    
    // Get the group color for the item
    private var groupColor: Color? {
        // Use the direct group reference if available
        if let group = item.group, group.hasColor {
            return Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue)
        }
        
        // Fallback to looking up by ID for backward compatibility
        guard let groupId = item.groupId,
              let group = groupStore.getGroup(by: groupId) else {
            return nil
        }
        
        // Use the direct color properties and hasColor flag
        if group.hasColor {
            return Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue)
        } else {
            return nil
        }
    }
    
    var body: some View {
        HStack(alignment: .center) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .green : .gray)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .alignmentGuide(.firstTextBaseline) { d in
                d[VerticalAlignment.center]
            }
            
            VStack(alignment: .leading, spacing: 0) {
                CustomTextField(text: $text, onReturn: {
                    onSubmit(text)
                }, onTextChange: { newText in
                    onTextChange(newText)
                })
                .foregroundColor(.white)
                .strikethrough(item.isCompleted, color: .gray)
                .dynamicTypeSize(.xSmall...DynamicTypeSize.large)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if !isEditing {
                            onStartEdit()
                        }
                    }
                )
                .frame(width: UIScreen.main.bounds.width * 0.81, alignment: isEditing ? .topTrailing : .topLeading)
                .clipped(antialiased: true)
                
                // Subtitles row (notification and group)
                if (item.notification != nil && !item.isCompleted) || item.groupId != nil {
                    HStack(spacing: 8) {
                        // Group subtitle (show even if completed)
                        if let group = item.group {
                            Text(group.title)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        } else if let groupId = item.groupId, let group = groupStore.getGroup(by: groupId) {
                            // Fallback for backward compatibility
                            Text(group.title)
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        // Notification subtitle (only show if not completed)
                        if item.notification != nil && !item.isCompleted {
                            HStack(spacing: 2) {
                                Image(systemName: "bell.fill")
                                    .font(.footnote)
                                
                                let isPastDue = item.notification! < Date()
                                Text(formatNotificationTime(item.notification!))
                                    .font(.footnote)
                                    .foregroundColor(isPastDue ? .red.opacity(0.5) : .white.opacity(0.5))
                            }
                            .foregroundColor(item.notification! < Date() ? .red.opacity(0.5) : .white.opacity(0.5))
                        }
                    }
                }
            }
            
            // Three dots button with popover
            Button(action: {
                isGroupSectionExpanded = false
                showingPopover = true
            }) {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 16))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: self.$showingPopover,
                     attachmentAnchor: .point(.center),
                     arrowEdge: .trailing) {
                PopoverContentView(
                    item: item,
                    isGroupSectionExpanded: $isGroupSectionExpanded,
                    onNotificationChange: { newNotification in
                        // Directly save notification changes
                        if let onNotificationChange = onNotificationChange {
                            onNotificationChange(newNotification)
                        }
                    },
                    onGroupChange: { newGroupId in
                        // Directly save group changes
                        if let onGroupChange = onGroupChange {
                            onGroupChange(newGroupId)
                        }
                    },
                    onDelete: { 
                        isDeleting = true
                        
                        // Start animation immediately before dismissing popover
                        withAnimation(.easeOut(duration: 0.25)) {
                            opacity = 0.1
                        }
                        // Close the popover immediately when delete is confirmed
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onLoseFocus("")
                            showingPopover = false //this slows things down, so keep it in here so it executes AFTER
                        }
                    }
                )
                .presentationCompactAdaptation(.none)
            }
            .onDisappear {
                isGroupSectionExpanded = false  // Contract group section when popover closes
            }
            .padding(.leading, -8)
        }
        .listRowBackground(
            ZStack {
                if isDeleting {
                    Color.red.opacity(0.95 * opacity)
                } else if let color = groupColor {
                    // Apply a slight tint based on the group color only if the group has a color set
                    color.opacity(0.25)
                } else {
                    Color.clear
                }
            }
        )
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .foregroundColor(.white)
        .padding(.vertical, 4)
        .padding(.leading, 8)
        .opacity(opacity) // Apply opacity for fade animation
    }
    
    // Helper function to format notification time
    private func formatNotificationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
        .padding(.leading, 16)
    }
}

// MARK: - List Content Component

struct ListContent: View {
    @ObservedObject var viewModel: EasyListViewModel
    @Binding var editingItemId: UUID?
    @State private var newItemText: String = ""
    @FocusState var focusedItemId: UUID?
    @FocusState var isNewItemFocused: Bool
    @Binding var isEditing: Bool
    @EnvironmentObject private var focusManager: FocusManager
    let focusCoordinator: PlannerFocusCoordinator
    let headerTitle: String
    let availableHeight: CGFloat
    let removeAllFocus: () -> Void
    
    // Haptic feedback generator for item toggling
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // MARK: - Item Action Handlers
    private func handleItemToggle(_ item: Models.ChecklistItem) {
        // Trigger haptic feedback when toggling item completion
        feedbackGenerator.impactOccurred()
        viewModel.toggleItem(item)
    }
    
    private func handleItemLoseFocus(_ item: Models.ChecklistItem, text: String) {
        if text.isEmpty {
            deleteItem(item)
            // Clean up focus state when an item is deleted
            if focusedItemId == item.id {
                DispatchQueue.main.async {
                    removeAllFocus()
                }
            }
        }
    }
    
    private func handleItemStartEdit(_ item: Models.ChecklistItem) {
        startEditing(item)
    }
    
    private func handleItemTextChange(_ item: Models.ChecklistItem, newText: String) {
        viewModel.updateItem(item, with: newText)
    }
    
    private func handleItemReturn(_ item: Models.ChecklistItem, proxy: ScrollViewProxy) {
        if let currentIndex = viewModel.items.firstIndex(where: { $0.id == item.id }) {
            if currentIndex < viewModel.items.count - 1 {
                let nextItem = viewModel.items[currentIndex + 1]
                startEditing(nextItem)
                withAnimation {
                    proxy.scrollTo(nextItem.id, anchor: .center)
                }
            } else {
                editingItemId = nil
                if !viewModel.isItemLimitReached {
                    isNewItemFocused = true
                    withAnimation {
                        proxy.scrollTo("newItemRow", anchor: .center)
                    }
                }
            }
        }
    }
    
    private func handleNewItemSubmit(_ proxy: ScrollViewProxy) {
        if !newItemText.isEmpty {
            viewModel.addItem(newItemText)
            newItemText = ""
            if !viewModel.isItemLimitReached {
                isNewItemFocused = true
                // Add scroll animation when submitting new item
                withAnimation {
                    proxy.scrollTo("newItemRow", anchor: .center)
                }
            }
        }
    }
    
    private func handleMoveItems(from: IndexSet, to: Int) {
        viewModel.moveItems(from: from, to: to)
    }
    
    private func handleNotificationChange(_ item: Models.ChecklistItem, newTime: Date?) {
        viewModel.updateItemNotification(item, with: newTime)
    }
    
    private func handleGroupChange(_ item: Models.ChecklistItem, groupId: UUID?) {
        viewModel.updateItemGroup(item, with: groupId)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                List {
                    ForEach(viewModel.items) { item in
                        makePlannerItemView(for: item)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .padding(.horizontal, 0)
                            .padding(.vertical, 0)
                    }
                    .onMove { from, to in
                        handleMoveItems(from: from, to: to)
                    }
                    
                    if !viewModel.isItemLimitReached {
                        NewItemRow(
                            text: $newItemText,
                            isFocused: $isNewItemFocused,
                            onSubmit: { handleNewItemSubmit(proxy) }
                        )
                        .id("newItemRow")
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
                .onChange(of: focusedItemId) { oldValue, newValue in
                    print("[ListContent] focusedItemId changed from \(String(describing: oldValue)) to \(String(describing: newValue))")
                    if let id = newValue {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        print("[ListContent] Requesting focus for EasyList")
                        focusManager.requestFocus(for: .easyList)
                    }
                    if newValue == nil {
                        print("[ListContent] Setting editingItemId to nil due to focusedItemId being nil")
                        editingItemId = nil
                        // Use the coordinator to properly remove focus from all items
                        focusCoordinator.removeAllFocus()
                    }
                    updateEditingState()
                    print("[ListContent] isEditing is now: \(isEditing)")
                }
                .onChange(of: isNewItemFocused) { oldValue, newValue in
                    print("[ListContent] isNewItemFocused changed from \(oldValue) to \(newValue)")
                    if newValue && !viewModel.isItemLimitReached {
                        withAnimation {
                            proxy.scrollTo("newItemRow", anchor: .center)
                        }
                        print("[ListContent] Requesting focus for EasyList")
                        focusManager.requestFocus(for: .easyList)
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
        // Constrain the entire ZStack to the available height
        .frame(height: availableHeight)
        .onChange(of: editingItemId) { oldValue, newValue in
            print("[ListContent] editingItemId changed from \(String(describing: oldValue)) to \(String(describing: newValue))")
            if let id = newValue {
                print("[ListContent] Setting focusedItemId to \(id)")
                focusedItemId = id
            }
            updateEditingState()
            print("[ListContent] isEditing updated to: \(isEditing)")
        }
        .onChange(of: focusedItemId) { oldValue, newValue in
            print("[ListContent] focusedItemId changed (outer) from \(String(describing: oldValue)) to \(String(describing: newValue))")
            if newValue == nil {
                print("[ListContent] Setting editingItemId to nil due to focusedItemId being nil (outer)")
                editingItemId = nil
            }
            updateEditingState()
            print("[ListContent] isEditing updated to: \(isEditing) (outer)")
        }
        .onChange(of: isNewItemFocused) { oldValue, newValue in
            print("[ListContent] isNewItemFocused changed (outer) from \(oldValue) to \(newValue)")
            if !newValue && !newItemText.isEmpty {
                viewModel.addItem(newItemText)
                newItemText = ""
            }
            updateEditingState()
            print("[ListContent] isEditing updated to: \(isEditing) (outer)")
        }
        .onChange(of: isEditing) { oldValue, newValue in
            if !newValue {
                let emptyItems = viewModel.items.enumerated().filter { $0.element.title.isEmpty }
                if !emptyItems.isEmpty {
                    viewModel.deleteItems(at: IndexSet(emptyItems.map { $0.offset }))
                }
            }
        }
        .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if newValue != .easyList {
                finishEditing()
            }
        }
        .onChange(of: focusCoordinator.focusedItemId) { _, newId in
            print("[ListContent] focusCoordinator.focusedItemId changed to: \(String(describing: newId))")
            editingItemId = newId
            updateEditingState()
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
        let newIsEditing = focusedItemId != nil || isNewItemFocused || editingItemId != nil
        print("[ListContent] updateEditingState: focusedItemId=\(String(describing: focusedItemId)), isNewItemFocused=\(isNewItemFocused), editingItemId=\(String(describing: editingItemId))")
        isEditing = newIsEditing
    }
    
    private func startEditing(_ item: Models.ChecklistItem) {
        print("[ListContent] startEditing called for item: \(item.id)")
        editingItemId = item.id
    }
    
    private func saveEdit(for item: Models.ChecklistItem, text: String) {
        viewModel.updateItem(item, with: text)
        editingItemId = nil
    }
    
    private func deleteItem(_ item: Models.ChecklistItem) {
        if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
            // Check if this is the currently focused item
            let isFocusedItem = focusedItemId == item.id
            
            viewModel.deleteItems(at: IndexSet([index]))
            editingItemId = nil
            
            // If we deleted the focused item, clean up all focus state
            if isFocusedItem {
                DispatchQueue.main.async {
                    removeAllFocus()
                }
            }
        }
    }
    
    // Helper function to create PlannerItemView with all necessary callbacks
    private func makePlannerItemView(for item: Models.ChecklistItem) -> some View {
        PlannerItemView.create(
            item: item,
            focusCoordinator: focusCoordinator,
            externalFocusState: $editingItemId,
            onToggle: {
                viewModel.toggleItem(item)
            },
            onTextChange: { newText in
                viewModel.updateItem(item, with: newText)
            },
            onLoseFocus: { text in
                // Only save non-empty items when losing focus
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.updateItem(item, with: text)
                } else {
                    handleItemLoseFocus(item, text: "")
                }
            },
            onAddSubItem: { text in
                // Create a new updated item with the subitem
                var updatedItem = item
                let newSubItem = Models.SubItem(
                    id: UUID(),
                    title: text,
                    isCompleted: false
                )
                updatedItem.subItems.append(newSubItem)
                viewModel.updateItem(updatedItem, with: updatedItem.title)
            },
            onSubItemToggle: { subItemId in
                // Handle subitem toggle
                var updatedItem = item
                updatedItem.toggleSubItem(withId: subItemId)
                viewModel.updateItem(updatedItem, with: updatedItem.title)
            },
            onSubItemTextChange: { subItemId, newText in
                // Handle subitem text change
                var updatedItem = item
                updatedItem.updateSubItem(withId: subItemId, newTitle: newText)
                viewModel.updateItem(updatedItem, with: updatedItem.title)
            },
            onNotificationChange: { date in
                viewModel.updateItemNotification(item, with: date)
            },
            onGroupChange: { groupId in
                viewModel.updateItemGroup(item, with: groupId)
            }
        )
        .id(item.id)
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
                }
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .padding(.horizontal, 4)
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
                        .onChange(of: selectedDate) { oldValue, newValue in
                            selectedDate = newValue
                        }
                    
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
                    }
                }
                .background(Color.black.opacity(0.3))
                .cornerRadius(8)
                .padding(.horizontal, 4)
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
    @StateObject private var viewModel: EasyListViewModel
    @State private var editingItemId: UUID?
    @State private var isEditing: Bool = false
    @FocusState private var focusedItemId: UUID?
    @FocusState private var isNewItemFocused: Bool
    @FocusState private var isNotesFocused: Bool
    @EnvironmentObject private var focusManager: FocusManager
    @ObservedObject private var groupStore = GroupStore.shared
    @StateObject private var focusCoordinator = PlannerFocusCoordinator()
    
    init(date: Date = Date()) {
        _viewModel = StateObject(wrappedValue: EasyListViewModel(date: date))
    }
    
    private func RemoveAllFocus() {
        print("[EasyListView] RemoveAllFocus called")
        if !focusManager.isEasyListFocused {
            print("[EasyListView] RemoveAllFocus returned early")
            return
        }
        // First remove coordinator focus which will trigger PlannerItemView focus removal
        focusCoordinator.removeAllFocus()
        // Then remove global focus which will prevent re-entry into EasyList
        focusManager.removeAllFocus()
        // Finally clear local focus states
        focusedItemId = nil
        isNewItemFocused = false
        isNotesFocused = false
        isEditing = false
    }
    
    // Helper method to reload the checklist
    private func reloadChecklistData() {
        Task {
            await MainActor.run {
                viewModel.reloadChecklist()
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            EasyListHeader(
                title: viewModel.headerTitle,
                isEditing: isEditing,
                showingNotes: viewModel.isShowingNotes,
                onDone: RemoveAllFocus,
                onNotesToggle: {
                    RemoveAllFocus()
                    withAnimation(.easeInOut(duration: 0.5)) {
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
                    
                    // Content container with rotation effects
                    ZStack {
                        // List content with rotation
                        ZStack {
                            ListContent(
                                viewModel: viewModel,
                                editingItemId: $editingItemId,
                                focusedItemId: _focusedItemId,
                                isNewItemFocused: _isNewItemFocused,
                                isEditing: $isEditing,
                                focusCoordinator: focusCoordinator,
                                headerTitle: viewModel.headerTitle,
                                availableHeight: geometry.size.height,
                                removeAllFocus: RemoveAllFocus
                            )
                            // Apply clip shape to ensure content doesn't visually extend beyond boundaries
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .rotation3DEffect(
                            .degrees(viewModel.isShowingNotes ? 180 : 0),
                            axis: (x: 0.0, y: 1.0, z: 0.0)
                        )
                        .opacity(viewModel.isShowingNotes ? 0 : 1)
                        
                        // Notes content with rotation
                        ZStack {
                            NotesView(
                                notes: Binding(
                                    get: { viewModel.checklist.notes },
                                    set: { viewModel.updateNotes($0) }
                                ),
                                isFocused: _isNotesFocused,
                                isEditing: $isEditing,
                                title: viewModel.headerTitle,
                                onSave: { viewModel.updateNotes($0) }
                            )
                            // Apply the same clip shape to notes view for consistency
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .rotation3DEffect(
                            .degrees(viewModel.isShowingNotes ? 0 : -180),
                            axis: (x: 0.0, y: 1.0, z: 0.0)
                        )
                        .opacity(viewModel.isShowingNotes ? 1 : 0)
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
                RemoveAllFocus()
            }
        }
        .onChange(of: groupStore.lastGroupUpdateTimestamp) { oldValue, newValue in
            reloadChecklistData()
        }
        .alert("Item Limit Reached", isPresented: $viewModel.showingImportLimitAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You've reached the maximum limit of 99 items per day. Delete some items to add more.")
        }
    }
}
