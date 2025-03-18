import SwiftUI

struct ManageGroupsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = ManageGroupsViewModel()
    @State private var showingInfoPopover = false
    @FocusState private var isNewGroupFieldFocused: Bool
    @State private var refreshCounter: Int = 0 // Add a counter to force refresh
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    viewModel.saveNewGroupIfNeeded()
                    isPresented = false
                }
            
            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
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
                        isPresented = false
                    }
                }
                .padding()
                .padding(.top, 8)
                
                // List content
                List {
                    ForEach(viewModel.groups) { group in
                        GroupRow(group: group)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectGroup(group)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .id("\(group.id)-\(refreshCounter)") // Force refresh when counter changes
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first {
                            viewModel.confirmDeleteGroup(at: index)
                        }
                    }
                    
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
            .padding()
            
            // Group details overlay
            if viewModel.selectedGroup != nil {
                GroupDetailsView(viewModel: viewModel, isPresented: Binding(
                    get: { viewModel.selectedGroup != nil },
                    set: { if !$0 { 
                        viewModel.selectedGroup = nil
                        // Force refresh when returning from details view
                        refreshCounter += 1
                    }}
                ))
            }
        }
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
                viewModel.groupToDelete = nil
            }
            Button("Delete", role: .destructive) {
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

// Helper Views
struct GroupRow: View {
    let group: Models.ItemGroup
    @ObservedObject private var groupStore = GroupStore.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Get the current group from the store to ensure we have the latest data
            let currentGroup = groupStore.groups.first(where: { $0.id == group.id }) ?? group
            
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
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// Group Details View
struct GroupDetailsView: View {
    @ObservedObject var viewModel: ManageGroupsViewModel
    @Binding var isPresented: Bool
    @State private var colorUpdateCounter: Int = 0 // Add a counter to force view updates
    @State private var dragOffset: CGFloat = 0 // Track drag gesture offset
    @State private var rotation = Angle.zero // Track rotation for swipe animation
    
    var body: some View {
        ZStack {
            // Background overlay - only dismiss when tapping directly on it
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isPresented = false
                }
                .allowsHitTesting(true) // Explicitly allow hit testing on the background
            
            // Main content
            VStack(spacing: 0) {
                // Header with group color indicator
                HStack {
                    Button(action: {
                        isPresented = false
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
                    
                    Menu {
                        Button(action: {
                            viewModel.editingGroupName = viewModel.currentGroupTitle
                            viewModel.showingEditNameAlert = true
                        }) {
                            Label("Edit Group Name", systemImage: "pencil")
                        }
                        
                        Button(action: {
                            viewModel.showingColorPicker = true
                        }) {
                            Label("Set Group Color", systemImage: "paintpalette")
                        }
                        Button(role: .destructive, action: {
                            viewModel.showingDeleteAllAlert = true
                        }) {
                            Label("Delete All Items", systemImage: "trash")
                        }
                        
                        Button(role: .destructive, action: {
                            // Set the groupToDelete to the currently selected group before showing the alert
                            if let selectedGroup = viewModel.selectedGroup {
                                viewModel.groupToDelete = selectedGroup
                                viewModel.showingDeleteGroupAlert = true
                            }
                        }) {
                            Label("Delete Group (Keep Items)", systemImage: "folder.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                            .font(.system(size: 18))
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        // Prevent tap from propagating to background
                    })
                }
                .padding()
                .padding(.top, 8)
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
                            GroupItemRow(item: item)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
            .padding()
            .contentShape(Rectangle())
            .onTapGesture {
                // Consume tap events on the content area to prevent them from reaching the background
            }
            .offset(x: dragOffset)
            .rotationEffect(rotation)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow dragging to the right (positive x values)
                        if value.translation.width > 0 {
                            dragOffset = value.translation.width
                            // Calculate rotation based on horizontal movement (similar to DayView)
                            let rotationFactor = Double(dragOffset / 40)
                            rotation = Angle(degrees: rotationFactor)
                        }
                    }
                    .onEnded { value in
                        // If dragged more than 100 points to the right, dismiss the view
                        if value.translation.width > 100 {
                            // Animate the view off screen (similar to DayView)
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                dragOffset = UIScreen.main.bounds.width * 1.5
                                rotation = Angle(degrees: 10)
                            }
                            
                            // Dismiss after animation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isPresented = false
                                // Reset for next time
                                dragOffset = 0
                                rotation = .zero
                            }
                        } else {
                            // Otherwise, animate back to original position
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                dragOffset = 0
                                rotation = .zero
                            }
                        }
                    }
            )
            
            // Color picker sheet
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
            }
        }
        .zIndex(1) // Ensure this appears above the main view
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
                viewModel.groupToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteGroupKeepItems()
            }
        } message: {
            Text("Are you sure you want to delete this group? The items will remain but will no longer be grouped.")
        }
        .alert("Edit Group Name", isPresented: $viewModel.showingEditNameAlert) {
            TextField("Group Name", text: $viewModel.editingGroupName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                viewModel.updateGroupName(viewModel.editingGroupName)
            }
        } message: {
            Text("Enter a new name for this group")
        }
    }
}

struct GroupItemRow: View {
    let item: Models.ChecklistItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(item.isCompleted ? .green : .gray)
                .font(.system(size: 18))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .strikethrough(item.isCompleted)
                    .lineLimit(1)
                
                // Format the date
                Text(formattedDate(item.date))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// Color Picker View
struct ColorPickerView: View {
    @Binding var isPresented: Bool
    @Binding var selectedRed: Double
    @Binding var selectedGreen: Double
    @Binding var selectedBlue: Double
    @Binding var hasColor: Bool
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
            // Background overlay
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isPresented = false
                }
            
            // Color picker content
            VStack(spacing: 12) {
                // Header
                HStack {
                    Text("Select Color")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Done") {
                        isPresented = false
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
            .frame(width: 300, height: 300) // More compact height
            .background(
                Color.clear
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                // Consume tap events on the content area
            }
        }
        .zIndex(2) // Above the group details view
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
