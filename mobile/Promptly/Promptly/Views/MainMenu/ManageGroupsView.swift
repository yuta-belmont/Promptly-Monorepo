import SwiftUI

struct ManageGroupsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = ManageGroupsViewModel()
    @State private var showingInfoPopover = false
    @FocusState private var isNewGroupFieldFocused: Bool
    @State private var refreshCounter: Int = 0 // Add a counter to force refresh
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    var onNavigateToDate: ((Date) -> Void)? = nil
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    // Add folder icon
                    Image(systemName: "folder")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.trailing, 4)
                    
                    Text("Manage Groups")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Button(action: {
                        showingInfoPopover = true
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 14))
                    }
                    .popover(isPresented: $showingInfoPopover) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Groups are used to organize tasks.")
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text("Grouped items can be color coded or deleted as a group.")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding()
                        .frame(width: 300)
                        .presentationCompactAdaptation(.none)
                    }
                    
                    Spacer()
                    
                    Button("Done") {
                        viewModel.saveNewGroupIfNeeded()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }
                }
                .padding()
                .padding(.top, 8)
                
                // List content
                List {
                    ForEach(viewModel.groups) { group in
                        // Only show the group if it's not pending deletion
                        if viewModel.groupIdToRemove != group.id {
                            GroupRow(group: group, viewModel: viewModel)
                                .contentShape(Rectangle())
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowSeparator(.hidden)
                                .id("\(group.id)-\(refreshCounter)") // Force refresh when counter changes
                        } else {
                            // This is a placeholder that will get removed with animation
                            // when groupIdToRemove is set
                            EmptyView()
                                .id("\(group.id)-tobedeleted")
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .frame(height: 0)
                        }
                    }
                    .animation(.easeInOut, value: viewModel.groupIdToRemove)
                    
                    // New Group Row
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(viewModel.isAddingNewGroup ? .gray : .blue)
                            .font(.system(size: 18))
                        
                        if viewModel.isAddingNewGroup {
                            TextField("Group Name", text: $viewModel.newGroupName)
                                .focused($isNewGroupFieldFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    viewModel.addGroup()
                                }
                        } else {
                            Text("New Group")
                                .foregroundColor(.blue)
                                .font(.system(size: 16, weight: .medium))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !viewModel.isAddingNewGroup {
                            viewModel.isAddingNewGroup = true
                            isNewGroupFieldFocused = true
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
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
                        // Only allow dragging to the right
                        if value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.translation.width > 100 {
                            // Use animation to ensure smooth transition
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
            )
            .transition(.move(edge: .trailing))
            .zIndex(999)
            
            // Group details overlay
            if viewModel.selectedGroup != nil {
                GroupDetailsView(
                    viewModel: viewModel, 
                    isPresented: Binding(
                        get: { viewModel.selectedGroup != nil },
                        set: { if !$0 { 
                            viewModel.selectedGroup = nil
                            // Force refresh when returning from details view
                            refreshCounter += 1
                        }}
                    ),
                    closeAllViews: {
                        // This will close both the details view and the manage groups view
                        viewModel.selectedGroup = nil
                        viewModel.saveNewGroupIfNeeded()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    },
                    onNavigateToDate: { date in
                        // First close this view and then navigate
                        viewModel.selectedGroup = nil
                        viewModel.saveNewGroupIfNeeded()
                        
                        // Use async to ensure views are properly cleaned up first
                        DispatchQueue.main.async {
                            if let parentNavigate = onNavigateToDate {
                                parentNavigate(date)
                            }
                        }
                    }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.selectedGroup)
        .onAppear {
            viewModel.loadGroups()
        }
        .onChange(of: isPresented) { newValue in
            if !newValue {
                viewModel.loadGroups()
            }
        }
        .alert("Delete Group", isPresented: $viewModel.showingDeleteGroupAlert) {
            Button("Cancel", role: .cancel) { 
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                // The animation and deletion will be handled by the viewModel
                // via the groupIdToRemove property
                viewModel.deleteGroupKeepItems()
            }
        } message: {
            Text("Are you sure you want to delete this group? The items will remain but will no longer be grouped.")
        }
        .onChange(of: isPresented) { oldValue, newValue in
            if oldValue && !newValue {
                // View is being dismissed
                viewModel.saveNewGroupIfNeeded()
            }
        }
    }
}

// Create a modular menu component
struct GroupOptionsMenu: View {
    @ObservedObject var viewModel: ManageGroupsViewModel
    let group: Models.ItemGroup
    @ObservedObject private var groupStore = GroupStore.shared
    @State private var showingPopover = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        Button(action: {
            showingPopover = true
        }) {
            Image(systemName: "ellipsis.circle")
                .foregroundColor(.white)
                .font(.system(size: 18))
                .frame(width: 44, height: 36)
        }
        .popover(isPresented: $showingPopover,
                attachmentAnchor: .point(.center),
                arrowEdge: .trailing) {
            VStack(spacing: 0) {
                // Edit Group Name option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    
                    // If this group isn't already selected, select it first
                    if viewModel.selectedGroup?.id != group.id {
                        viewModel.selectGroup(group)
                        
                        // Give time for selection to complete and update currentGroupTitle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Now use the currentGroupTitle which will be updated with the selected group
                            viewModel.editingGroupName = viewModel.currentGroupTitle
                            viewModel.showingEditNameAlert = true
                        }
                    } else {
                        // Group is already selected, use the currentGroupTitle directly
                        viewModel.editingGroupName = viewModel.currentGroupTitle
                        viewModel.showingEditNameAlert = true
                    }
                }) {
                    HStack {
                        Image(systemName: "pencil")
                            .frame(width: 24)
                        Text("Edit Group Name")
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Set Group Color option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    
                    // If this group isn't already selected, select it first
                    if viewModel.selectedGroup?.id != group.id {
                        viewModel.selectGroup(group)
                        
                        // Give time for selection to complete
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewModel.showingColorPicker = true
                        }
                    } else {
                        // Group is already selected, show color picker directly
                        viewModel.showingColorPicker = true
                    }
                }) {
                    HStack {
                        Image(systemName: "paintpalette")
                            .frame(width: 24)
                        Text("Set Group Color")
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Delete All Items option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    
                    // If this group isn't already selected, select it first
                    if viewModel.selectedGroup?.id != group.id {
                        viewModel.selectGroup(group)
                        
                        // Give time for selection to complete and load items
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            viewModel.showingDeleteAllAlert = true
                        }
                    } else {
                        // Group is already selected, show delete alert directly
                        viewModel.showingDeleteAllAlert = true
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .frame(width: 24)
                        Text("Delete All Items")
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Delete Group (Keep Items) option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    viewModel.confirmDeleteGroup(group)
                }) {
                    HStack {
                        Image(systemName: "folder.badge.minus")
                            .frame(width: 24)
                        Text("Delete Group (Keep Items)")
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 200)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .presentationCompactAdaptation(.none)
            .onAppear {
                feedbackGenerator.prepare()
            }
        }
        .contentShape(Rectangle())
    }
}

// Helper Views
struct GroupRow: View {
    let group: Models.ItemGroup
    @ObservedObject private var viewModel: ManageGroupsViewModel
    @ObservedObject private var groupStore = GroupStore.shared
    @State private var isGlowing: Bool = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    init(group: Models.ItemGroup, viewModel: ManageGroupsViewModel) {
        self.group = group
        self.viewModel = viewModel
    }
    
    var body: some View {
        // Get the current group from the store to ensure we have the latest data
        let currentGroup = groupStore.groups.first(where: { $0.id == group.id }) ?? group
        
        HStack(spacing: 12) {
            // Main content with navigation
            Button(action: {
                // Trigger haptic feedback
                feedbackGenerator.impactOccurred()
                
                // Start the glow animation
                isGlowing = true
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isGlowing = false
                    }
                }
                
                // Select the group
                viewModel.selectGroup(currentGroup)
            }) {
                HStack {
                    // Color indicator
                    if currentGroup.hasColor {
                        Circle()
                            .fill(Color(red: currentGroup.colorRed, green: currentGroup.colorGreen, blue: currentGroup.colorBlue))
                            .frame(width: 16, height: 16)
                            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                    } else {
                        Circle()
                            .strokeBorder(Color.gray.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Get the current title from the group store to ensure it's up-to-date
                        let currentTitle = currentGroup.title
                        
                        Text(currentTitle)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        // Item count
                        let itemCount = currentGroup.getAllItems().count
                        Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Chevron to indicate navigation
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onAppear {
                // Prepare the feedback generator when the view appears
                feedbackGenerator.prepare()
            }
            
            // Menu - completely separate from navigation area
            GroupOptionsMenu(viewModel: viewModel, group: currentGroup)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.3))
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Glow effect - exactly like in PlannerItemView
                if isGlowing {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .blur(radius: 8)
                        .opacity(0.15)
                }
            }
        )
        .overlay(
            Group {
                // Default outline
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                
                // Animated outline that appears with the glow
                if isGlowing {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 0.5)
                }
            }
        )
    }
}

// Group Details View
struct GroupDetailsView: View {
    @ObservedObject var viewModel: ManageGroupsViewModel
    @Binding var isPresented: Bool
    @State private var colorUpdateCounter: Int = 0 // Add a counter to force view updates
    @State private var dragOffset = CGSize.zero // Track drag gesture offset
    let closeAllViews: () -> Void
    let onNavigateToDate: ((Date) -> Void)?
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with group color indicator
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .padding(.trailing, 8)
                    
                    // Add color indicator next to the title
                    if let group = viewModel.selectedGroup, group.hasColor {
                        Circle()
                            .fill(Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue))
                            .frame(width: 12, height: 12)
                            .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
                            .padding(.trailing, 4)
                    }
                    
                    Text(viewModel.currentGroupTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Use the modular menu component
                    if let selectedGroup = viewModel.selectedGroup {
                        GroupOptionsMenu(viewModel: viewModel, group: selectedGroup)
                    }
                    
                    // Add "Done" button to completely close the ManageGroupsView
                    Button("Done") {
                        closeAllViews()
                    }
                }
                .padding()
                .padding(.top, 0)
                .id("header-\(colorUpdateCounter)") // Force refresh when color changes
                
                // Items in group
                if viewModel.isLoadingItems {
                    ProgressView()
                        .padding(.top, 20)
                } else if viewModel.groupItems.isEmpty {
                    Text("No items in this group")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                } else {
                    List {
                        ForEach(viewModel.groupItems) { item in
                            GroupItemRow(item: item, viewModel: viewModel, onNavigateToDate: onNavigateToDate)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
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
                        // Only allow dragging to the right
                        if value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.translation.width > 100 {
                            // Use animation to ensure smooth transition
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
            )
            .transition(.move(edge: .trailing))
            .zIndex(1999)
        }
        .zIndex(3999) // Ensure this appears above the managegroupsview
        .onAppear {
            // Reset loading state and reload items
            viewModel.isLoadingItems = true
            viewModel.loadItems()
        }
        .alert("Delete All Items", isPresented: $viewModel.showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewModel.deleteAllItems()
            }
        } message: {
            Text("Are you sure you want to delete all items in this group? This action cannot be undone.")
        }
        .alert("Delete Group", isPresented: $viewModel.showingDeleteGroupAlert) {
            Button("Cancel", role: .cancel) { 
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                // This will properly animate the deletion in the parent view
                // and dismiss this detail view if the current group is deleted
                viewModel.deleteGroupKeepItems()
                
                // Dismiss the details view with animation if the deleted group is the selected one
                if let selectedGroup = viewModel.selectedGroup, 
                   let groupToDelete = viewModel.groupToDelete,
                   selectedGroup.id == groupToDelete.id {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this group? The items will remain but will no longer be grouped.")
        }
        .alert("Edit Group Name", isPresented: $viewModel.showingEditNameAlert) {
            TextField("Group Name", text: $viewModel.editingGroupName)
                .autocapitalization(.words)
                .disableAutocorrection(true)
            Button("Cancel", role: .cancel) { 
                // Reset the editing name
                viewModel.editingGroupName = viewModel.currentGroupTitle
            }
            Button("Save") {
                if !viewModel.editingGroupName.isEmpty {
                    viewModel.updateGroupName(viewModel.editingGroupName)
                }
            }
            .disabled(viewModel.editingGroupName.isEmpty)
        } message: {
            Text("Enter a new name for this group")
        }
        
        // Color picker sheet - moved outside the ZStack for proper z-index context
        if viewModel.showingColorPicker {
            ColorPickerView(
                isPresented: $viewModel.showingColorPicker,
                selectedRed: $viewModel.selectedColorRed,
                selectedGreen: $viewModel.selectedColorGreen,
                selectedBlue: $viewModel.selectedColorBlue,
                hasColor: $viewModel.selectedColorHasColor,
                onColorSelected: { red, green, blue, hasColor in
                    if hasColor {
                        viewModel.updateGroupColor(red: red, green: green, blue: blue)
                    } else {
                        viewModel.removeGroupColor()
                    }
                    // Increment counter to force UI refresh
                    colorUpdateCounter += 1
                }
            )
            .zIndex(9999) // Ensure this is higher than GroupDetailsView's zIndex
        }
    }
}

struct GroupItemRow: View {
    let item: Models.ChecklistItem
    @ObservedObject private var viewModel: ManageGroupsViewModel
    @State private var showingPopover = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    let onNavigateToDate: ((Date) -> Void)?
    
    init(item: Models.ChecklistItem, viewModel: ManageGroupsViewModel, onNavigateToDate: ((Date) -> Void)? = nil) {
        self.item = item
        self.viewModel = viewModel
        self.onNavigateToDate = onNavigateToDate
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Item title and date
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .strikethrough(item.isCompleted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                // Format the date
                Text(formattedDate(item.date))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // Menu button
            Button(action: {
                feedbackGenerator.impactOccurred()
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
                     arrowEdge: .trailing) {
                GroupItemPopoverView(
                    item: item,
                    group: viewModel.selectedGroup ?? viewModel.groups[0],
                    viewModel: viewModel,
                    onNavigateToDate: onNavigateToDate
                )
                .presentationCompactAdaptation(.none)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// Custom PopoverView for GroupItemRow
struct GroupItemPopoverView: View {
    let item: Models.ChecklistItem
    let group: Models.ItemGroup
    @ObservedObject private var viewModel: ManageGroupsViewModel
    @State private var removeConfirmationActive = false
    @State private var deleteConfirmationActive = false
    @State private var removeTimer: Timer?
    @State private var deleteTimer: Timer?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @Environment(\.dismiss) private var dismiss
    let onNavigateToDate: ((Date) -> Void)?
    
    init(item: Models.ChecklistItem, group: Models.ItemGroup, viewModel: ManageGroupsViewModel, onNavigateToDate: ((Date) -> Void)? = nil) {
        self.item = item
        self.group = group
        self.viewModel = viewModel
        self.onNavigateToDate = onNavigateToDate
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Go To Button
            Button(action: {
                feedbackGenerator.impactOccurred()
                dismiss()
                if let onNavigateToDate = onNavigateToDate {
                    DispatchQueue.main.async {
                        onNavigateToDate(item.date)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "calendar")
                        .frame(width: 24)
                    Text("Go To")
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Remove from Group Button
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if removeConfirmationActive {
                    // Second tap - perform remove
                    removeTimer?.invalidate()
                    removeTimer = nil
                    removeConfirmationActive = false
                    viewModel.removeItemFromGroup(item, group: group)
                    dismiss()
                } else {
                    // First tap - start confirmation timer
                    removeConfirmationActive = true
                    removeTimer?.invalidate()
                    removeTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                        removeConfirmationActive = false
                    }
                }
            }) {
                HStack {
                    Image(systemName: "folder.badge.minus")
                        .frame(width: 24)
                    Text(removeConfirmationActive ? "Confirm" : "Remove from Group")
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Delete Button
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                if deleteConfirmationActive {
                    // Second tap - perform delete
                    deleteTimer?.invalidate()
                    deleteTimer = nil
                    deleteConfirmationActive = false
                    viewModel.deleteItem(item)
                    dismiss()
                } else {
                    // First tap - start confirmation timer
                    deleteConfirmationActive = true
                    deleteTimer?.invalidate()
                    deleteTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                        deleteConfirmationActive = false
                    }
                }
            }) {
                HStack {
                    Image(systemName: "trash")
                        .frame(width: 24)
                    Text(deleteConfirmationActive ? "Confirm" : "Delete")
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            // Prepare haptic feedback when view appears
            feedbackGenerator.prepare()
        }
        .onDisappear {
            // Clean up timers when view disappears
            removeTimer?.invalidate()
            removeTimer = nil
            deleteTimer?.invalidate()
            deleteTimer = nil
            removeConfirmationActive = false
            deleteConfirmationActive = false
        }
    }
}

// Color Picker View
struct ColorPickerView: View {
    @Binding var isPresented: Bool
    @Binding var selectedRed: Double
    @Binding var selectedGreen: Double
    @Binding var selectedBlue: Double
    @Binding var hasColor: Bool
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    let onColorSelected: (Double, Double, Double, Bool) -> Void
    
    // Predefined colors with identifiers
    let colors: [(id: Int, red: Double, green: Double, blue: Double)] = [
        (0, 1.0, 0.2, 0.2), // Red
        (1, 1.0, 0.6, 0.2), // Orange
        (2, 1.0, 0.8, 0.2), // Yellow
        (3, 0.2, 0.8, 0.2), // Green
        (4, 0.2, 0.6, 1.0), // Blue
        (5, 0.6, 0.2, 1.0), // Purple
        (6, 1.0, 0.4, 0.8), // Pink
        (7, 0.5, 0.5, 0.5), // Gray
    ]
    
    var body: some View {
        ZStack {
            // Semi-transparent backdrop for closing the view
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
                .allowsHitTesting(true)
                .zIndex(9998)
            
            // Color picker content
            VStack(spacing: 12) {
                // Header
                HStack {
                    Text("Select Color")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Color grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                    ForEach(colors, id: \.id) { item in
                        ColorCircle(
                            red: item.red,
                            green: item.green,
                            blue: item.blue,
                            isSelected: hasColor && isColorSelected(item.red, item.green, item.blue)
                        )
                        .onTapGesture {
                            selectedRed = item.red
                            selectedGreen = item.green
                            selectedBlue = item.blue
                            hasColor = true
                            onColorSelected(item.red, item.green, item.blue, true)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Remove color option
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal)
                
                Button(action: {
                    // Set hasColor to false to indicate no color is selected
                    hasColor = false
                    // Call onColorSelected with nil to remove the color
                    onColorSelected(0, 0, 0, false)
                }) {
                    HStack {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "xmark")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .bold))
                        }
                        
                        Text("Remove Color")
                            .foregroundColor(.white)
                            .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                }
                .padding(.bottom, 8)
            }
            .frame(width: 300)
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
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
                        // Only allow dragging to the right
                        if value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss
                        if value.translation.width > 100 {
                            // Use animation to ensure smooth transition
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }
                        // If not dragged far enough, animate back to original position
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
            )
            .transition(.move(edge: .trailing))
            .zIndex(9999)
        }
    }
    
    // Helper function to check if a color is selected
    private func isColorSelected(_ red: Double, _ green: Double, _ blue: Double) -> Bool {
        // We only want to show a color as selected if it exactly matches the selected color
        return abs(red - selectedRed) < 0.01 && 
               abs(green - selectedGreen) < 0.01 && 
               abs(blue - selectedBlue) < 0.01
    }
}

struct ColorCircle: View {
    let red: Double
    let green: Double
    let blue: Double
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: red, green: green, blue: blue))
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            
            if isSelected {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 50, height: 50)
                
                Image(systemName: "checkmark")
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .bold))
            }
        }
    }
}
