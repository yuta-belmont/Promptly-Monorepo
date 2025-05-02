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
    @State private var isTitlePreloading = false // Add preloading state for title
    
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
                Divider()
                    .background(Color.white.opacity(0.2))
                titleView
                
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
                }
            )
            .offset(x: dragOffset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging from the left edge (first 66 points) and only to the right
                        if value.startLocation.x < 66 && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 66 points to the right, dismiss
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
        .preference(key: IsItemDetailsViewShowingPreferenceKey.self, value: isPresented)
        .onAppear {
            viewModel.loadDetails()
            feedbackGenerator.prepare()
            
            // Listen for the editing state notification
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("SetNewSubitemEditingState"),
                object: nil,
                queue: .main
            ) { _ in
                if viewModel.item.subItems.count < 50 {
                    feedbackGenerator.impactOccurred()
                    editingState = .newSubitem
                    updateFocusState()
                }
            }
            
            // Listen for the plus button notification from BaseView
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("TriggerItemDetailsPlusButton"),
                object: nil,
                queue: .main
            ) { _ in
                onPlusTapped()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // Save any ongoing edits
            if case .title = editingState {
                saveTitle()
            }
            // Save changes when view disappears
            viewModel.saveChanges()
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
            
            // Remove the notification observer
            NotificationCenter.default.removeObserver(self)
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
            // Back chevron on the left
            Button(action: {
                isPresented = false
            }) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 18, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.leading, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Checkbox
            checkboxButton
                .padding(.trailing, 4)
            
            // Metadata with flexible space
            MetadataRowCompact(item: viewModel.item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("metadata-\(viewModel.item.id.uuidString)")
            
            // Action buttons
            headerButtons
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 8)
    }
    
    private var checkboxButton: some View {
        Button(action: {
            feedbackGenerator.impactOccurred()
            viewModel.toggleCompleted()
        }) {
            Image(systemName: viewModel.item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(viewModel.item.isCompleted ? .green : .gray)
                .font(.system(size: 24))
                // Add a simple scale transition for the icon
                .animation(.spring(response: 0.01, dampingFraction: 1), value: viewModel.item.isCompleted)
        }
        .buttonStyle(.plain)
    }
    
    // Function to handle plus button tap
    private func onPlusTapped() {
        feedbackGenerator.impactOccurred()
        if viewModel.item.subItems.count < 50 {
            // First post notification to show and scroll to the field
            NotificationCenter.default.post(
                name: NSNotification.Name("ScrollToNewSubitemRow"),
                object: nil
            )
            
            // Then set new focus state
            editingState = .newSubitem
            updateFocusState()
        }
    }
    
    // Combined header buttons (without the close button)
    private var headerButtons: some View {
        HStack(spacing: 0) {
            // Undo button (conditionally shown)
            if viewModel.canUndo {
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    viewModel.undo()
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 20))
                        .frame(width: 56)
                        .contentShape(Rectangle())
                }
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
                    .frame(width: 55)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPopover, arrowEdge: .top) {
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
            
            // Delete button
            Button(action: {
                removeAllFocus()
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 20))
                    .frame(width: 48, height: 30)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
            }
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
            
            // Only show Done button when editing (no Close button since we now have the chevron)
            if editingState.isFocused {
                // Done button
                Button(action: {
                    removeAllFocus()
                }) {
                    Text("Done")
                        .foregroundColor(.white)
                        .dynamicTypeSize(.small...DynamicTypeSize.large)
                        .padding(.trailing, 12)
                }
                .frame(minWidth: 60)

            }
        }
    }
    
    // Start editing title
    private func startEditingTitle() {
        editedTitleText = viewModel.item.title
        isTitlePreloading = true
        
        // Use async to allow the UI to update first
        DispatchQueue.main.async {
            self.editingState = .title
            self.updateFocusState()
            self.isTitlePreloading = false
        }
    }
    
    // Save title
    private func saveTitle() {
        if !editedTitleText.isEmpty && editedTitleText != viewModel.item.title {
            viewModel.updateTitle(editedTitleText)
        }
    }
    
    // Title view component
    private var titleView: some View {
        ZStack {
            // Static title text (always present, but hidden when editing and not preloading)
            Button(action: {
                startEditingTitle()
            }) {
                Text(viewModel.item.title)
                    .font(.title3)
                    .foregroundColor(viewModel.item.isCompleted ? .white.opacity(0.7) : .white)
                    .lineLimit(4)
                    .strikethrough(viewModel.item.isCompleted, color: .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .opacity((editingState != .title) || isTitlePreloading ? 1 : 0)
            
            // Editable title field (always present, but only visible when editing and not preloading)
            TextField("Title", text: $editedTitleText, axis: .vertical)
                .font(.title3)
                .foregroundColor(.white)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .focused($titleFocused)
                .submitLabel(.done)
                .onChange(of: editedTitleText) {_, newValue in
                    // Check for Enter key
                    if newValue.contains("\n") {
                        // Remove the newline character
                        editedTitleText = newValue.replacingOccurrences(of: "\n", with: "")
                        
                        // Save the title
                        removeAllFocus()
                    }
                }
                .onChange(of: titleFocused) {
                    saveTitle()
                }
                .opacity(editingState == .title && !isTitlePreloading ? 1 : 0)
                .onChange(of: isTitlePreloading) { oldValue, newValue in
                    // When preloading ends, update focus
                    if oldValue == true && newValue == false, case .title = editingState {
                        DispatchQueue.main.async {
                            titleFocused = true
                        }
                    }
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
                                        viewModel.addSubitem(newSubitemText, true)
                                        newSubitemText = ""
                                        
                                        // After adding a subitem, maintain focus and keep the input field ready for more entry
                                        if keepFocus {
                                            editingState = .newSubitem
                                            updateFocusState()
                                        } else {
                                            removeAllFocus()
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
                                focusedSubitemId: $focusedSubitemId,
                                onEditingStateChange: { newState in
                                    editingState = newState
                                    updateFocusState()
                                }
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
                        
                        Color.clear.frame(height: 250)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)
                    .scrollContentBackground(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToNewSubitemRow"))) { _ in
                        
                        var row = ""
                        var topAnchor = true
                        if viewModel.item.subItems.count < 50 {
                            row = "newSubItemRow"
                        } else {
                            row = "subitemLimitMessage"
                            topAnchor = false
                        }
                        DispatchQueue.main.async {
                            proxy.scrollTo(row, anchor: topAnchor ? .top : .bottom)
                            //sometimes there's a timing issue so we force it to scroll again
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                proxy.scrollTo(row, anchor: topAnchor ? .top : .bottom)
                                
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
                        // Only apply animation to the strikethrough, not the entire text
                        .strikethrough(item.isCompleted, color: .gray)
                        .lineLimit(1)
                        .layoutPriority(1)
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
                            .animation(.easeInOut(duration: 0.01), value: item.isCompleted)
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
            ZStack {
                Image(systemName: "circle")
                    .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0.1))
                    .font(.system(size: 20))
                    .zIndex(2)
                    .padding(.trailing, 4)
                    .padding(.bottom, 6)
                Image(systemName: "arrow.down")
                    .foregroundColor(isFocused.wrappedValue ? .gray.opacity(0.3) : .gray.opacity(0))
                    .font(.system(size: 10))
                    .padding(.trailing, 4)
                    .padding(.bottom, 6)
            }
            
            ZStack(alignment: .leading) {
                TextField("New subitem...", text: $text, axis: .vertical)
                    .foregroundColor(isFocused.wrappedValue ? .white : .gray)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .submitLabel(.next)
                    .focused(isFocused)
                    //.frame(maxHeight: 80)
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
        .padding(.bottom, (isFocused.wrappedValue || viewModel.item.subItems.isEmpty) ? 6 : 0)
        .padding(.top, (isFocused.wrappedValue || viewModel.item.subItems.isEmpty) ? 10 : 0)
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
    let onEditingStateChange: (EditingState) -> Void
    @State private var editedText: String
    @State private var isPreloading = true
    
    // Add state for swipe
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    private let deleteWidth: CGFloat = 75
    
    init(subitem: Models.SubItem,
         viewModel: ItemDetailsViewModel,
         onToggle: @escaping () -> Void,
         onTap: @escaping () -> Void,
         editingState: EditingState,
         focusedSubitemId: FocusState<UUID?>.Binding,
         onEditingStateChange: @escaping (EditingState) -> Void) {
        self.subitem = subitem
        self.viewModel = viewModel
        self.onToggle = onToggle
        self.onTap = onTap
        self.editingState = editingState
        self._focusedSubitemId = focusedSubitemId
        self.onEditingStateChange = onEditingStateChange
        self._editedText = State(initialValue: subitem.title)
    }
    
    // Helper to determine if this specific subitem is being edited
    private var isEditing: Bool {
        if case .existingSubitem(let id) = editingState, id == subitem.id {
            return true
        }
        return false
    }
    
    private func triggerFocusSequence(id : UUID) {
        if id == subitem.id {
            isPreloading = true
            DispatchQueue.main.async {
                onTap()
            }
        }
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
                        .padding(.trailing, 4)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                
                ZStack {
                    if !isEditing && !isPreloading {
                        Text(subitem.title)
                            .font(.body)
                            .foregroundColor(subitem.isCompleted ? .white.opacity(0.7) : .white)
                            .lineLimit(4)
                            .strikethrough(subitem.isCompleted, color: .gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .padding(.leading, 0)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                triggerFocusSequence(id : subitem.id)
                            }
                    }
           
                    if isEditing || isPreloading {
                        TextField("",text: $editedText, axis: .vertical)
                            .font(.body)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .submitLabel(.next)
                            .padding(.vertical, 6)
                            .padding(.leading, 0)
                            .focused($focusedSubitemId, equals: subitem.id)
                            .onChange(of: focusedSubitemId) { oldValue, newValue in
                                if newValue == subitem.id {
                                    if editedText != subitem.title {
                                        editedText = subitem.title
                                    }
                                }
                                else if oldValue == subitem.id {
                                    saveChanges()
                                }
                            }
                            .onChange(of: subitem.title) { oldValue, newValue in
                                editedText = newValue
                            }
                            .onChange(of: editedText) { oldValue, newValue in
                                if newValue.contains("\n") {
                                    editedText = oldValue
                                    saveChanges()
                                    
                                    if let currentIndex = viewModel.item.subItems.firstIndex(where: { $0.id == subitem.id }) {
                                        viewModel.addSubitem("", false, afterIndex: currentIndex)
                                        if currentIndex + 1 < viewModel.item.subItems.count {
                                            let newSubitem = viewModel.item.subItems[currentIndex + 1]
                                            viewModel.subitemToFocus = newSubitem.id

                                        }
                                    }
                                }
                            }
                            .onAppear {
                                //now we can finish the preloading sequence

                                DispatchQueue.main.async {
                                    isPreloading = false
                                }
                            }
                            .onDisappear {
                                saveChanges()
                            }
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
            .onAppear {
                if viewModel.subitemToFocus == subitem.id {
                    triggerFocusSequence(id : subitem.id)
                    viewModel.subitemToFocus = nil
                }
            }
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
                    if (horizontalAmount > verticalAmount * 2) && (translation < -25) {
                        guard !isEditing else { return }
                        // Only allow left swipe (negative values)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            // Add some resistance to the drag
                            offset = max(-deleteWidth, translation)
                        }
                    } else if isSwiped {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                    if (horizontalAmount > verticalAmount * 2) && (translation < -50) {
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

// MARK: - Custom Shape for Side-Rounded Rectangle
private struct CustomRoundedRectangle: Shape {
    var topRight: CGFloat = 0
    var bottomRight: CGFloat = 0
    var topLeft: CGFloat = 0
    var bottomLeft: CGFloat = 0
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start from top left with potential corner
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        
        // Top right
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                radius: topRight,
                startAngle: Angle(degrees: -90),
                endAngle: Angle(degrees: 0),
                clockwise: false
            )
        }
        
        // Bottom right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                radius: bottomRight,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
        }
        
        // Bottom left
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                radius: bottomLeft,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
        }
        
        // Top left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                radius: topLeft,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
        }
        
        path.closeSubpath()
        return path
    }
} 

