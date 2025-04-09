import SwiftUI

// Define a clear editing state enum
enum EditingState: Equatable {
    case none
    case title
    case newSubitem
    case existingSubitem(UUID)
    
    var isFocused: Bool {
        self != .none
    }
}

struct ItemDetailsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: ItemDetailsViewModel
    @State private var newSubitemText = ""
    @State private var showingPopover = false
    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationActive = false
    @State private var isGroupSectionExpanded = false
    @FocusState private var isSubitemFieldFocused: Bool
    @State private var isEditingTitle = false
    @State private var editedTitleText = ""
    @FocusState private var isTitleFieldFocused: Bool
    @State private var editingSubitemId: UUID? //we use this as the initial variable to set editing when we first tap a subitem. This is important because subitems must transition from text to texteditors.
    @FocusState private var focusedSubitemId: UUID?
    @State private var borderOpacity: Double = 0
    
    // Add focus removal state
    private enum FocusRemovalState {
        case saving
        case clearingFocus
        case completed
    }
    @State private var focusRemovalState: FocusRemovalState?
    
    // State for drag and drop functionality
    @State private var draggedItem: Models.SubItem?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    // Consolidated focus management
    @State private var editingState: EditingState = .none
    @FocusState private var titleFocused: Bool
    @FocusState private var newSubitemFocused: Bool
    
    // Computed property to check if any field is focused
    private var isAnyFieldFocused: Bool {
        isSubitemFieldFocused || isTitleFieldFocused || focusedSubitemId != nil
    }
    
    // Function to synchronize focus state with editing state
    private func updateFocusState() {
        // First update the focus state
        // We set the previous editing state false after a delay so we can ensure the keyboard isn't retracted
        if focusRemovalState == FocusRemovalState.clearingFocus {
            return
        }
        
        focusRemovalState = FocusRemovalState.clearingFocus
        
        switch editingState {
        case .none:
            titleFocused = false
            newSubitemFocused = false
            focusedSubitemId = nil
            focusRemovalState = nil
            
        case .title:
            titleFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                newSubitemFocused = false
                focusedSubitemId = nil
                
                focusRemovalState = nil
            }
        case .newSubitem:
            newSubitemFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = false
                focusedSubitemId = nil
                
                focusRemovalState = nil
            }
        case .existingSubitem(let id):
            focusedSubitemId = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFocused = false
                newSubitemFocused = false
                
                focusRemovalState = nil
            }
        }
    }
    
    // Robust focus removal function
    private func removeAllFocus() {
        // Save any ongoing edits
        if case .title = editingState {
            saveTitle()
        }
        
        // Clear state first, then focus will follow
        editingState = .none
        updateFocusState()
    }
    
    @State private var dragOffset = CGSize.zero
    
    init(item: Models.ChecklistItem, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: ItemDetailsViewModel(item: item))
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                headerView
                titleView
                
                // Divider between header section and content
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal)
                
                // Main list content
                listContentView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.black
                    .opacity(0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                ZStack {
                    // Static border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                    
                    // Animated border
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(borderOpacity), lineWidth: 1.5)
                }
            )
            .offset(x: dragOffset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging from the left edge (first 88 points) and only to the right
                        if value.startLocation.x < 66 && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.startLocation.x < 66 && value.translation.width > 50 {
                            // Use animation to ensure smooth transition back to EasyListView
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = .zero
                        }
                    }
            )
        }
        .onAppear {
            viewModel.loadDetails()
            feedbackGenerator.prepare()
        }
        .onDisappear {
            // Save any ongoing edits
            if case .title = editingState {
                saveTitle()
            }
            
            // Remove focus which will trigger saves in subitems
            removeAllFocus()
            
            // Save changes when view disappears
            viewModel.saveChanges()
            
            // Post notification that item was updated
            NotificationCenter.default.post(
                name: Notification.Name("ItemDetailsUpdated"),
                object: viewModel.item.id
            )
        }
        // Monitor focus state changes
        .onChange(of: titleFocused) { _, isFocused in
            if !isFocused, case .title = editingState {
                saveTitle()
                editingState = .none
            }
        }
        .onChange(of: newSubitemFocused) { _, isFocused in
            if !isFocused, case .newSubitem = editingState {
                editingState = .none
            }
        }
        .onChange(of: focusedSubitemId) { _, focusedId in
            if focusedId == nil, case .existingSubitem = editingState {
                editingState = .none
            }
        }
        .preference(key: IsEditingPreferenceKey.self, value: editingState.isFocused)
    }
    
    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            // Checkbox
            checkboxButton
            
            // Metadata
            MetadataRowCompact(item: viewModel.item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("metadata-\(viewModel.item.id)-\(viewModel.item.groupId?.uuidString ?? "none")-\(viewModel.item.notification?.timeIntervalSince1970 ?? 0)-\(viewModel.item.isCompleted)")
                .animation(.easeInOut, value: viewModel.item.isCompleted)
            
            // Action buttons
            actionButtons
            
            // Menu and close buttons
            menuAndCloseButtons
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
    
    private var checkboxButton: some View {
        Button(action: {
            feedbackGenerator.impactOccurred()
            let wasCompleted = viewModel.item.isCompleted
            viewModel.toggleCompleted()
            
            // Only animate when completing, not uncompleting
            if !wasCompleted {
                // Trigger border animation
                borderOpacity = 0.4
                // Reset opacity after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        borderOpacity = 0
                    }
                }
            }
        }) {
            Image(systemName: viewModel.item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(viewModel.item.isCompleted ? .green : .gray)
                .font(.system(size: 24))
        }
        .buttonStyle(.plain)
    }
    
    private var actionButtons: some View {
        Group {
            if viewModel.canUndo {
                // Undo button
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    viewModel.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 4)
                .buttonStyle(.plain)
            }
            
            // Ellipsis menu button
            Button(action: {
                isGroupSectionExpanded = false
                showingPopover = true
            }) {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 4)
            .buttonStyle(.plain)
            .popover(isPresented: $showingPopover,
                     attachmentAnchor: .point(.center),
                     arrowEdge: .top) {
                PopoverContentView(
                    itemId: viewModel.item.id,
                    itemDate: viewModel.item.date,
                    itemNotification: viewModel.item.notification,
                    itemGroupId: viewModel.item.groupId,
                    isGroupSectionExpanded: $isGroupSectionExpanded,
                    onNotificationChange: { newNotification in
                        viewModel.updateNotification(newNotification)
                    },
                    onGroupChange: { newGroupId in
                        viewModel.updateGroup(newGroupId)
                    },
                    onDelete: {},
                    showDeleteOption: false
                )
                .presentationCompactAdaptation(.none)
            }
            
            // Add button - always show it
            Button(action: {
                feedbackGenerator.impactOccurred()
                if viewModel.item.subItems.count < 50 {
                    // First post notification to show and scroll to the field
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ScrollToNewSubitemRow"),
                        object: nil
                    )
                    
                    // First clear any current focus
                    /*
                    if editingState != .newSubitem {
                        removeAllFocus()
                    }
                     */
                    
                    // Then set new focus state
                    editingState = .newSubitem
                    
                    // Update focus after a short delay to ensure view is updated
                    //DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        updateFocusState()
                    //}
                }
            }) {
                Image(systemName: "plus")
                    .foregroundColor(viewModel.item.subItems.count >= 50 ? .white.opacity(0.3) : .white.opacity(0.6))
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 4)
            .buttonStyle(.plain)
            .disabled(viewModel.item.subItems.count >= 50)
            
            // Delete button
            Button(action: {
                feedbackGenerator.impactOccurred()
                removeAllFocus()
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 4)
            .buttonStyle(.plain)
            .popover(isPresented: $showingDeleteConfirmation, arrowEdge: .top) {
                SubitemDeleteConfirmationView(
                    isPresented: $showingDeleteConfirmation,
                    isConfirmationActive: $deleteConfirmationActive,
                    onDeleteAll: {
                        // Clear focus before deleting all subitems
                        removeAllFocus()
                        viewModel.deleteAllSubitems()
                    },
                    onDeleteCompleted: {
                        viewModel.deleteCompletedSubitems()
                    },
                    onDeleteIncomplete: {
                        viewModel.deleteIncompleteSubitems()
                    },
                    
                    feedbackGenerator: feedbackGenerator
                )
            }
        }
    }
    
    private var menuAndCloseButtons: some View {
        Group {
            if editingState.isFocused {
                // Done button
                Button(action: {
                    removeAllFocus()
                }) {
                    Text("Done")
                        .foregroundColor(.white)
                        .dynamicTypeSize(.small...DynamicTypeSize.large)
                }
            } else {
                // Close button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 18, weight: .medium))
                        .padding(6)
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    // Start editing title
    private func startEditingTitle() {
        editedTitleText = viewModel.item.title
        editingState = .title
        updateFocusState()
    }
    
    // Save title
    private func saveTitle() {
        if !editedTitleText.isEmpty {
            viewModel.updateTitle(editedTitleText)
        }
        updateFocusState()
    }
    
    // Title view component
    private var titleView: some View {
        ZStack {
            if case .title = editingState {
                // Editable title field
                TextEditor(text: $editedTitleText)
                    .font(.title3)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: 96)
                    .focused($titleFocused)
                    .onChange(of: editedTitleText) {_, newValue in
                        // Check for Enter key
                        if newValue.contains("\n") {
                            // Remove the newline character
                            editedTitleText = newValue.replacingOccurrences(of: "\n", with: "")
                            
                            // Save the title
                            saveTitle()
                            removeAllFocus()
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            .padding(.horizontal, 4)
                    )
            } else {
                // Static title text (tappable)
                Button(action: {
                    startEditingTitle()
                }) {
                    Text(viewModel.item.title)
                        .font(.title3)
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .strikethrough(viewModel.item.isCompleted, color: .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Main list content component
    private var listContentView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    List {
                        // New subitem row at the top, always included but will hide itself when not focused
                        if viewModel.item.subItems.count < 50 {
                            NewSubItemRow(
                                text: $newSubitemText,
                                isFocused: $newSubitemFocused,
                                onSubmit: { keepFocus in
                                    if !newSubitemText.isEmpty {
                                        viewModel.addSubitem(newSubitemText)
                                        newSubitemText = ""
                                        
                                        // After adding a subitem, maintain focus and keep the input field ready for more entry
                                        if keepFocus {
                                            editingState = .newSubitem
                                            updateFocusState()
                                        } else {
                                            removeAllFocus()
                                        }
                                        
                                        // Scroll to top to keep the input field visible
                                        DispatchQueue.main.async {
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                proxy.scrollTo("newSubItemRow", anchor: .top)
                                            }
                                        }
                                    } else {
                                        // If text is empty, just lose focus
                                        removeAllFocus()
                                    }
                                },
                                viewModel: viewModel,
                                onTap: {
                                    // When tapped, call onTap to update editing state
                                    editingState = .newSubitem
                                    updateFocusState()
                                }
                            )
                            .id("newSubItemRow")
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                        
                        ForEach(viewModel.item.subItems) { subitem in
                            SubItemView(
                                subitem: subitem,
                                viewModel: viewModel,
                                onToggle: {
                                    feedbackGenerator.impactOccurred()
                                    viewModel.toggleSubitemCompleted(subitemId: subitem.id)
                                },
                                onTap: {
                                    startEditingSubitem(subitem)
                                },
                                editingState: editingState,
                                focusedSubitemId: $focusedSubitemId
                            )
                            .id(subitem.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                        .onMove(perform: { indices, destination in
                            viewModel.moveSubitems(from: indices, to: destination)
                        })
                        
                        // Display limit reached message if needed
                        if viewModel.item.subItems.count >= 50 {
                            // Show message when limit is reached
                            Text("Maximum limit of 50 subitems reached.\nRemove some subitems to add more.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .id("subitemLimitMessage")
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                        }
                        
                        Color.clear.frame(height: 100)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        if case .newSubitem = editingState {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("newSubItemRow", anchor: .top)
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToNewSubitemRow"))) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            if viewModel.item.subItems.count < 50 {
                                proxy.scrollTo("newSubItemRow", anchor: .top)
                            } else {
                                proxy.scrollTo("subitemLimitMessage", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: newSubitemFocused) { oldValue, newValue in
                        if newValue {
                            // When field gets focus, scroll to it
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("newSubItemRow", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compact metadata row for header
private struct MetadataRowCompact: View {
    let item: Models.ChecklistItem
    @ObservedObject private var groupStore = GroupStore.shared
    
    private var hasGroup: Bool {
        return item.groupId != nil && groupStore.getGroup(by: item.groupId!) != nil
    }
    
    private var groupName: String? {
        guard let groupId = item.groupId else { return nil }
        return groupStore.getGroup(by: groupId)?.title
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasGroup, let groupTitle = groupName {
                HStack(spacing: 2) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .opacity(0.6)
                    Text(groupTitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let notification = item.notification {
                HStack(spacing: 2) {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .padding(.horizontal, 1)
                    
                    let isPastDue = notification < Date()
                    Text(formatNotificationTime(notification))
                        .font(.caption)
                        .foregroundColor(isPastDue ? .red.opacity(0.5) : .white.opacity(0.5))
                        .strikethrough(item.isCompleted, color: .gray)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .animation(.easeInOut(duration: 0.2), value: item.isCompleted)
                }
                .foregroundColor(notification < Date() ? .red.opacity(0.5) : .white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // Format notification time
    private func formatNotificationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Original Metadata row for compatibility
private struct MetadataRow: View {
    let item: Models.ChecklistItem
    @ObservedObject private var groupStore = GroupStore.shared
    
    private var hasGroup: Bool {
        return item.groupId != nil && groupStore.getGroup(by: item.groupId!) != nil
    }
    
    private var groupName: String? {
        guard let groupId = item.groupId else { return nil }
        return groupStore.getGroup(by: groupId)?.title
    }
    
    var body: some View {
        // Only show if there's a notification or group
        if item.notification != nil || hasGroup {
            HStack(spacing: 12) {
                if hasGroup, let groupTitle = groupName {
                    Text(groupTitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                if let notification = item.notification {
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill")
                            .font(.footnote)
                        
                        let isPastDue = notification < Date()
                        Text(formatNotificationTime(notification))
                            .font(.footnote)
                            .foregroundColor(isPastDue ? .red.opacity(0.5) : .white.opacity(0.5))
                            .strikethrough(item.isCompleted, color: .gray)
                            .lineLimit(1)  // Prevent notification time from wrapping
                            .layoutPriority(1)  // Add layout priority to ensure notification time gets space
                            .animation(.easeInOut(duration: 0.2), value: item.isCompleted)
                    }
                    .foregroundColor(notification < Date() ? .red.opacity(0.5) : .white.opacity(0.5))
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
        } else {
            // Empty spacer when no metadata to display
            Spacer().frame(height: 0)
        }
    }
    
    // Format notification time
    private func formatNotificationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Helper Methods
extension ItemDetailsView {
    
    // Subitem editing methods
    private func startEditingSubitem(_ subitem: Models.SubItem) {
        editingState = .existingSubitem(subitem.id)
        updateFocusState()
    }
}

// MARK: - NewSubItemRow Component
private struct NewSubItemRow: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: (Bool) -> Void
    let viewModel: ItemDetailsViewModel
    let onTap: () -> Void  // Add onTap callback
    
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "circle")
                .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0))
                .font(.system(size: 20))
                .zIndex(2)
                .padding(.top, 8)
            
            ZStack(alignment: .leading) {
                // Placeholder text
                if text.isEmpty {
                    Text("New subitem...")
                        .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0.7))
                        .padding(.leading, 4)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $text)
                    .foregroundColor(isFocused.wrappedValue ? .white : .gray)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused(isFocused)
                    .frame(maxHeight: 80)
                    .onChange(of: text) { oldValue, newValue in
                        // Check if user pressed return (added a newline)
                        if newValue.contains("\n") {
                            // Remove the newline character.
                            // By replacing \n with " ", we allow copy-pasted with \n values
                            if oldValue.count == 0 {
                                text = newValue.replacingOccurrences(of: "\n", with: " ")
                                
                                // But now that we replace \n with " ", we need to make sure we're not just submitting a " " field.
                                // An empty field that a users presses return in should just remove focus and not submit anything.
                                if text.count <= 1 {
                                    text = ""
                                    isFocused.wrappedValue = false
                                    return
                                }
                            } else {
                                text = oldValue
                            }
                            
                            // Submit if text is not empty
                            if !text.isEmpty {
                                onSubmit(true)
                            } else {
                                isFocused.wrappedValue = false
                            }
                        }
                    }
                    .onChange(of: isFocused.wrappedValue) { oldValue, newValue in
                        // When focus is lost, save the subitem if there's text
                        if !text.isEmpty {
                            onSubmit(false)
                        }
                        
                        // When focus is gained, update editing state
                        if newValue {
                            onTap()  // This will update the editing state in the parent
                        }
                    }
            }
            .frame(width: UIScreen.main.bounds.width * 0.80, alignment: .topLeading)
            .clipped(antialiased: true)
            .padding(.leading, 4)
            .zIndex(1)
            .accessibilityAddTraits(.isKeyboardKey)
            .contentShape(Rectangle())  // Make entire area tappable
            .onTapGesture {
                // When tapped, call onTap to update editing state
                onTap()
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .padding(.vertical, (isFocused.wrappedValue || viewModel.item.subItems.isEmpty) ? 4 : 0)
        .padding(.leading, 16)
        // Only show when focused OR list is empty
        .opacity((isFocused.wrappedValue || viewModel.item.subItems.isEmpty) ? 1 : 0)
        // Explicitly set height to 0 when hidden
        .frame(height: (isFocused.wrappedValue || viewModel.item.subItems.isEmpty) ? nil : 0, alignment: .top)
        // Hide completely when not visible
        .accessibility(hidden: !(isFocused.wrappedValue || viewModel.item.subItems.isEmpty))
    }
}

// MARK: - SubItemView Component
private struct SubItemView: View {
    let subitem: Models.SubItem
    let viewModel: ItemDetailsViewModel
    let onToggle: () -> Void
    let onTap: () -> Void
    let editingState: EditingState
    @FocusState.Binding var focusedSubitemId: UUID?
    @State private var editedText: String
    @State private var isPreloading = false
    
    // Add state for swipe
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    private let deleteWidth: CGFloat = 75
    
    init(subitem: Models.SubItem,
         viewModel: ItemDetailsViewModel,
         onToggle: @escaping () -> Void,
         onTap: @escaping () -> Void,
         editingState: EditingState,
         focusedSubitemId: FocusState<UUID?>.Binding) {
        self.subitem = subitem
        self.viewModel = viewModel
        self.onToggle = onToggle
        self.onTap = onTap
        self.editingState = editingState
        self._focusedSubitemId = focusedSubitemId
        self._editedText = State(initialValue: subitem.title)
    }
    
    // Helper to determine if this specific subitem is being edited
    private var isEditing: Bool {
        if case .existingSubitem(let id) = editingState, id == subitem.id {
            return true
        }
        return false
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button background and button - position off screen when not swiped
            Rectangle()
                .fill(Color.red)
                .frame(width: deleteWidth)
                .offset(x: offset < 0 || isSwiped ? 0 : deleteWidth)
            
            Button(action: {
                withAnimation {
                    offset = 0
                    isSwiped = false
                    // Clear focus if this subitem is currently being edited
                    if isEditing {
                        focusedSubitemId = nil
                    }
                    viewModel.deleteSubitem(subitem.id)
                }
            }) {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: deleteWidth)
            }
            .disabled(!isSwiped && offset >= 0)
            .contentShape(Rectangle().size(
                width: isSwiped || offset < 0 ? deleteWidth : 0,
                height: isSwiped || offset < 0 ? 44 : 0
            ))
            .offset(x: offset < 0 || isSwiped ? 0 : deleteWidth)
            
            // Main content
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: subitem.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(subitem.isCompleted ? .green : .gray)
                        .font(.system(size: 20))
                        .padding(.top, 8)
                }
                .buttonStyle(.plain)
                
                ZStack {
                    if !isEditing || isPreloading {
                        Text(subitem.title)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(4)
                            .strikethrough(subitem.isCompleted, color: .gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 5)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isPreloading = true
                                DispatchQueue.main.async {
                                    onTap()
                                    isPreloading = false
                                }
                            }
                    }
                    
                    if isEditing || isPreloading {
                        TextEditor(text: $editedText)
                            .font(.body)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.vertical, 0)
                            .padding(.leading, 0)
                            .focused($focusedSubitemId, equals: subitem.id)
                            .onChange(of: editedText) { oldValue, newValue in
                                if newValue.contains("\n") {
                                    editedText = oldValue
                                    // Save changes when Enter is pressed (since this doesn't destroy the view).
                                    saveChanges()
                                    focusedSubitemId = nil
                                }
                            }
                            .onDisappear {
                                saveChanges()
                            }
                            .opacity(isPreloading ? 0 : 1)
                            .onChange(of: isPreloading) { oldValue, newValue in
                                if oldValue == true && newValue == false && isEditing {
                                    focusedSubitemId = subitem.id
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .offset(x: offset)
        }
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    // Don't allow dragging if this subitem is being edited
                    
                    // Calculate the angle of the drag to determine if it's horizontal enough
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    let translation = value.translation.width
                    
                    // Only respond if:
                    // 1. The gesture is primarily horizontal (horizontal movement is at least 3x the vertical movement)
                    // 2. Has moved at least 25 points
                    if (horizontalAmount > verticalAmount * 2) && (translation < -50) {
                        guard !isEditing else { return }
                        // Only allow left swipe (negative values)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            // Add some resistance to the drag
                            offset = max(-deleteWidth, translation)
                        }
                    } else if isSwiped {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = 0
                            isSwiped = false
                        }
                    }
                }
                .onEnded { value in
                    // Don't allow dragging if this subitem is being edited
                    guard !isEditing else { return }
                    
                    let translation = value.translation.width
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Only complete the swipe if:
                    // 1. It was primarily horizontal
                    // 2. Moved enough distance (in the negative direction)
                    // 3. Has sufficient velocity or distance
                    if (horizontalAmount > verticalAmount * 2) && (translation < -100) {
                        guard !isEditing else { return }
                        // Determine if we should open or close based on velocity and position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = -deleteWidth
                            isSwiped = true
                        }
                    } else {
                        // If the gesture wasn't horizontal enough, reset position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = 0
                            isSwiped = false
                        }
                    }
                }
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        // Add onDisappear handler for the entire view to clean up focus
        .onDisappear {
            // If this subitem was being edited when it disappeared,
            // make sure to clear the focus state in the parent
            if isEditing {
                focusedSubitemId = nil
            }
        }
    }
    
    // Helper to save changes to a subitem
    private func saveChanges() {
        if editedText.isEmpty {
            viewModel.deleteSubitem(subitem.id)
        } else if editedText != subitem.title {
            viewModel.updateSubitemTitle(subitem.id, newTitle: editedText)
        }
    }
}

// Add DeleteConfirmationView for subitems before the ItemDetailsView struct
private struct SubitemDeleteConfirmationView: View {
    @Binding var isPresented: Bool
    @Binding var isConfirmationActive: Bool
    let onDeleteAll: () -> Void
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
            // Delete All Subitems Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if isConfirmationActive && selectedOption == .all {
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    isConfirmationActive = false
                    onDeleteAll()
                    isPresented = false
                } else {
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
            
            // Delete Completed Subitems Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if isConfirmationActive && selectedOption == .completed {
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    isConfirmationActive = false
                    onDeleteCompleted()
                    isPresented = false
                } else {
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
            
            // Delete Incomplete Subitems Option
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if isConfirmationActive && selectedOption == .incomplete {
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    isConfirmationActive = false
                    onDeleteIncomplete()
                    isPresented = false
                } else {
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

