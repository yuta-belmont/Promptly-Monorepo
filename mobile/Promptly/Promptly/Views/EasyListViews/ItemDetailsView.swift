import SwiftUI

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
    @State private var editingSubitemId: UUID? = nil
    @State private var editedSubitemText = ""
    @FocusState private var focusedSubitemId: UUID?
    
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
    
    // Computed property to check if any field is focused
    private var isAnyFieldFocused: Bool {
        isSubitemFieldFocused || isTitleFieldFocused || focusedSubitemId != nil
    }
    
    // Function to remove all focus
    private func removeAllFocus() {
        focusRemovalState = .saving
        
        // Phase 1: Save all edits
        if isEditingTitle {
            saveTitle()
        }
        if editingSubitemId != nil {
            let currentEditingId = editingSubitemId
            editingSubitemId = nil  // Clear editing state first
            
            if let id = currentEditingId {
                if editedSubitemText.isEmpty {
                    viewModel.deleteSubitem(id)
                } else {
                    viewModel.updateSubitemTitle(id, newTitle: editedSubitemText)
                }
            }
        }
        
        // Phase 2: Clear focus states
        focusRemovalState = .clearingFocus
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                self.isSubitemFieldFocused = false
                self.isTitleFieldFocused = false
                self.focusedSubitemId = nil
                
                // Phase 3: Mark as complete
                self.focusRemovalState = .completed
                
                // Reset state after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.focusRemovalState = nil
                }
            }
        }
    }
    
    @State private var dragOffset = CGSize.zero
    @State private var draggedTooFar = false
    
    init(item: Models.ChecklistItem, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: ItemDetailsViewModel(item: item))
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                headerView
                
                // Item title below header
                ZStack {
                    if isEditingTitle {
                        // Editable title field
                        TextEditor(text: $editedTitleText)
                            .font(.title3)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 8)
                            .frame(maxHeight: 96)
                            .focused($isTitleFieldFocused)
                            .onChange(of: editedTitleText) {_, newValue in
                                // Check for Enter key
                                if newValue.contains("\n") {
                                    // Remove the newline character
                                    editedTitleText = newValue.replacingOccurrences(of: "\n", with: "")
                                    
                                    // Save the title
                                    saveTitle()
                                }
                            }
                            .onAppear {
                                // Set focus in the next run loop
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                    isTitleFieldFocused = true
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
                
                // Divider between header section and content
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal)
                
                // Main item details
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        ScrollViewReader { proxy in
                            List {
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
                                        editingSubitemId: $editingSubitemId,
                                        editedSubitemText: $editedSubitemText,
                                        focusedSubitemId: $focusedSubitemId,
                                        onSave: { newText in
                                            if !newText.isEmpty {
                                                viewModel.updateSubitemTitle(subitem.id, newTitle: newText)
                                            }
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
                                
                                // Only show the new subitem row if fewer than 50 subitems exist
                                if viewModel.item.subItems.count < 50 {
                                    NewSubItemRow(
                                        text: $newSubitemText,
                                        isFocused: $isSubitemFieldFocused,
                                        onSubmit: { keepFocus in
                                            if !newSubitemText.isEmpty {
                                                viewModel.addSubitem(newSubitemText)
                                                newSubitemText = ""
                                                // Only maintain focus if explicitly requested (i.e., from return key)
                                                isSubitemFieldFocused = keepFocus
                                                if keepFocus {
                                                    // Scroll to bottom only when keeping focus
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                        withAnimation {
                                                            proxy.scrollTo("newSubItemRow", anchor: .bottom)
                                                        }
                                                    }
                                                }
                                            }
                                            else {
                                                isSubitemFieldFocused = false
                                            }
                                        }
                                    )
                                    .id("newSubItemRow")
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets())
                                } else {
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
                                
                                Color.clear.frame(height: 44)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                            }
                            .listStyle(.plain)
                            .environment(\.defaultMinListRowHeight, 0)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                                if isSubitemFieldFocused {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo("newSubItemRow", anchor: .bottom)
                                    }
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToNewSubitemRow"))) { _ in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    if viewModel.item.subItems.count < 50 {
                                        proxy.scrollTo("newSubItemRow", anchor: .bottom)
                                    } else {
                                        proxy.scrollTo("subitemLimitMessage", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.black
                    .opacity(0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .offset(x: dragOffset.width)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging from the left edge (first 88 points) and only to the right
                        if value.startLocation.x < 88 && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.startLocation.x < 44 && value.translation.width > 100 {
                            draggedTooFar = true
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
            if isEditingTitle {
                saveTitle()
            }
            if editingSubitemId != nil {
                saveSubitemEdit()
            }
            
            // Save changes when view disappears
            viewModel.saveChanges()
            
            // Post notification that item was updated
            NotificationCenter.default.post(
                name: Notification.Name("ItemDetailsUpdated"),
                object: viewModel.item.id
            )
        }
        .onChange(of: isTitleFieldFocused) { _, newValue in
            if !newValue && isEditingTitle {
                saveTitle()
            }
        }
        .onChange(of: focusedSubitemId) { oldValue, newValue in
            
            // Only handle focus changes if we're not in the middle of focus removal
            if focusRemovalState == nil {
                if oldValue != nil && newValue == nil && editingSubitemId != nil {
                    saveSubitemEdit()
                }
            }
        }
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
            viewModel.toggleCompleted()
        }) {
            Image(systemName: viewModel.item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(viewModel.item.isCompleted ? .green : .gray)
                .font(.system(size: 24))
        }
        .buttonStyle(.plain)
    }
    
    private var actionButtons: some View {
        Group {
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
            
            // Add button - only show when the new subitem field is not focused
            if !isSubitemFieldFocused {
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    if viewModel.item.subItems.count < 50 {
                        isSubitemFieldFocused = true
                    }
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ScrollToNewSubitemRow"),
                        object: nil
                    )
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(viewModel.item.subItems.count >= 50 ? .white.opacity(0.3) : .white.opacity(0.6))
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.item.subItems.count >= 50)
            }
            
            // Delete button
            Button(action: {
                feedbackGenerator.impactOccurred()
                showingDeleteConfirmation = true
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDeleteConfirmation, arrowEdge: .top) {
                SubitemDeleteConfirmationView(
                    isPresented: $showingDeleteConfirmation,
                    isConfirmationActive: $deleteConfirmationActive,
                    onDeleteAll: {
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
            
            if isAnyFieldFocused {
                // Done button
                Button(action: {
                    removeAllFocus()
                }) {
                    Text("Done")
                        .foregroundColor(.blue)
                        .font(.system(size: 17, weight: .regular))
                        .padding(.horizontal, 8)
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
        HStack(spacing: 8) {
            if hasGroup, let groupTitle = groupName {
                Text(groupTitle)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            
            if let notification = item.notification {
                if hasGroup {
                    Divider()
                        .frame(height: 14)
                        .background(Color.white.opacity(0.3))
                }
                
                HStack(spacing: 2) {
                    Image(systemName: "bell.fill")
                        .font(.footnote)
                    
                    let isPastDue = notification < Date()
                    Text(formatNotificationTime(notification))
                        .font(.footnote)
                        .foregroundColor(isPastDue ? .red.opacity(0.5) : .white.opacity(0.5))
                        .strikethrough(item.isCompleted, color: .gray)
                        .animation(.easeInOut(duration: 0.2), value: item.isCompleted)
                }
                .foregroundColor(notification < Date() ? .red.opacity(0.5) : .white.opacity(0.5))
            }
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
    
    // Title editing methods
    private func startEditingTitle() {
        editedTitleText = viewModel.item.title
        isEditingTitle = true
    }
    
    private func saveTitle() {
        guard !editedTitleText.isEmpty else { return }
        if editedTitleText != viewModel.item.title {
            viewModel.updateTitle(editedTitleText)
        }
        isEditingTitle = false
    }
    
    // Subitem editing methods
    private func startEditingSubitem(_ subitem: Models.SubItem) {
        
        // If we have an existing edit, save it first
        if editingSubitemId != nil {
            saveSubitemEdit()
        }
        
        editingSubitemId = subitem.id
        editedSubitemText = subitem.title
    }
    
    private func saveSubitemEdit() {
        guard let subitemId = editingSubitemId else { return }
        
        if editedSubitemText.isEmpty {
            // Delete the subitem if text is empty
            viewModel.deleteSubitem(subitemId)
        } else if editedSubitemText != viewModel.item.subItems.first(where: { $0.id == subitemId })?.title {
            viewModel.updateSubitemTitle(subitemId, newTitle: editedSubitemText)
        }
        self.editingSubitemId = nil
    }
}

// Add SubItemView definition
private struct SubItemView: View {
    let subitem: Models.SubItem
    let viewModel: ItemDetailsViewModel
    let onToggle: () -> Void
    let onTap: () -> Void
    @Binding var editingSubitemId: UUID?
    @Binding var editedSubitemText: String
    @FocusState.Binding var focusedSubitemId: UUID?
    let onSave: (String) -> Void
    @State private var isPreloading = false
    
    // Add state for swipe
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    private let deleteWidth: CGFloat = 75
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete button background and button - position off screen when not swiped
            Rectangle()
                .fill(Color.red)
                .frame(width: deleteWidth)
                .offset(x: offset < 0 || isSwiped ? 0 : deleteWidth)
            
            Button(action: {
                withAnimation {
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
                    if editingSubitemId != subitem.id || isPreloading {
                        Text(subitem.title)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(3)
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
                    
                    if editingSubitemId == subitem.id || isPreloading {
                        TextEditor(text: $editedSubitemText)
                            .font(.body)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.vertical, 0)
                            .padding(.leading, 0)
                            .focused($focusedSubitemId, equals: subitem.id)
                            .onChange(of: editedSubitemText) { oldValue, newValue in
                                if newValue.contains("\n") {
                                    editedSubitemText = oldValue
                                    onSave(editedSubitemText)
                                    focusedSubitemId = nil
                                    editingSubitemId = nil
                                }
                            }
                            .opacity(isPreloading ? 0 : 1)
                            .onChange(of: isPreloading) { oldValue, newValue in
                                if oldValue == true && newValue == false && editingSubitemId == subitem.id {
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
                    // Calculate the angle of the drag to determine if it's horizontal enough
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Only respond if the gesture is primarily horizontal
                    // (horizontal movement is at least 3x the vertical movement)
                    if horizontalAmount > verticalAmount * 3 && horizontalAmount > 25 {
                        // Only allow left swipe (negative values)
                        let translation = value.translation.width
                        if translation < 0 {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                // Add some resistance to the drag
                                offset = max(-deleteWidth, translation)
                            }
                        } else if isSwiped {
                            // If already swiped, allow closing with some resistance
                            offset = -deleteWidth + min(deleteWidth, translation)
                        }
                    }
                }
                .onEnded { value in
                    let translation = value.translation.width
                    let velocity = value.velocity.width
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)
                    
                    // Only complete the swipe if it was primarily horizontal
                    if horizontalAmount > verticalAmount * 2 && horizontalAmount > 50 {
                        // Determine if we should open or close based on velocity and position
                        if (translation < -deleteWidth/2 || velocity < -100) && !isSwiped {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = -deleteWidth
                                isSwiped = true
                            }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                offset = 0
                                isSwiped = false
                            }
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
    }
}

// Add NewSubItemRow component before SubItemView
private struct NewSubItemRow: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: (Bool) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0))
                .font(.system(size: 20))
                .transition(.opacity)
                .padding(.top, 8)
            
            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused(isFocused)
                .onChange(of: isFocused.wrappedValue) { _, isFocused in
                    if !isFocused && !text.isEmpty {
                        onSubmit(false) // Don't keep focus when submitting via focus loss
                    }
                }
                .onChange(of: text) { _, newValue in
                    if newValue.contains("\n") {
                        text = newValue.replacingOccurrences(of: "\n", with: "")
                        onSubmit(true) // Keep focus when submitting via return key
                    }
                }
                .overlay(
                    Text(text.isEmpty ? "Add subitem..." : "")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.leading, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading),
                    alignment: .topLeading
                )
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
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
