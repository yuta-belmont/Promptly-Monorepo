import SwiftUI

// Group Details View
struct GroupDetailsView: View {
    @ObservedObject var viewModel: GroupDetailsViewModel
    @Binding var isPresented: Bool
    @State private var dragOffset = CGSize.zero // Track drag gesture offset
    @State private var showingItemDetailsView: Bool = false
    @State private var selectedItemForDetails: Models.ChecklistItem?
    let closeAllViews: () -> Void
    let onNavigateToDate: ((Date) -> Void)?
    
    // Helper function to generate a unique item ID string
    private func generateItemId(for item: Models.ChecklistItem) -> String {
        // Debug: Print the item values as seen by the PlannerItemView
        print("PlannerItemView - Item Values: id=\(item.id.uuidString), title=\(item.title), completed=\(item.isCompleted), subItems=\(item.subItems.count), lastModified=\(String(describing: item.lastModified))")
        
        // Only include properties that actually affect the view's appearance
        // Use more concise representations to improve performance and compiler handling
        // Follow EasyListView's approach - DON'T include lastModified in the ID
        let idString = "item-\(item.id.uuidString)-\(item.isCompleted)-\(item.title.hashValue)-\(item.notification?.timeIntervalSince1970 ?? 0)-\(item.subItems.count)"
        
        // Debug: Print the generated ID
        print("PlannerItemView - Generated ID: \(idString)")
        
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
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
                    
                    Text(viewModel.currentGroupTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Use the modular menu component
                    if let selectedGroup = viewModel.selectedGroup {
                        GroupOptionsMenu(viewModel: viewModel, group: selectedGroup)
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
                    Text("No items in this group")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
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
                                onGroupChange: nil, // Group editing not needed in this view
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
                                    
                                    // Also close this view
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isPresented = false
                                    }
                                },
                                isGroupDetailsView: true
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 0, trailing: 4))
                            .listRowSeparator(.hidden)

                            // Use a stable ID that doesn't change with isCompleted status
                            // Only use the UUID and title hash for the ID, which won't change during toggle
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
                
                Spacer()
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
            
            // ItemDetailsView - appears over GroupDetailsView with higher zIndex
            if showingItemDetailsView, let selectedItem = selectedItemForDetails {
                ItemDetailsView(
                    item: selectedItem,
                    isPresented: $showingItemDetailsView
                )
                .transition(.move(edge: .trailing))
                .zIndex(4999) // Higher than GroupDetailsView's zIndex (3999)
                // We rely on the notification system to update specific items
                // No need for a full reload on disappear
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
                }
            )
            .zIndex(9999) // Ensure this is higher than GroupDetailsView's zIndex
        }
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
                .frame(width: 56)
                .contentShape(Rectangle())
        }
        .popover(isPresented: $showingPopover,
                attachmentAnchor: .point(.bottom),
                arrowEdge: .top) {
            VStack(spacing: 0) {
                // Edit Group Name option
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    showingPopover = false
                    viewModel.editingGroupName = viewModel.currentGroupTitle
                    viewModel.showingEditNameAlert = true
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
    }
} 
