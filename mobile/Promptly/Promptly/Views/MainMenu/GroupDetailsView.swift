import SwiftUI

// Group Details View
struct GroupDetailsView: View {
    @ObservedObject var viewModel: GroupDetailsViewModel
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
                            PlannerItemView.create(
                                displayData: viewModel.getDisplayData(for: item),
                                onToggleItem: { itemId, notification in
                                    // No need to handle toggling in group details view
                                },
                                onToggleSubItem: { mainItemId, subItemId, isCompleted in
                                    // No need to handle sub-item toggling in group details view
                                },
                                onLoseFocus: { text in
                                    // No need to handle text-based deletion in group details view
                                },
                                onDelete: {
                                    viewModel.deleteItem(item)
                                },
                                onNotificationChange: { date in
                                    // No need to handle notification changes in group details view
                                },
                                onGroupChange: { groupId in
                                    // No need to handle group changes in group details view
                                },
                                onItemTap: { itemId in
                                    if let onNavigateToDate = onNavigateToDate {
                                        DispatchQueue.main.async {
                                            onNavigateToDate(item.date)
                                        }
                                    }
                                },
                                isGroupDetailsView: true
                            )
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
                .ultraThinMaterial
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
        .contentShape(Rectangle())
    }
} 
