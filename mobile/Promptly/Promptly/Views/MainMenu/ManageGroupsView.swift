import SwiftUI

struct ManageGroupsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = ManageGroupsViewModel()
    @State private var showingInfoPopover = false
    @FocusState private var isNewGroupFieldFocused: Bool
    @State private var refreshCounter: Int = 0 // Add a counter to force refresh
    @State private var dragOffset = CGSize.zero // Add drag offset for swipe gesture
    @State private var detailsViewModel: GroupDetailsViewModel? = nil
    @State private var activeView: ActiveView = .manageGroups // Track which view is active
    var onNavigateToDate: ((Date) -> Void)? = nil
    
    // Define an enum for the possible views
    enum ActiveView {
        case manageGroups
        case groupDetails
    }
    
    var body: some View {
        ZStack {
            // Conditionally show either the ManageGroupsView content or GroupDetailsView
            if activeView == .manageGroups {
                // Main content - ManageGroupsView
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
                                Text("Groups are used to organize tasks together.")
                            }
                            .padding()
                            .frame(width: 250)
                            .background(.ultraThinMaterial)
                            .presentationCompactAdaptation(.none)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.saveNewGroupIfNeeded()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 18, weight: .medium))
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding()
                    
                    Divider()
                        .background(Color.white.opacity(0.2))

                    
                    // List content
                    List {
                        
                        ForEach(viewModel.groups) { group in
                            // Only show the group if it's not pending deletion
                            if viewModel.groupIdToRemove != group.id {
                                GroupRow(group: group, viewModel: viewModel, onGroupTap: { tappedGroup in
                                    // Create a new details view model
                                    let newViewModel = GroupDetailsViewModel()
                                    newViewModel.setSelectedGroup(tappedGroup)
                                    detailsViewModel = newViewModel
                                    
                                    // Switch to details view with animation
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        activeView = .groupDetails
                                    }
                                })
                                .contentShape(Rectangle())
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
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
                        .padding(.vertical, 0)
                        .padding(.horizontal, 0)
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
                .transition(.opacity)
                .zIndex(999)
            } else if activeView == .groupDetails, let detailsVM = detailsViewModel {
                // Show the Group details view
                GroupDetailsView(
                    viewModel: detailsVM,
                    isPresented: Binding(
                        get: { activeView == .groupDetails },
                        set: { if !$0 { 
                            // Switch back to manage groups view with animation
                            withAnimation(.easeIn(duration: 0.2)) {
                                activeView = .manageGroups
                            }
                            // Clean up
                            refreshCounter += 1
                        }}
                    ),
                    closeAllViews: {
                        viewModel.saveNewGroupIfNeeded()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    },
                    onNavigateToDate: { date in
                        // Clean up
                        viewModel.saveNewGroupIfNeeded()
                        
                        // Handle navigation (which will close all views)
                        DispatchQueue.main.async {
                            if let parentNavigate = onNavigateToDate {
                                parentNavigate(date)
                            }
                        }
                    }
                )
                .transition(.move(edge: .trailing))
                .zIndex(999)
            }
        }
        // Apply animation to the ZStack for view transitions
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: activeView)
        .onAppear {
            viewModel.loadGroups()
        }
        .onChange(of: isPresented) {oldValue, newValue in
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

// Helper Views
struct GroupRow: View {
    let group: Models.ItemGroup
    @ObservedObject private var viewModel: ManageGroupsViewModel
    @ObservedObject private var groupStore = GroupStore.shared
    @State private var isGlowing: Bool = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    let onGroupTap: (Models.ItemGroup) -> Void
    
    init(group: Models.ItemGroup, viewModel: ManageGroupsViewModel, onGroupTap: @escaping (Models.ItemGroup) -> Void) {
        self.group = group
        self.viewModel = viewModel
        self.onGroupTap = onGroupTap
    }
    
    var body: some View {
        // Get the current group from the store to ensure we have the latest data
        let currentGroup = groupStore.groups.first(where: { $0.id == group.id }) ?? group
        
        HStack(spacing: 12) {
            // Main content with navigation
            Button(action: {
                
                // Start the glow animation
                isGlowing = true
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isGlowing = false
                    }
                }
                
                // Call the tap handler which will switch to the details view
                onGroupTap(currentGroup)
            }) {
                HStack {
                    // Color indicator
                    if currentGroup.hasColor {
                        // Add folder icon
                        Image(systemName: "folder")
                            .font(.subheadline)
                            .foregroundColor(Color(red: currentGroup.colorRed, green: currentGroup.colorGreen, blue: currentGroup.colorBlue))
                            .padding(.trailing, 4)
                    } else {
                        Image(systemName: "folder")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.trailing, 4)
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
