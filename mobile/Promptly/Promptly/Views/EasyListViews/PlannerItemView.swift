import SwiftUI
import Combine

// Define a debug helper function at the top level
private func debugLog(_ source: String, _ action: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("\(timestamp) [PlannerItemView]: \(source) - \(action)")
}

// MARK: - Helper Structures

// Break callbacks into smaller, focused structures
struct ItemCallbacks {
    let onLoseFocus: ((String) -> Void)?
    
    init(
        onLoseFocus: ((String) -> Void)? = nil
    ) {
        self.onLoseFocus = onLoseFocus
    }
}

struct MetadataCallbacks {
    let onNotificationChange: ((Date?) -> Void)?
    let onGroupChange: ((UUID?) -> Void)?
    
    init(
        onNotificationChange: ((Date?) -> Void)? = nil,
        onGroupChange: ((UUID?) -> Void)? = nil
    ) {
        self.onNotificationChange = onNotificationChange
        self.onGroupChange = onGroupChange
    }
}

//The PlannerItemView does not get updates from the EasyListView, it updates its state locally and
//sends those updates down to the EasyListView as the true state manager.
//This View is more of a UI element that sends updates down to the easylistview in a
//unidirectional channel.

// Extended DisplayData that includes all the UI state we need
// This replaces both the original displayData and localState
struct MutablePlannerItemData {
    // Original data from model
    var id: UUID
    var title: String
    var isCompleted: Bool
    var notification: Date?
    var groupId: UUID?
    var groupTitle: String?
    var groupColor: Color?
    var subItems: [PlannerItemDisplayData.SubItemDisplayData]
    var date: Date
    
    // UI state (previously in localState)
    var isDeleting: Bool = false
    var showingPopover: Bool = false
    var opacity: Double = 1.0
    var isGroupSectionExpanded: Bool = false
    var areSubItemsExpanded: Bool = false
    var isCompletedLocally: Bool
    var subItemsCompletedLocally: [UUID: Bool] = [:]
    
    // Initialize from PlannerItemDisplayData
    init(from displayData: PlannerItemDisplayData) {
        self.id = displayData.id
        self.title = displayData.title
        self.isCompleted = displayData.isCompleted
        self.notification = displayData.notification
        self.groupId = displayData.groupId
        self.groupTitle = displayData.groupTitle
        self.groupColor = displayData.groupColor
        self.subItems = displayData.subItems
        self.date = displayData.date
        
        // Set initial UI state
        self.isCompletedLocally = displayData.isCompleted
    }
    
    mutating func startDeletingAnimation() {
        debugLog("startDeletingAnimation", "called")
        isDeleting = true
        // Animation will be handled by the View
    }
}

// Helper for formatting dates
private func formatNotificationTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

// MARK: - Menu button component
private struct ItemMenuButton: View {
    @Binding var itemData: MutablePlannerItemData
    let itemCallbacks: ItemCallbacks
    let metadataCallbacks: MetadataCallbacks
    
    var body: some View {
        Button(action: {
            itemData.isGroupSectionExpanded = false
            itemData.showingPopover = true
        }) {
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .popover(isPresented: $itemData.showingPopover,
                 attachmentAnchor: .point(.center),
                 arrowEdge: .trailing) {
            PopoverContentView(
                itemId: itemData.id,
                itemDate: itemData.date,
                itemNotification: itemData.notification,
                itemGroupId: itemData.groupId,
                isGroupSectionExpanded: $itemData.isGroupSectionExpanded,
                onNotificationChange: { newNotification in
                    // Update data immediately
                    itemData.notification = newNotification
                    
                    // Then call the parent callback to update the data model
                    metadataCallbacks.onNotificationChange?(newNotification)
                },
                onGroupChange: { newGroupId in
                    // Update data immediately
                    itemData.groupId = newGroupId
                    
                    // Then call the parent callback to update the data model
                    metadataCallbacks.onGroupChange?(newGroupId)
                },
                onDelete: { 
                    itemData.startDeletingAnimation()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        itemCallbacks.onLoseFocus?("")
                        itemData.showingPopover = false
                    }
                }
            )
            .presentationCompactAdaptation(.none)
        }
        .onDisappear {
            itemData.isGroupSectionExpanded = false
        }
    }
}

// MARK: - Main item row component
private struct MainItemRow: View {
    @Binding var itemData: MutablePlannerItemData
    let onToggleItem: ((UUID, Date?) -> Void)?
    let itemCallbacks: ItemCallbacks
    let metadataCallbacks: MetadataCallbacks
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Checkbox button
            Button(action: {
                feedbackGenerator.impactOccurred()
                // Update local state immediately
                itemData.isCompletedLocally.toggle()
                // Notify parent of the change
                onToggleItem?(itemData.id, itemData.notification)
            }) {
                Image(systemName: itemData.isCompletedLocally ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(itemData.isCompletedLocally ? .green : .gray)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            
            // Text input area
            ItemTextInputArea(
                title: itemData.title,
                isCompletedLocally: itemData.isCompletedLocally
            )
            
            // Expand/collapse button
            if !itemData.subItems.isEmpty {
                ExpandCollapseButton(
                    hasSubItems: !itemData.subItems.isEmpty,
                    areSubItemsExpanded: $itemData.areSubItemsExpanded
                )
            }
            
            // Menu button
            ItemMenuButton(
                itemData: $itemData,
                itemCallbacks: itemCallbacks,
                metadataCallbacks: metadataCallbacks
            )
        }
        // Add listRowSeparator to avoid rendering separators
        .listRowSeparator(.hidden) 
        // Prepare haptic feedback once during initialization
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
}

// MARK: - Text input area component
private struct ItemTextInputArea: View {
    let title: String
    let isCompletedLocally: Bool
    // Simplified properties
    private var displayText: String {
        title.isEmpty ? "Enter task here..." : title
    }
    
    private var textOpacity: Double {
        isCompletedLocally ? 0.7 : 1.0
    }
    
    private var textColor: Color {
        title.isEmpty ? .gray : .white
    }
    
    var body: some View {
        // Simple Text view with no editing capabilities
        Text(displayText)
            .foregroundColor(textColor)
            .lineLimit(isCompletedLocally ? 1 : 2)
            .truncationMode(.tail)
            .strikethrough(isCompletedLocally, color: .gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, 5)
            .opacity(textOpacity)
            .contentShape(Rectangle())
    }
}

// MARK: - Expand/collapse button component
private struct ExpandCollapseButton: View {
    let hasSubItems: Bool
    @Binding var areSubItemsExpanded: Bool
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        // Only show the button if there are subitems
        if hasSubItems {
            Button(action: {
                feedbackGenerator.impactOccurred()
                
                // Toggle expanded state
                areSubItemsExpanded.toggle()
                
                // Animate UI changes
                withAnimation(.easeOut(duration: 0.25)) {
                    // Empty animation block to handle view updates
                }
            }) {
                Image(systemName: areSubItemsExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .onAppear {
                feedbackGenerator.prepare()
            }
        } else {
            // Empty spacer when there are no subitems
            Spacer()
                .frame(width: 30, height: 30)
        }
    }
}

// MARK: - Metadata row component
private struct MetadataRow: View {
    @Binding var itemData: MutablePlannerItemData
    
    private var hasValidGroup: Bool {
        return itemData.groupTitle != nil
    }
    
    var body: some View {
        // Only show notification or group info if not completed or if subitems are expanded
        let hasNotification = (!itemData.isCompletedLocally || itemData.areSubItemsExpanded) && 
                             itemData.notification != nil
        let hasGroup = (!itemData.isCompletedLocally || itemData.areSubItemsExpanded) && hasValidGroup
        
        if hasNotification || hasGroup {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 30)
                
                if hasGroup, let groupTitle = itemData.groupTitle {
                    Text(groupTitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                if let notificationTime = itemData.notification, hasNotification {
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill")
                            .font(.footnote)
                        
                        let isPastDue = notificationTime < Date()
                        Text(formatNotificationTime(notificationTime))
                            .font(.footnote)
                            .foregroundColor(isPastDue ? .red.opacity(0.5) : .white.opacity(0.5))
                            .strikethrough(itemData.isCompletedLocally, color: .gray)
                    }
                    .foregroundColor(notificationTime < Date() ? .red.opacity(0.5) : .white.opacity(0.5))
                }
            }
            .padding(.leading, 1)
            .padding(.top, -8)
            .padding(.bottom, 0)
            .frame(height: 16)
        }
    }
}

// MARK: - Individual subitem row component
private struct SubItemRowView: View {
    let subItem: PlannerItemDisplayData.SubItemDisplayData
    @Binding var itemData: MutablePlannerItemData
    let onToggleSubItem: ((UUID, UUID, Bool) -> Void)?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    // Computed property to get the local completion state
    private var isSubItemCompletedLocally: Bool {
        // Use locally tracked state if available, otherwise fall back to the original state
        itemData.subItemsCompletedLocally[subItem.id] ?? subItem.isCompleted
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Checkbox button
            Button(action: {
                debugLog("SubItemRowView", "checkbox button tapped")
                feedbackGenerator.impactOccurred()
                
                // Update local state immediately
                let newCompletedState = !isSubItemCompletedLocally
                itemData.subItemsCompletedLocally[subItem.id] = newCompletedState
                
                // Call the callback
                onToggleSubItem?(itemData.id, subItem.id, newCompletedState)
            }) {
                Image(systemName: isSubItemCompletedLocally ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSubItemCompletedLocally ? .green : .gray)
                    .font(.system(size: 16))
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
                    .scaleEffect(isSubItemCompletedLocally ? 1.1 : 1.0)
                    .rotationEffect(.degrees(isSubItemCompletedLocally ? 360 : 0))
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSubItemCompletedLocally)
            }
            .buttonStyle(.plain)
            .zIndex(2)
            
            // Simple Text view
            Text(subItem.title)
                .font(.subheadline)
                .foregroundColor(.white)
                .strikethrough(isSubItemCompletedLocally, color: .gray)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(isSubItemCompletedLocally ? 0.7 : 1.0)
                .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: .leading)
                .padding(.vertical, 3)
        }
        .padding(.leading, 0)
        .frame(height: 30)
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
}

// MARK: - Subitem list component
private struct SubItemListView: View {
    @Binding var itemData: MutablePlannerItemData
    let onToggleSubItem: ((UUID, UUID, Bool) -> Void)?
    
    var body: some View {
        ForEach(itemData.subItems, id: \.id) { subItem in
            SubItemRowView(
                subItem: subItem,
                itemData: $itemData,
                onToggleSubItem: onToggleSubItem
            )
            .id("subitem-\(itemData.id.uuidString)-\(subItem.id.uuidString)-\(subItem.isCompleted.description)")
        }
    }
}

// MARK: - SubItems section
private struct SubItemsSection: View {
    @Binding var itemData: MutablePlannerItemData
    let onToggleSubItem: ((UUID, UUID, Bool) -> Void)?
    
    var body: some View {
        if itemData.areSubItemsExpanded {
            VStack(spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 0)
                
                LazyVStack(alignment: .leading, spacing: 2) {
                    SubItemListView(
                        itemData: $itemData,
                        onToggleSubItem: onToggleSubItem
                    )
                    .id("subitems-list-\(itemData.id.uuidString)-\(itemData.subItems.count)")
                }
                .padding(.leading, 4)
                .padding(.trailing, 0)
                .padding(.top, 2)
                .animation(.linear(duration: 0.15), value: itemData.subItems.count)
            }
            .modifier(SubItemsTransitionModifier())
            .id("subitems-section-\(itemData.id.uuidString)-\(itemData.areSubItemsExpanded)-\(itemData.subItems.count)")
        }
    }
}

// MARK: - Main PlannerItemView
struct PlannerItemView: View, Equatable {
    // Single mutable state source that combines displayData and localState
    @State private var itemData: MutablePlannerItemData
    @State private var isGlowing: Bool = false
    
    // Store the display data to observe changes
    let displayData: PlannerItemDisplayData
    
    // Direct access to GroupStore for current group info
    @ObservedObject private var groupStore = GroupStore.shared
    
    // Derived state for group info
    private var groupInfo: (title: String?, color: Color?) {
        if let groupId = itemData.groupId {
            if let group = groupStore.getGroup(by: groupId) {
                // Just return the values without modifying state
                let color = group.hasColor ? Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue) : nil
                return (group.title, color)
            }
        }
        // Use the stored values if we can't get them from GroupStore
        return (itemData.groupTitle, itemData.groupColor)
    }
    
    // Callbacks to parent
    let onToggleItem: ((UUID, Date?) -> Void)?
    let onToggleSubItem: ((UUID, UUID, Bool) -> Void)?
    let onLoseFocus: ((String) -> Void)?
    let onNotificationChange: ((Date?) -> Void)?
    let onGroupChange: ((UUID?) -> Void)?
    let onItemTap: ((UUID) -> Void)?
    
    // MARK: - Equatable Implementation
    static func == (lhs: PlannerItemView, rhs: PlannerItemView) -> Bool {
        // If both have lastModified timestamps, compare them
        if let lhsModified = lhs.displayData.lastModified,
           let rhsModified = rhs.displayData.lastModified {
            return lhs.itemData.id == rhs.itemData.id && 
                   lhs.itemData.isCompleted == rhs.itemData.isCompleted && 
                   lhs.itemData.title == rhs.itemData.title &&
                   lhsModified == rhsModified
        }
        
        // If either doesn't have lastModified, just compare the other fields
        return lhs.itemData.id == rhs.itemData.id && 
               lhs.itemData.isCompleted == rhs.itemData.isCompleted && 
               lhs.itemData.title == rhs.itemData.title
    }
    
    init(
        displayData: PlannerItemDisplayData,
        onToggleItem: ((UUID, Date?) -> Void)? = nil,
        onToggleSubItem: ((UUID, UUID, Bool) -> Void)? = nil,
        onLoseFocus: ((String) -> Void)? = nil,
        onNotificationChange: ((Date?) -> Void)? = nil,
        onGroupChange: ((UUID?) -> Void)? = nil,
        onItemTap: ((UUID) -> Void)? = nil
    ) {
        // Store the display data
        self.displayData = displayData
        // Initialize the itemData from displayData
        self._itemData = State(initialValue: MutablePlannerItemData(from: displayData))
        
        self.onToggleItem = onToggleItem
        self.onToggleSubItem = onToggleSubItem
        self.onLoseFocus = onLoseFocus
        self.onNotificationChange = onNotificationChange
        self.onGroupChange = onGroupChange
        self.onItemTap = onItemTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MainItemRow(
                itemData: $itemData,
                onToggleItem: onToggleItem,
                itemCallbacks: ItemCallbacks(
                    onLoseFocus: onLoseFocus
                ),
                metadataCallbacks: MetadataCallbacks(
                    onNotificationChange: onNotificationChange,
                    onGroupChange: onGroupChange
                )
            )
            
            MetadataRow(
                itemData: $itemData
            )
            
            SubItemsSection(
                itemData: $itemData,
                onToggleSubItem: onToggleSubItem
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.4))
                
                if itemData.isDeleting {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.65 * itemData.opacity))
                } else if let color = groupInfo.color {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.25))
                }
                
                // Glow effect
                if isGlowing {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .blur(radius: 8)
                        .opacity(0.15)
                }
            }
        )
        .opacity(itemData.opacity)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .contentShape(Rectangle()) // Make the entire view tappable
        .onTapGesture {
            // Trigger tap glow animation
            isGlowing = true
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isGlowing = false
                }
            }
            onItemTap?(itemData.id)
        }
        .listRowSeparator(.hidden)
        // Watch for local completed state changes to trigger animations
        .onChange(of: itemData.isCompletedLocally) { _, isCompleted in
            if isCompleted {
                // Trigger glow animation
                isGlowing = true
                // Glow effect eases in then out immediately
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isGlowing = false
                    }
                }
            }
        }
        // Animation for deletion
        .onChange(of: itemData.isDeleting) { _, isDeleting in
            if isDeleting {
                withAnimation(.easeOut(duration: 0.25)) {
                    itemData.opacity = 0.1
                }
            }
        }
        .onChange(of: itemData.groupId) { _, newGroupId in
            // Update group info when the groupId changes
            if newGroupId != nil {
                _ = updateGroupInfo()
            } else {
                // When group is removed, clear the group info
                itemData.groupTitle = nil
                itemData.groupColor = nil
            }
        }
        .onChange(of: displayData) { _, newDisplayData in
            itemData = MutablePlannerItemData(from: newDisplayData)
        }
    }
    
    // Update the group info in itemData from GroupStore
    private func updateGroupInfo() -> Bool {
        if let groupId = itemData.groupId, let group = groupStore.getGroup(by: groupId) {
            itemData.groupTitle = group.title
            itemData.groupColor = group.hasColor ? Color(red: group.colorRed, green: group.colorGreen, blue: group.colorBlue) : nil
            return true
        }
        return false
    }
}

// MARK: - Factory Method
extension PlannerItemView {
    static func create(
        displayData: PlannerItemDisplayData,
        onToggleItem: ((UUID, Date?) -> Void)? = nil,
        onToggleSubItem: ((UUID, UUID, Bool) -> Void)? = nil,
        onLoseFocus: ((String) -> Void)? = nil,
        onNotificationChange: ((Date?) -> Void)? = nil,
        onGroupChange: ((UUID?) -> Void)? = nil,
        onItemTap: ((UUID) -> Void)? = nil
    ) -> PlannerItemView {
        return PlannerItemView(
            displayData: displayData,
            onToggleItem: onToggleItem,
            onToggleSubItem: onToggleSubItem,
            onLoseFocus: onLoseFocus,
            onNotificationChange: onNotificationChange,
            onGroupChange: onGroupChange,
            onItemTap: onItemTap
        )
    }
}

// Define a custom transition modifier for SubItems to have different animations for expand/contract
struct SubItemsTransitionModifier: ViewModifier {
    @State private var animState: Bool = false
    @State private var hasAnimatedBefore: Bool = false
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                if !hasAnimatedBefore {
                    // Only animate the first time it appears after being added to the view hierarchy
                    withAnimation(.easeOut(duration: 0.2)) {
                        animState = true
                    }
                    // Mark that we've animated once
                    hasAnimatedBefore = true
                } else {
                    // If reappearing due to scrolling, just set the final state without animation
                    animState = true
                }
            }
            .onDisappear {
                // Don't reset the hasAnimatedBefore flag on disappear
                // But we do need to reset animState so the transition works properly
                animState = false
            }
            // Simplify transition to basic move and opacity
            .transition(.move(edge: .top).combined(with: .opacity))
            // Apply simpler transformations without the 3D effect for better performance
            .opacity(animState ? 1 : 0)
            .scaleEffect(y: animState ? 1 : 0.01, anchor: .top) // Start with minimal height from the top
    }
}


