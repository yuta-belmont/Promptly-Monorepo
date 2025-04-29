import SwiftUI

// Group Details View
struct GroupDetailsView: View {
    @ObservedObject var viewModel: GroupDetailsViewModel
    @Binding var isPresented: Bool
    @State private var dragOffset = CGSize.zero // Track drag gesture offset
    @State private var showingItemDetailsView: Bool = false
    @State private var selectedItemForDetails: Models.ChecklistItem?
    @State private var isEditingTitle: Bool = false // Track if title is being edited
    @State private var editedTitle: String = "" // Store the title being edited
    @State private var isEditingNotes: Bool = false // Track if notes are being edited
    @State private var editedNotes: String = "" // Store the notes being edited
    @FocusState private var isTitleFieldFocused: Bool // Focus state for text field
    @FocusState private var isNotesFieldFocused: Bool // Focus state for notes field
    @State private var showingRemoveAllAlert = false
    let closeAllViews: () -> Void
    let onNavigateToDate: ((Date) -> Void)?
    
    // Helper function to generate a unique item ID string
    private func generateItemId(for item: Models.ChecklistItem) -> String {
        
        // Only include properties that actually affect the view's appearance
        // Use more concise representations to improve performance and compiler handling
        // Follow EasyListView's approach - DON'T include lastModified in the ID
        let idString = "item-\(item.id.uuidString)-\(item.isCompleted)-\(item.title.hashValue)-\(item.notification?.timeIntervalSince1970 ?? 0)-\(item.subItems.count)"
        
        // Return the ID string without lastModified timestamp
        return idString
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with group color indicator
                HStack {
                    Button(action: {
                        if isEditingTitle {
                            // Cancel editing if back button is pressed while editing
                            isEditingTitle = false
                            isTitleFieldFocused = false
                            saveTitle()
                        }
                        isPresented = false
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(8)
                            .padding(.leading, 10)
                    }
                    
                    // Add color indicator next to the title
                    if let group = viewModel.selectedGroup, group.hasColor {
                        // Add folder icon
                        Image(systemName: "folder")
                            .font(.headline)
                            .foregroundColor(Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue).opacity(0.9))
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "folder")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.trailing, 4)
                    }
                    
                    // Replace Text with TextField when editing, or make Text tappable to enter edit mode
                    if isEditingTitle {
                        TextField("Group name", text: $editedTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .submitLabel(.done)
                            .lineLimit(1)
                            .focused($isTitleFieldFocused)
                            .onSubmit {
                                saveTitle()
                            }
                            .onAppear {
                                // Set the initial value when entering edit mode
                                editedTitle = viewModel.currentGroupTitle
                                // Set focus after a brief delay to ensure the field is ready
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isTitleFieldFocused = true
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                    } else {
                        Button(action: {
                            // Enter edit mode when tapping on the title
                            editedTitle = viewModel.currentGroupTitle
                            isEditingTitle = true
                        }) {
                            HStack(spacing: 4) {
                                Text(viewModel.currentGroupTitle)
                                    .font(.headline)
                                    .lineLimit(1)
                                    .foregroundColor(.white)
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Add notes button before the ellipsis
                    if !isEditingTitle {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isEditingNotes.toggle()
                                if isEditingNotes {
                                    editedNotes = viewModel.selectedGroup?.notes ?? ""
                                    // Set focus after a brief delay to ensure the field is ready
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isNotesFieldFocused = true
                                    }
                                }
                            }
                        }) {
                            Image(systemName: "note.text")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 18))
                                .padding(.leading, 16)
                        }
                    }
                    
                    Spacer()
                    
                    // Show Done button when editing title
                    if isEditingTitle {
                        Button(action: {
                            saveTitle()
                        }) {
                            Text("Done")
                                .foregroundColor(.white)
                                .dynamicTypeSize(.small...DynamicTypeSize.large)
                                .padding(.trailing, 8)
                        }
                        .padding(.trailing, 12)
                    } else {
                        // Use the modular menu component when not editing
                        if let selectedGroup = viewModel.selectedGroup {
                            GroupOptionsMenu(viewModel: viewModel, group: selectedGroup)
                        }
                    }
                }
                .padding(.vertical, 10)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Items in group
                if viewModel.isLoadingItems {
                    ProgressView()
                        .padding(.top, 20)
                } else if viewModel.groupItems.isEmpty {
                    VStack {
                        Spacer()
                        Text("No items in this group")
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.groupItems) { item in
                            PlannerItemView.create(
                                displayData: viewModel.getDisplayData(for: item),
                                onToggleItem: { itemId, notification in
                                    viewModel.toggleItemCompletion(itemId: itemId, notification: notification)
                                },
                                onToggleSubItem: { mainItemId, subItemId, isCompleted in
                                    viewModel.toggleSubItemCompletion(mainItemId: mainItemId, subItemId: subItemId, isCompleted: isCompleted)
                                },
                                onLoseFocus: nil,
                                onDelete: {
                                    viewModel.deleteItem(item)
                                },
                                onNotificationChange: { date in
                                    viewModel.updateItemNotification(itemId: item.id, notification: date)
                                },
                                onGroupChange: { groupId in
                                    // When groupId is nil, it means remove from group
                                    if groupId == nil, let group = viewModel.selectedGroup {
                                        viewModel.removeItemFromGroup(item, group: group)
                                    }
                                },
                                onItemTap: { itemId in
                                    // Show ItemDetailsView instead of navigating to date
                                    selectedItemForDetails = item
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showingItemDetailsView = true
                                    }
                                },
                                onToggleExpanded: { itemId in
                                    viewModel.toggleItemExpanded(itemId)
                                },
                                onGoToDate: {
                                    // Navigate to the calendar view at the item's date
                                    onNavigateToDate?(item.date)
                                    saveTitle()
                                    
                                    // Also close this view
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isPresented = false
                                    }
                                },
                                isGroupDetailsView: true
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                            .id("stable-item-\(item.id.uuidString)")
                        }
                        
                        // Add spacer at bottom of list for better scrolling
                        Color.clear.frame(height: 250)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.black.opacity(0.4)
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
                        // Only allow dragging from the left edge (first 66 points) and only to the right
                        if value.startLocation.x < 66 && value.translation.width > 0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 50 points to the right, dismiss
                        if value.startLocation.x < 66 && value.translation.width > 50 {
                            saveTitle()
                            
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
            .opacity(showingItemDetailsView ? 0 : 1) // Hide when ItemDetailsView is showing
            .zIndex(showingItemDetailsView ? 0 : 1999) // Lower z-index when ItemDetailsView is showing
            
            // Notes editor sheet
            .sheet(isPresented: $isEditingNotes) {
                NavigationView {
                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $editedNotes)
                                .font(.body)
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .focused($isNotesFieldFocused)
                                .padding(.horizontal)
                                .padding(.bottom)
                                .onChange(of: editedNotes) { _, newValue in
                                    // Update the group's notes in the view model
                                    if let group = viewModel.selectedGroup {
                                        viewModel.updateGroupNotes(newValue)
                                    }
                                }
                            
                            if editedNotes.isEmpty {
                                Text("Notes...")
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(.leading, 20)
                                    .padding(.top, 8)
                            }
                        }
                    }
                    .background(Color.black.opacity(0.4))
                    .navigationTitle("\(viewModel.currentGroupTitle) notes")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                isEditingNotes = false
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            
            // ItemDetailsView - appears over GroupDetailsView with higher zIndex
            if showingItemDetailsView, let selectedItem = selectedItemForDetails {
                ItemDetailsView(
                    item: selectedItem,
                    isPresented: .init(
                        get: { showingItemDetailsView },
                        set: { newValue in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingItemDetailsView = newValue
                            }
                        }
                    )
                )
                .transition(.move(edge: .trailing))
                .zIndex(4999) // Higher than GroupDetailsView's zIndex (3999)
            }
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
        .alert("Remove All Items", isPresented: $viewModel.showingRemoveAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                viewModel.removeAllItemsFromGroup()
            }
        } message: {
            Text("Are you sure you want to remove all items from this group? The items will remain in your checklists but will no longer be associated with this group.")
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
                }
            )
            .zIndex(9999) // Ensure this is higher than GroupDetailsView's zIndex
            .transition(.opacity)
        }
    }
    
    // Save the edited title to the group
    private func saveTitle() {
        if !editedTitle.isEmpty && editedTitle != viewModel.currentGroupTitle {
            viewModel.updateGroupName(editedTitle)
        }
        isEditingTitle = false
        isTitleFieldFocused = false
    }
}

// Create a modular menu component
struct GroupOptionsMenu: View {
    @ObservedObject var viewModel: GroupDetailsViewModel
    let group: Models.ItemGroup
    @ObservedObject private var groupStore = GroupStore.shared
    @State private var showingPopover = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        Button(action: {
            showingPopover = true
        }) {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 18))
                .padding(.leading, 8)
                .padding(.trailing, 18)
                .contentShape(Rectangle())
        }
        .popover(isPresented: $showingPopover,
                attachmentAnchor: .point(.bottom),
                arrowEdge: .top) {
            VStack(spacing: 0) {
                // Set Group Color option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    viewModel.showingColorPicker = true
                }) {
                    HStack {
                        Image(systemName: "paintpalette")
                            .frame(width: 24)
                        Text("Set Group Color")
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
                
                // Remove All Items option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    viewModel.showingRemoveAllAlert = true
                }) {
                    HStack {
                        Image(systemName: "folder.badge.minus")
                            .frame(width: 24)
                        Text("Remove All Items")
                        Spacer()
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Delete All Items option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    viewModel.showingDeleteAllAlert = true
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .frame(width: 24)
                        Text("Delete All Items")
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
    }
} 
