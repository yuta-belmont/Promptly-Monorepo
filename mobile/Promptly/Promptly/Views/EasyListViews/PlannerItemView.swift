import SwiftUI
import Combine

class PlannerFocusManager: ObservableObject {
    // Read-only properties that track focus state
    @Published private(set) var isTitleEditing: Bool = false
    @Published private(set) var focusedSubItemId: UUID? = nil
    @Published private(set) var isNewSubItemFocused: Bool = false
    
    // A computed property to check if any element has focus
    var hasAnyFocus: Bool {
        isTitleEditing || focusedSubItemId != nil || isNewSubItemFocused
    }
    
    // Update focus state from view
    func updateFocusState(titleEditing: Bool, subItemId: UUID?, newSubItemFocused: Bool) {
        self.isTitleEditing = titleEditing
        self.focusedSubItemId = subItemId
        self.isNewSubItemFocused = newSubItemFocused
    }
    
    // Remove all focus states
    func removeAllFocus() {
        
        if self.hasAnyFocus {
            updateFocusState(
                titleEditing: false,
                subItemId: nil,
                newSubItemFocused: false
            )
        }
    }
}

// Break callbacks into smaller, focused structures
struct ItemCallbacks {
    let onToggle: (() -> Void)?
    let onTextChange: ((String) -> Void)?
    let onLoseFocus: ((String) -> Void)?
    
    init(
        onToggle: (() -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onLoseFocus: ((String) -> Void)? = nil,
        onReturn: (() -> Void)? = nil
    ) {
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onLoseFocus = onLoseFocus
    }
}

struct SubItemCallbacks {
    let onAddSubItem: ((String) -> Void)?
    let onSubItemToggle: ((UUID) -> Void)?
    let onSubItemTextChange: ((UUID, String) -> Void)?
    
    init(
        onAddSubItem: ((String) -> Void)? = nil,
        onSubItemToggle: ((UUID) -> Void)? = nil,
        onSubItemTextChange: ((UUID, String) -> Void)? = nil
    ) {
        self.onAddSubItem = onAddSubItem
        self.onSubItemToggle = onSubItemToggle
        self.onSubItemTextChange = onSubItemTextChange
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

// Main item row component
private struct MainItemRow: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    @ObservedObject var focusManager: PlannerFocusManager
    let itemCallbacks: ItemCallbacks
    let metadataCallbacks: MetadataCallbacks
    @Binding var shouldShowTextEditor: Bool
    let isTitleEditing: FocusState<Bool>.Binding
    let focusTitle: () -> Void
    let focusNewSubItem: () -> Void
    let focusCoordinator: PlannerFocusCoordinator
    let removeAllFocus: () -> Void
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Checkbox button
            Button(action: {
                feedbackGenerator.impactOccurred()
                itemCallbacks.onToggle?()
                viewModel.toggleItem()
            }) {
                Image(systemName: viewModel.item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.item.isCompleted ? .green : .gray)
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            
            // Text input area
            ItemTextInputArea(
                viewModel: viewModel,
                shouldShowTextEditor: $shouldShowTextEditor,
                isTitleEditing: isTitleEditing,
                itemCallbacks: itemCallbacks,
                focusManager: focusManager,
                focusCoordinator: focusCoordinator,
                focusTitle: focusTitle,
                removeAllFocus: removeAllFocus
            )
            
            // Expand/collapse button
            ExpandCollapseButton(
                viewModel: viewModel,
                focusManager: focusManager,
                focusNewSubItem: focusNewSubItem
            )
            
            // Menu button
            ItemMenuButton(
                viewModel: viewModel,
                itemCallbacks: itemCallbacks,
                metadataCallbacks: metadataCallbacks
            )
        }
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
}

// Text input area component
private struct ItemTextInputArea: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    @Binding var shouldShowTextEditor: Bool
    let isTitleEditing: FocusState<Bool>.Binding
    let itemCallbacks: ItemCallbacks
    let focusManager: PlannerFocusManager
    let focusCoordinator: PlannerFocusCoordinator
    let focusTitle: () -> Void
    let removeAllFocus: () -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if shouldShowTextEditor || viewModel.areSubItemsExpanded {
                TextEditor(text: $viewModel.text)
                    .focused(isTitleEditing)
                    .onChange(of: viewModel.text) { oldValue, newValue in
                        if newValue.contains("\n") {
                            viewModel.text = newValue.replacingOccurrences(of: "\n", with: "")
                            removeAllFocus()
                        } else {
                            itemCallbacks.onTextChange?(newValue)
                        }
                    }
                    .onSubmit {
                        if viewModel.text.isEmpty {
                            removeAllFocus()
                        }
                    }
                    .submitLabel(.done)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.vertical, -1)
                    .padding(.trailing, -4)
                    .opacity(viewModel.item.isCompleted ? 0.7 : 1.0)
            } else {
                Text(viewModel.text.isEmpty ? "Enter task here..." : viewModel.text)
                    .foregroundColor(viewModel.text.isEmpty ? .gray : .white)
                    .lineLimit(viewModel.item.isCompleted ? 1 : 2)
                    .truncationMode(.tail)
                    .strikethrough(viewModel.item.isCompleted, color: .gray)
                    .opacity(viewModel.item.isCompleted ? 0.7 : 1.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.leading, 5)
                    .padding(.trailing, -6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            shouldShowTextEditor = true
            focusTitle()
        }
        .padding(.vertical, 0)
    }
}

// Expand/collapse button component
private struct ExpandCollapseButton: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    let focusManager: PlannerFocusManager
    let focusNewSubItem: () -> Void
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        Button(action: {
            feedbackGenerator.impactOccurred()
            let isAddingFirstSubItem = viewModel.item.subItems.isEmpty && !viewModel.areSubItemsExpanded
            
            // 1. Update data state
            viewModel.areSubItemsExpanded.toggle()
            
            // 2. Set focus if needed
            if isAddingFirstSubItem {
                focusNewSubItem()
            }
            
            // 3. Animate UI changes
            withAnimation(.easeOut(duration: 0.25)) {
                // Empty animation block to handle view updates
            }
        }) {
            if viewModel.item.subItems.isEmpty && !viewModel.areSubItemsExpanded {
                Image(systemName: "plus")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 18))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: viewModel.areSubItemsExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
}

// Menu button component
private struct ItemMenuButton: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    let itemCallbacks: ItemCallbacks
    let metadataCallbacks: MetadataCallbacks
    
    var body: some View {
        Button(action: {
            viewModel.isGroupSectionExpanded = false
            viewModel.showingPopover = true
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
        .popover(isPresented: $viewModel.showingPopover,
                 attachmentAnchor: .point(.center),
                 arrowEdge: .trailing) {
            PopoverContentView(
                item: viewModel.item,
                isGroupSectionExpanded: $viewModel.isGroupSectionExpanded,
                onNotificationChange: { newNotification in
                    metadataCallbacks.onNotificationChange?(newNotification)
                    viewModel.updateNotification(newNotification)
                },
                onGroupChange: { newGroupId in
                    metadataCallbacks.onGroupChange?(newGroupId)
                    viewModel.updateGroup(newGroupId)
                },
                onDelete: { 
                    viewModel.startDeletingAnimation()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        itemCallbacks.onLoseFocus?("")
                        viewModel.showingPopover = false
                    }
                }
            )
            .presentationCompactAdaptation(.none)
        }
        .onDisappear {
            viewModel.isGroupSectionExpanded = false
        }
    }
}

// Metadata row component
private struct MetadataRow: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    
    var body: some View {
        let hasNotification = (!viewModel.item.isCompleted || viewModel.areSubItemsExpanded) && viewModel.item.notification != nil
        let hasGroup = (!viewModel.item.isCompleted || viewModel.areSubItemsExpanded) && viewModel.hasValidGroup()
        
        if hasNotification || hasGroup {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 30)
                
                if hasGroup, let groupTitle = viewModel.getGroupTitle() {
                    Text(groupTitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                if let notificationTime = viewModel.item.notification, hasNotification {
                    HStack(spacing: 2) {
                        Image(systemName: "bell.fill")
                            .font(.footnote)
                        
                        let isPastDue = notificationTime < Date()
                        Text(viewModel.formatNotificationTime(notificationTime))
                            .font(.footnote)
                            .foregroundColor(isPastDue ? .red.opacity(0.5) : .white.opacity(0.5))
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

// Individual subitem row component
private struct SubItemRowView: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    let subItem: Models.SubItem
    let onReturn: (UUID) -> Void
    @FocusState.Binding var focusedSubItemId: UUID?
    let onStartEdit: (UUID) -> Void
    let onStartNewSubItem: () -> Void
    @State private var localText: String
    @State private var lastTapTime: Date? = nil
    @State private var forceRefresh: Bool = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)

    init(viewModel: PlannerItemViewModel, 
         subItem: Models.SubItem, 
         onReturn: @escaping (UUID) -> Void, 
         focusedSubItemId: FocusState<UUID?>.Binding, 
         onStartEdit: @escaping (UUID) -> Void,
         onStartNewSubItem: @escaping () -> Void) {
        self.viewModel = viewModel
        self.subItem = subItem
        self.onReturn = onReturn
        self._focusedSubItemId = focusedSubItemId
        self.onStartEdit = onStartEdit
        self.onStartNewSubItem = onStartNewSubItem
        self._localText = State(initialValue: subItem.title)
    }
    
    private func handleDeletion() {
        // Find the current subitem's index
        if let currentIndex = viewModel.item.subItems.firstIndex(where: { $0.id == subItem.id }) {
            if currentIndex > 0 {
                // If there's a subitem above, focus it directly
                let previousSubItem = viewModel.item.subItems[currentIndex - 1]
                focusedSubItemId = previousSubItem.id  // Set focus directly
            } else {
                // If this is the first subitem, focus the new subitem field
                focusedSubItemId = nil
                DispatchQueue.main.async {
                    onStartNewSubItem()
                }
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Direct toggle using viewModel only
            Button(action: {
                feedbackGenerator.impactOccurred()
                viewModel.toggleSubItem(subItem.id)
                forceRefresh.toggle()
            }) {
                Image(systemName: subItem.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subItem.isCompleted ? .green : .gray)
                    .font(.system(size: 16))
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
                    .scaleEffect(subItem.isCompleted ? 1.1 : 1.0)
                    .rotationEffect(.degrees(subItem.isCompleted ? 360 : 0))
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: subItem.isCompleted)
            }
            .buttonStyle(.plain)
            .zIndex(2)
            
            CustomTextField(
                text: $localText,
                textColor: .white,
                isStrikethrough: subItem.isCompleted,
                textStyle: .subheadline,  // Use smaller text for subitems
                onReturn: { onReturn(subItem.id) },
                onTextChange: { newText in
                    localText = newText
                    if newText.isEmpty {
                        // If text is becoming empty, handle deletion focus
                        handleDeletion()
                    }
                    viewModel.updateSubItemText(subItem.id, newText: newText)
                }
            )
            .id(forceRefresh)
            .focused($focusedSubItemId, equals: subItem.id)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if focusedSubItemId != subItem.id {
                        onStartEdit(subItem.id)
                    }
                }
            )
            .opacity(subItem.isCompleted ? 0.7 : 1.0)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: focusedSubItemId == subItem.id ? .trailing : .leading)
            .clipped()
            .zIndex(1)
        }
        .padding(.leading, 0)
        .frame(height: 30)
        .onAppear {
            feedbackGenerator.prepare()
        }
    }
}

// Subitem list component
private struct SubItemListView: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    let onSubItemReturn: (UUID) -> Void
    @FocusState.Binding var focusedSubItemId: UUID?
    let onStartEdit: (UUID) -> Void
    let onStartNewSubItem: () -> Void
    
    var body: some View {
        ForEach(viewModel.item.subItems, id: \.id) { subItem in
            SubItemRowView(
                viewModel: viewModel,
                subItem: subItem,
                onReturn: onSubItemReturn,
                focusedSubItemId: $focusedSubItemId,
                onStartEdit: { subItemId in
                    onStartEdit(subItemId)
                },
                onStartNewSubItem: onStartNewSubItem
            )
        }
    }
}

// Consolidated NewSubItemView with all functionality
struct NewSubItemView: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    let onSubmit: () -> Void
    @FocusState.Binding var isNewSubItemFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "circle")
                .foregroundColor(.gray)
                .font(.system(size: 16))
                .frame(width: 44, height: 30)
                .opacity(isNewSubItemFocused ? 1 : 0)
            
            CustomTextField(
                text: $viewModel.newSubItemText,
                textColor: isNewSubItemFocused ? .white : .gray,
                placeholder: "Add subitem...",
                placeholderColor: .gray,
                isStrikethrough: false,
                textStyle: .subheadline,
                onReturn: handleAddSubItem
                
            )
            .focused($isNewSubItemFocused)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if !isNewSubItemFocused {
                        onSubmit()
                    }
                }
            )
            .onChange(of: isNewSubItemFocused) { oldValue, newValue in
                if !newValue && oldValue && !viewModel.newSubItemText.isEmpty {
                    viewModel.addSubItem(viewModel.newSubItemText)
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: isNewSubItemFocused ? .trailing : .leading)
            .clipped()
        }
        .padding(.leading, 0)
        .frame(height: 30)
    }
    
    private func handleAddSubItem() {
        if !viewModel.newSubItemText.isEmpty {
            let textToAdd = viewModel.newSubItemText
            viewModel.addSubItem(textToAdd)
            viewModel.newSubItemText = ""
            onSubmit()
        } else {
            isNewSubItemFocused = false
        }
    }
}

// Update SubItemsSection to use consolidated NewSubItemView
private struct SubItemsSection: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    @FocusState.Binding var focusedSubItemId: UUID?
    @FocusState.Binding var isNewSubItemFocused: Bool
    let onStartEditSubItem: (UUID) -> Void
    let onStartNewSubItem: () -> Void
    
    var body: some View {
        if viewModel.areSubItemsExpanded {
            VStack(spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 0)
                
                VStack(alignment: .leading, spacing: 2) {
                    SubItemListView(
                        viewModel: viewModel,
                        onSubItemReturn: handleSubItemReturn,
                        focusedSubItemId: $focusedSubItemId,
                        onStartEdit: { subItemId in
                            onStartEditSubItem(subItemId)
                        },
                        onStartNewSubItem: onStartNewSubItem
                    )
                    
                    NewSubItemView(
                        viewModel: viewModel,
                        onSubmit: onStartNewSubItem,
                        isNewSubItemFocused: $isNewSubItemFocused
                    )
                }
                .padding(.leading, 4)
                .padding(.trailing, 0)
                .padding(.top, 2)
                .animation(.linear(duration: 0.15), value: viewModel.item.subItems.map { $0.id })
            }
            .modifier(SubItemsTransitionModifier())
        }
    }
    
    private func handleSubItemReturn(subItemId: UUID) {
        if let currentIndex = viewModel.item.subItems.firstIndex(where: { $0.id == subItemId }),
           currentIndex < viewModel.item.subItems.count - 1 {
            onStartEditSubItem(viewModel.item.subItems[currentIndex + 1].id)
        }
        else {
            isNewSubItemFocused = true
            onStartNewSubItem()
        }
    }
}

// Update PlannerItemView to include metadataCallbacks in MainItemRow
struct PlannerItemView: View {
    @StateObject private var viewModel: PlannerItemViewModel
    @StateObject private var focusManager = PlannerFocusManager()
    @EnvironmentObject private var appFocusManager: FocusManager
    @ObservedObject var focusCoordinator: PlannerFocusCoordinator
    
    @FocusState private var isTitleEditing: Bool
    @FocusState private var focusedSubItemId: UUID?
    @FocusState private var isNewSubItemFocused: Bool
    @State private var isGlowing: Bool = false
    
    let externalFocusState: Binding<UUID?>?
    let itemId: UUID
    
    @State private var shouldShowTextEditor: Bool = false
    
    let itemCallbacks: ItemCallbacks
    let subItemCallbacks: SubItemCallbacks
    let metadataCallbacks: MetadataCallbacks
    
    // Add instance identifier
    private let instanceId: String
    
    init(
        item: Models.ChecklistItem,
        focusCoordinator: PlannerFocusCoordinator,
        externalFocusState: Binding<UUID?>?,
        itemCallbacks: ItemCallbacks,
        subItemCallbacks: SubItemCallbacks,
        metadataCallbacks: MetadataCallbacks
    ) {
        self._viewModel = StateObject(wrappedValue: PlannerItemViewModel(item: item))
        self.focusCoordinator = focusCoordinator
        self.itemId = item.id
        self.externalFocusState = externalFocusState
        self.itemCallbacks = itemCallbacks
        self.subItemCallbacks = subItemCallbacks
        self.metadataCallbacks = metadataCallbacks
        self.instanceId = String(item.id.uuidString.prefix(4))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MainItemRow(
                viewModel: viewModel,
                focusManager: focusManager,
                itemCallbacks: itemCallbacks,
                metadataCallbacks: metadataCallbacks,
                shouldShowTextEditor: $shouldShowTextEditor,
                isTitleEditing: $isTitleEditing,
                focusTitle: focusTitle,
                focusNewSubItem: { startNewSubItem() },
                focusCoordinator: focusCoordinator,
                removeAllFocus: removeAllFocus
            )
            
            MetadataRow(viewModel: viewModel)
            
            SubItemsSection(
                viewModel: viewModel,
                focusedSubItemId: $focusedSubItemId,
                isNewSubItemFocused: $isNewSubItemFocused,
                onStartEditSubItem: startEditingSubItem,
                onStartNewSubItem: startNewSubItem
            )
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.2))
                
                if viewModel.isDeleting {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.65 * viewModel.opacity))
                } else if let color = viewModel.groupColor {
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
        .opacity(viewModel.opacity)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        
        // One-way focus management
        .onAppear {
            shouldShowTextEditor = focusManager.hasAnyFocus
            focusCoordinator.register(focusManager, for: itemId)
        }
        .onDisappear {
            focusCoordinator.unregister(itemId: itemId)
        }
        .onChange(of: focusManager.hasAnyFocus) { _, isEditing in
            print("[PlannerItemView \(instanceId)] hasAnyFocus changed to: \(isEditing)")
            focusCoordinator.updateFocus(for: itemId, hasAnyFocus: isEditing)
        }
        .onChange(of: isTitleEditing) { oldValue, newValue in
            print("[PlannerItemView \(instanceId)] isTitleEditing changed from: \(oldValue) to: \(newValue)")
            focusManager.updateFocusState(
                titleEditing: newValue,
                subItemId: focusedSubItemId,
                newSubItemFocused: isNewSubItemFocused
            )
            shouldShowTextEditor = focusManager.hasAnyFocus
            if !newValue && oldValue {
                itemCallbacks.onLoseFocus?(viewModel.text)
                saveEntireItem()
            }
        }
        .onChange(of: focusedSubItemId) { oldValue, newValue in
            print("[PlannerItemView \(instanceId)] focusedSubItemId changed from: \(String(describing: oldValue)) to: \(String(describing: newValue))")
            focusManager.updateFocusState(
                titleEditing: isTitleEditing,
                subItemId: newValue,
                newSubItemFocused: isNewSubItemFocused
            )
            shouldShowTextEditor = focusManager.hasAnyFocus
        }
        .onChange(of: isNewSubItemFocused) { oldValue, newValue in
            print("[PlannerItemView \(instanceId)] isNewSubItemFocused changed from: \(oldValue) to: \(newValue)")
            focusManager.updateFocusState(
                titleEditing: isTitleEditing,
                subItemId: focusedSubItemId,
                newSubItemFocused: newValue
            )
            shouldShowTextEditor = focusManager.hasAnyFocus
        }
        .onChange(of: viewModel.item.isCompleted) { _, isCompleted in
            if isCompleted {
                // Trigger glow animation
                isGlowing = true
                // Remove glow after delay
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        isGlowing = false
                    }
                }
            }
        }
        .onChange(of: focusCoordinator.focusedItemId) { _, newId in
            print("[PlannerItemView \(instanceId)] focusCoordinator.focusedItemId changed to: \(String(describing: newId))")
            if newId != itemId {
                removeAllFocus()
            }
        }
        // Remove the direct focus handling from global focus manager changes
        // Let the coordinator handle it through EasyListView's RemoveAllFocus
        .onChange(of: appFocusManager.currentFocusedView) { oldValue, newValue in
            print("[PlannerItemView \(instanceId)] appFocusManager.currentFocusedView changed from: \(String(describing: oldValue)) to: \(String(describing: newValue))")
        }
    }
    
    // Focus methods that directly set @FocusState
    func focusTitle() {
        print("[PlannerItemView \(instanceId)] focusTitle() called for itemId: \(itemId)")
        shouldShowTextEditor = true  // First ensure TextEditor is present
        // Use DispatchQueue to ensure TextEditor is rendered before setting focus
        DispatchQueue.main.async {
            isTitleEditing = true
            focusedSubItemId = nil
            isNewSubItemFocused = false
        }
    }
    
    private func startEditingSubItem(_ id: UUID) {
        print("[PlannerItemView \(instanceId)] startEditingSubItem() called for subItemId: \(id)")
        // First, update the focus manager state
        focusManager.updateFocusState(
            titleEditing: false,
            subItemId: id,
            newSubItemFocused: false
        )
        
        // Batch the individual focus state updates in the next run loop
        DispatchQueue.main.async {
            isTitleEditing = false
            focusedSubItemId = id
            isNewSubItemFocused = false
        }
    }
    
    private func startNewSubItem() {
        print("[PlannerItemView \(instanceId)] startNewSubItem() called")
        //First update focus manager state
        focusManager.updateFocusState(
            titleEditing: false,
            subItemId: nil,
            newSubItemFocused: true
        )
        
        // Batch the focus state updates in the next run loop
        DispatchQueue.main.async {
            self.isTitleEditing = false
            self.focusedSubItemId = nil
            self.isNewSubItemFocused = true
        }
    }
    
    private func saveEntireItem() {
        // Save the entire item with its current state
        print("[PlannerItemView \(instanceId)] saveEntireItem() called")
        viewModel.save()
    }
    
    func removeAllFocus() {
        print("[PlannerItemView \(instanceId)] Removing all focus")
        // Update local focus states
        isTitleEditing = false
        focusedSubItemId = nil
        isNewSubItemFocused = false
        shouldShowTextEditor = false
        
        // Update focus manager state
        focusManager.removeAllFocus()
        
        // Save any pending changes
        saveEntireItem()
    }
}

// Helper extension to find subviews of a specific type
extension UIView {
    func findSubviews<T: UIView>(ofType type: T.Type) -> [T] {
        var result = subviews.compactMap { $0 as? T }
        for subview in subviews {
            result.append(contentsOf: subview.findSubviews(ofType: type))
        }
        return result
    }
}

// Define a custom AnimatableModifier for height animation
struct ViewHeightModifier: ViewModifier, Animatable {
    var height: CGFloat
    var alignment: Alignment
    var opacity: Double
    
    var animatableData: CGFloat {
        get { height }
        set { height = newValue }
    }
    
    func body(content: Content) -> some View {
        content
            .frame(maxHeight: height > 0 ? .infinity : 0, alignment: alignment)
            .opacity(opacity)
            .scaleEffect(y: height, anchor: .top)
    }
}

// Define a custom transition modifier for SubItems to have different animations for expand/contract
struct SubItemsTransitionModifier: ViewModifier {
    @State private var animState: Bool = false
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Start animation after a brief delay to ensure proper animation
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.25)) {
                        animState = true
                    }
                }
            }
            .onDisappear {
                // Reset animation state when view disappears
                animState = false
            }
            .transition(
                // Use asymmetric transition for different animations when inserting vs removing
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity), // Top down for expansion
                    removal: .move(edge: .bottom).combined(with: .opacity)  // Bottom up for contraction
                )
            )
            .scaleEffect(y: animState ? 1 : 0.01, anchor: .top) // Start with minimal height from the top
            .opacity(animState ? 1 : 0)
    }
}

// Replace the extension with a simpler factory method
extension PlannerItemView {
    static func create(
        item: Models.ChecklistItem,
        focusCoordinator: PlannerFocusCoordinator,
        externalFocusState: Binding<UUID?>? = nil,
        onToggle: (() -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onLoseFocus: ((String) -> Void)? = nil,
        onReturn: (() -> Void)? = nil,
        onAddSubItem: ((String) -> Void)? = nil,
        onSubItemToggle: ((UUID) -> Void)? = nil,
        onSubItemTextChange: ((UUID, String) -> Void)? = nil,
        onNotificationChange: ((Date?) -> Void)? = nil,
        onGroupChange: ((UUID?) -> Void)? = nil
    ) -> PlannerItemView {
        return PlannerItemView(
            item: item,
            focusCoordinator: focusCoordinator,
            externalFocusState: externalFocusState,
            itemCallbacks: ItemCallbacks(
                onToggle: onToggle,
                onTextChange: onTextChange,
                onLoseFocus: onLoseFocus,
                onReturn: onReturn
            ),
            subItemCallbacks: SubItemCallbacks(
                onAddSubItem: onAddSubItem,
                onSubItemToggle: nil,  // No longer using the callback
                onSubItemTextChange: onSubItemTextChange
            ),
            metadataCallbacks: MetadataCallbacks(
                onNotificationChange: onNotificationChange,
                onGroupChange: onGroupChange
            )
        )
    }
}
