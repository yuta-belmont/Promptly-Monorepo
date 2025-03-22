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
        print("PlannerFocusManager: updateFocusState called")
        print("PlannerFocusManager: titleEditing: \(titleEditing), subItemId: \(String(describing: subItemId)), newSubItemFocused: \(newSubItemFocused)")
        print("PlannerFocusManager: Before - isTitleEditing: \(isTitleEditing), focusedSubItemId: \(String(describing: focusedSubItemId)), isNewSubItemFocused: \(isNewSubItemFocused)")
        
        self.isTitleEditing = titleEditing
        self.focusedSubItemId = subItemId
        self.isNewSubItemFocused = newSubItemFocused
        
        print("PlannerFocusManager: After - isTitleEditing: \(isTitleEditing), focusedSubItemId: \(String(describing: focusedSubItemId)), isNewSubItemFocused: \(isNewSubItemFocused)")
    }
}

// Break callbacks into smaller, focused structures
struct ItemCallbacks {
    let onToggle: (() -> Void)?
    let onTextChange: ((String) -> Void)?
    let onLoseFocus: ((String) -> Void)?
    let onReturn: (() -> Void)?
    
    init(
        onToggle: (() -> Void)? = nil,
        onTextChange: ((String) -> Void)? = nil,
        onLoseFocus: ((String) -> Void)? = nil,
        onReturn: (() -> Void)? = nil
    ) {
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onLoseFocus = onLoseFocus
        self.onReturn = onReturn
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
    @FocusState var isTitleEditing: Bool
    let focusTitle: () -> Void
    let focusNewSubItem: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Checkbox button
            Button(action: {
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
                isTitleEditing: _isTitleEditing,
                itemCallbacks: itemCallbacks,
                focusManager: focusManager,
                focusTitle: focusTitle
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
    }
}

// Text input area component
private struct ItemTextInputArea: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    @Binding var shouldShowTextEditor: Bool
    @FocusState var isTitleEditing: Bool
    let itemCallbacks: ItemCallbacks
    let focusManager: PlannerFocusManager
    let focusTitle: () -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if shouldShowTextEditor {
                TextEditor(text: $viewModel.text)
                    .focused($isTitleEditing)
                    .onChange(of: viewModel.text) { oldValue, newValue in
                        if newValue.contains("\n") {
                            viewModel.text = newValue.replacingOccurrences(of: "\n", with: "")
                            itemCallbacks.onReturn?()
                        } else {
                            itemCallbacks.onTextChange?(newValue)
                        }
                    }
                    .submitLabel(.next)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.vertical, 8)
                    .strikethrough(viewModel.item.isCompleted, color: .gray)
                    .opacity(viewModel.item.isCompleted ? 0.7 : 1.0)
            } else {
                Text(viewModel.text.isEmpty ? "Enter task here..." : viewModel.text)
                    .foregroundColor(viewModel.text.isEmpty ? .gray : .white)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .strikethrough(viewModel.item.isCompleted, color: .gray)
                    .opacity(viewModel.item.isCompleted ? 0.7 : 1.0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
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
    
    var body: some View {
        Button(action: {
            let isAddingFirstSubItem = viewModel.item.subItems.isEmpty && !viewModel.areSubItemsExpanded
            
            // 1. Update data state
            viewModel.areSubItemsExpanded.toggle()
            
            // 2. Set focus if needed
            if isAddingFirstSubItem {
                print("ExpandButton: Calling focusNewSubItem")
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
        let hasNotification = !viewModel.item.isCompleted && viewModel.item.notification != nil
        let hasGroup = viewModel.hasValidGroup()
        
        if hasNotification || hasGroup {
            HStack(spacing: 8) {
                Spacer()
                    .frame(width: 30)
                
                if let groupTitle = viewModel.getGroupTitle() {
                    Text(groupTitle)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                if let notificationTime = viewModel.item.notification, !viewModel.item.isCompleted {
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
            .padding(.leading, 2)
            .padding(.top, -4)
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
    let onStartEdit: () -> Void
    @State private var localText: String
    @State private var lastTapTime: Date? = nil

    init(viewModel: PlannerItemViewModel, subItem: Models.SubItem, onReturn: @escaping (UUID) -> Void, focusedSubItemId: FocusState<UUID?>.Binding, onStartEdit: @escaping () -> Void) {
        self.viewModel = viewModel
        self.subItem = subItem
        self.onReturn = onReturn
        self._focusedSubItemId = focusedSubItemId
        self.onStartEdit = onStartEdit
        self._localText = State(initialValue: subItem.title)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Direct toggle using viewModel only
            Button(action: {
                let now = Date()
                print("\n=== TAP DETAILS ===")
                print("Tap detected on subitem \(subItem.id)")
                print("Current time: \(now)")
                if let last = lastTapTime {
                    print("Time since last tap: \(now.timeIntervalSince(last)) seconds")
                } else {
                    print("First tap detected")
                }
                print("=== TAP DETAILS END ===\n")
                
                lastTapTime = now
                print("SubItemRowView: Direct toggle of subitem \(subItem.id)")
                viewModel.toggleSubItem(subItem.id)
            }) {
                Image(systemName: subItem.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subItem.isCompleted ? .green : .gray)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            CustomTextField(
                text: $localText,
                textColor: .white,
                onReturn: { onReturn(subItem.id) },
                onTextChange: { newText in
                    localText = newText
                    viewModel.updateSubItemText(subItem.id, newText: newText)
                }
            )
            .focused($focusedSubItemId, equals: subItem.id)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if focusedSubItemId != subItem.id {
                        onStartEdit()
                    }
                }
            )
            .strikethrough(subItem.isCompleted, color: .gray)
            .opacity(subItem.isCompleted ? 0.7 : 1.0)
        }
        .padding(.leading, 32)
        .frame(height: 30)  // Reduced from 44 to 30
    }
}

// Subitem list component
private struct SubItemListView: View {
    @ObservedObject var viewModel: PlannerItemViewModel
    let onSubItemReturn: (UUID) -> Void
    @FocusState.Binding var focusedSubItemId: UUID?
    let onStartEdit: (UUID) -> Void
    
    var body: some View {
        ForEach(viewModel.item.subItems, id: \.id) { subItem in
            SubItemRowView(
                viewModel: viewModel,
                subItem: subItem,
                onReturn: onSubItemReturn,
                focusedSubItemId: $focusedSubItemId,
                onStartEdit: { onStartEdit(subItem.id) }
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
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .foregroundColor(.gray)
                .font(.system(size: 16))
            
            CustomTextField(
                text: $viewModel.newSubItemText,
                textColor: isNewSubItemFocused ? .white : .gray,
                placeholder: "Add subitem...",
                placeholderColor: .gray,
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
        }
        .padding(.leading, 32)
        .padding(.vertical, 8)
    }
    
    private func handleAddSubItem() {
        if !viewModel.newSubItemText.isEmpty {
            let textToAdd = viewModel.newSubItemText
            viewModel.addSubItem(textToAdd)
            viewModel.newSubItemText = ""
            onSubmit()
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
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    SubItemListView(
                        viewModel: viewModel,
                        onSubItemReturn: handleSubItemReturn,
                        focusedSubItemId: $focusedSubItemId,
                        onStartEdit: { subItemId in
                            onStartEditSubItem(subItemId)
                        }
                    )
                    
                    NewSubItemView(
                        viewModel: viewModel,
                        onSubmit: onStartNewSubItem,
                        isNewSubItemFocused: $isNewSubItemFocused
                    )
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
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
        } else {
            onStartNewSubItem()
        }
    }
}

// Update PlannerItemView to include metadataCallbacks in MainItemRow
struct PlannerItemView: View {
    @StateObject private var viewModel: PlannerItemViewModel
    @StateObject private var focusManager = PlannerFocusManager()
    @EnvironmentObject private var appFocusManager: FocusManager
    
    @FocusState private var isTitleEditing: Bool
    @FocusState private var focusedSubItemId: UUID?
    @FocusState private var isNewSubItemFocused: Bool
    
    let externalFocusState: FocusState<UUID?>.Binding?
    let itemId: UUID
    
    @State private var shouldShowTextEditor: Bool = false
    
    let itemCallbacks: ItemCallbacks
    let subItemCallbacks: SubItemCallbacks
    let metadataCallbacks: MetadataCallbacks
    
    init(
        item: Models.ChecklistItem,
        externalFocusState: FocusState<UUID?>.Binding?,
        itemCallbacks: ItemCallbacks,
        subItemCallbacks: SubItemCallbacks,
        metadataCallbacks: MetadataCallbacks
    ) {
        print("PlannerItemView: Initializing with item \(item.id)")
        print("PlannerItemView: Item has \(item.subItems.count) subitems")
        print("PlannerItemView: Subitems completion states: \(item.subItems.map { "\($0.id): \($0.isCompleted)" }.joined(separator: ", "))")
        self._viewModel = StateObject(wrappedValue: PlannerItemViewModel(item: item))
        self.itemId = item.id
        self.externalFocusState = externalFocusState
        self.itemCallbacks = itemCallbacks
        self.subItemCallbacks = subItemCallbacks
        self.metadataCallbacks = metadataCallbacks
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MainItemRow(
                viewModel: viewModel,
                focusManager: focusManager,
                itemCallbacks: itemCallbacks,
                metadataCallbacks: metadataCallbacks,
                shouldShowTextEditor: $shouldShowTextEditor,
                isTitleEditing: _isTitleEditing,
                focusTitle: focusTitle,
                focusNewSubItem: { startNewSubItem() }
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
                    .fill(Color.white.opacity(0.07))
                
                if viewModel.isDeleting {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.red.opacity(0.95 * viewModel.opacity))
                } else if let color = viewModel.groupColor {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.25))
                }
            }
        )
        .opacity(viewModel.opacity)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        
        // One-way focus management
        .onChange(of: isTitleEditing) { oldValue, newValue in
            focusManager.updateFocusState(
                titleEditing: newValue,
                subItemId: focusedSubItemId,
                newSubItemFocused: isNewSubItemFocused
            )
            if !newValue && oldValue {
                itemCallbacks.onLoseFocus?(viewModel.text)
                saveEntireItem()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    shouldShowTextEditor = false
                }
            }
        }
        .onChange(of: focusedSubItemId) { oldValue, newValue in
            print("PlannerItemView: focusedSubItemId changed - old: \(String(describing: oldValue)), new: \(String(describing: newValue))")
            focusManager.updateFocusState(
                titleEditing: isTitleEditing,
                subItemId: newValue,
                newSubItemFocused: isNewSubItemFocused
            )
            if oldValue != nil && newValue == nil {
                saveEntireItem()
            }
        }
        .onChange(of: isNewSubItemFocused) { oldValue, newValue in
            focusManager.updateFocusState(
                titleEditing: isTitleEditing,
                subItemId: focusedSubItemId,
                newSubItemFocused: newValue
            )
            if oldValue && !newValue {
                saveEntireItem()
            }
        }
        .onChange(of: externalFocusState?.wrappedValue) { _, newValue in
            if newValue == itemId && !isTitleEditing {
                focusTitle()
            }
        }
        .onChange(of: focusManager.hasAnyFocus) { _, isEditing in
            if !isEditing {
                // Save when we lose focus on any editable field
                saveEntireItem()
            }
        }
        .onAppear {
            shouldShowTextEditor = isTitleEditing
        }
    }
    
    // Focus methods that directly set @FocusState
    func focusTitle() {
        isTitleEditing = true
        focusedSubItemId = nil
        isNewSubItemFocused = false
        shouldShowTextEditor = true
        if let externalFocusState = externalFocusState {
            externalFocusState.wrappedValue = itemId
        }
    }
    
    private func startEditingSubItem(_ id: UUID) {
        print("PlannerItemView: startEditingSubItem called with id: \(id)")
        print("PlannerItemView: Before - isTitleEditing: \(isTitleEditing), focusedSubItemId: \(String(describing: focusedSubItemId)), isNewSubItemFocused: \(isNewSubItemFocused)")
        
        isTitleEditing = false
        focusedSubItemId = id
        isNewSubItemFocused = false
        
        focusManager.updateFocusState(
            titleEditing: false,
            subItemId: id,
            newSubItemFocused: false
        )
        
        print("PlannerItemView: After - isTitleEditing: \(isTitleEditing), focusedSubItemId: \(String(describing: focusedSubItemId)), isNewSubItemFocused: \(isNewSubItemFocused)")
    }
    
    private func startNewSubItem() {
        isTitleEditing = false
        focusedSubItemId = nil
        isNewSubItemFocused = true
        focusManager.updateFocusState(
            titleEditing: false,
            subItemId: nil,
            newSubItemFocused: true
        )
    }
    
    private func saveEntireItem() {
        // Save the entire item with its current state
        viewModel.save()
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

// SwipeAction implementation
struct SwipeAction<Content: View>: View {
    @ViewBuilder let content: Content
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwiped: Bool = false
    
    // Swipe threshold
    private let threshold: CGFloat = 80
    
    var body: some View {
        ZStack {
            // Background layer with delete button (only visible when swiped)
            HStack(spacing: 0) {
                Spacer()
                
                // Delete button appears only when swiped
                // The width is calculated based on how far the user has swiped
                if offset < 0 || isSwiped {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .frame(width: min(abs(offset), threshold), height: nil)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .opacity(min(abs(offset) / threshold, 1.0)) // Gradually increase opacity as user swipes
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                // Return to non-swiped state
                                offset = 0
                                isSwiped = false
                                
                                // Execute the delete with a small delay to allow animation to complete
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onDelete()
                                }
                            }
                        }
                }
            }
            
            // Content layer that can be swiped
            content
                .background(Color.white.opacity(0.001)) // Nearly invisible background to help with gestures
                .offset(x: offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Allow only left swipe (negative values), clamp to prevent rightward movement
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0)) {
                                // Restrict to negative or zero values only, never positive (rightward)
                                offset = min(0, value.translation.width) // Prevent rightward dragging
                            }
                        }
                        .onEnded { value in
                            // Check if swipe is past threshold
                            let swipedLeft = value.translation.width < -threshold/2
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if swipedLeft {
                                    offset = -threshold
                                    isSwiped = true
                                } else {
                                    offset = 0
                                    isSwiped = false
                                }
                            }
                        }
                )
        }
        // Reset offset when tapped outside the swipe area
        .onTapGesture {
            if isSwiped {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset = 0
                    isSwiped = false
                }
            }
        }
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
        externalFocusState: FocusState<UUID?>.Binding? = nil,
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
        print("PlannerItemView.create: Creating view for item \(item.id)")
        
        return PlannerItemView(
            item: item,
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
