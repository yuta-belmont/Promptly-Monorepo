import SwiftUI

struct ItemDetailsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: ItemDetailsViewModel
    @State private var newSubitemText = ""
    @State private var showingPopover = false
    @State private var isGroupSectionExpanded = false
    @FocusState private var isSubitemFieldFocused: Bool
    @State private var isEditingTitle = false
    @State private var editedTitleText = ""
    @FocusState private var isTitleFieldFocused: Bool
    @State private var editingSubitemId: UUID? = nil {
        didSet {
            print("🔴 editingSubitemId didSet - setting focus to: \(editingSubitemId?.uuidString ?? "nil")")
            focusedSubitemId = editingSubitemId
        }
    }
    @State private var editedSubitemText = ""
    @FocusState private var focusedSubitemId: UUID? {
        didSet {
            print("⚪️ FocusState actually changed to: \(focusedSubitemId?.uuidString ?? "nil")")
        }
    }
    // State for drag and drop functionality
    @State private var draggedItem: Models.SubItem?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    init(item: Models.ChecklistItem, isPresented: Binding<Bool>) {
        self._isPresented = isPresented
        self._viewModel = StateObject(wrappedValue: ItemDetailsViewModel(item: item))
    }
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with controls
                HStack(alignment: .center, spacing: 8) {
                    // Checkbox for completion status
                    Button(action: {
                        feedbackGenerator.impactOccurred()
                        viewModel.toggleCompleted()
                    }) {
                        Image(systemName: viewModel.item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(viewModel.item.isCompleted ? .green : .gray)
                            .font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    
                    // Metadata in the middle (metadata row component reused)
                    MetadataRowCompact(item: viewModel.item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("metadata-\(viewModel.item.id)-\(viewModel.item.groupId?.uuidString ?? "none")-\(viewModel.item.notification?.timeIntervalSince1970 ?? 0)-\(viewModel.item.isCompleted)")
                        .animation(.easeInOut, value: viewModel.item.isCompleted)
                    
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
                    
                    // Close (X) button
                    Button(action: {
                        // Use animation to ensure smooth transition back to EasyListView
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
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 4)
                
                // Item title below header
                ZStack {
                    if isEditingTitle {
                        // Editable title field
                        TextEditor(text: $editedTitleText)
                            .font(.title3)
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal)
                            // Estimate height for a single line of text plus padding
                            .frame(height: 48)
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
                                
                                NewSubItemRow(
                                    text: $newSubitemText,
                                    isFocused: $isSubitemFieldFocused,
                                    onSubmit: {
                                        if !newSubitemText.isEmpty {
                                            viewModel.addSubitem(newSubitemText)
                                            newSubitemText = ""
                                            isSubitemFieldFocused = true
                                        }
                                    }
                                )
                                .id("newSubItemRow")
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets())
                                
                                Color.clear.frame(height: 44)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets())
                                    .listRowSeparator(.hidden)
                            }
                            .listStyle(.plain)
                            .environment(\.defaultMinListRowHeight, 0)
                            .scrollContentBackground(.hidden)
                            .frame(height: geometry.size.height * 0.7)
                            .onChange(of: newSubitemText) { _, newValue in
                                if newValue.contains("\n") {
                                    newSubitemText = newValue.replacingOccurrences(of: "\n", with: "")
                                    if !newSubitemText.isEmpty {
                                        viewModel.addSubitem(newSubitemText)
                                        newSubitemText = ""
                                        isSubitemFieldFocused = true
                                    }
                                }
                            }
                        }
                    }
                }
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
        }
        .onAppear {
            viewModel.loadDetails()
            feedbackGenerator.prepare()
            
            // Debug current item state
            print("ItemDetailsView appeared with item ID: \(viewModel.item.id)")
            print("Item has \(viewModel.item.subItems.count) subitems")
            print("Subitem IDs: \(viewModel.item.subItems.map { $0.id })")
            print("Subitem titles: \(viewModel.item.subItems.map { $0.title })")
            
            // Debug scroll view bounds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("Item still has \(viewModel.item.subItems.count) subitems after delay")
            }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewChecklistAvailable"))) { notification in
            if let notificationDate = notification.object as? Date,
               Calendar.current.isDate(notificationDate, inSameDayAs: viewModel.item.date) {
                viewModel.loadDetails()
            }
        }
        .onChange(of: isTitleFieldFocused) { _, newValue in
            if !newValue && isEditingTitle {
                saveTitle()
            }
        }
        .onChange(of: focusedSubitemId) { oldValue, newValue in
            print("🟤 Focus onChange: \(oldValue?.uuidString ?? "nil") -> \(newValue?.uuidString ?? "nil")")
            if newValue == nil && editingSubitemId != nil {
                saveSubitemEdit()
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
        print("🟡 startEditingSubitem called")
        editingSubitemId = subitem.id
        editedSubitemText = subitem.title
        print("🟡 editingSubitemId set to: \(subitem.id)")
    }
    
    private func saveSubitemEdit() {
        guard let subitemId = editingSubitemId,
              !editedSubitemText.isEmpty else { return }
        if editedSubitemText != viewModel.item.subItems.first(where: { $0.id == subitemId })?.title {
            viewModel.updateSubitemTitle(subitemId, newTitle: editedSubitemText)
        }
        self.editingSubitemId = nil
    }
}

// Add SubItemView definition
private struct SubItemView: View {
    let subitem: Models.SubItem
    let onToggle: () -> Void
    let onTap: () -> Void
    @Binding var editingSubitemId: UUID?
    @Binding var editedSubitemText: String
    @FocusState.Binding var focusedSubitemId: UUID?
    let onSave: (String) -> Void
    @State private var isPreloading = false
    
    var body: some View {
        let _ = print("📋 SubItemView body called for id: \(subitem.id), isEditing: \(editingSubitemId == subitem.id)")
        
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: subitem.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subitem.isCompleted ? .green : .gray)
                    .font(.system(size: 20))
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
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            print("🔵 Text tapped, setting isPreloading = true")
                            isPreloading = true
                            DispatchQueue.main.async {
                                print("🔵 Async: setting isPreloading = false and calling onTap")
                                isPreloading = false
                                onTap()
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
                        .opacity(isPreloading ? 0 : 1)
                        .onChange(of: isPreloading) { oldValue, newValue in
                            print("🟢 TextEditor isPreloading changed: \(oldValue) -> \(newValue)")
                            if !newValue {
                                print("🟢 TextEditor should now be visible")
                            }
                        }
                        .onAppear {
                            print("🟣 TextEditor appeared, isPreloading: \(isPreloading), focused: \(focusedSubitemId == subitem.id), id: \(subitem.id)")
                        }
                        .onDisappear {
                            print("⚫️ TextEditor disappeared for id: \(subitem.id)")
                        }
                        .task {
                            print("🎯 TextEditor task started for id: \(subitem.id)")
                        }
                        .onChange(of: focusedSubitemId) { oldValue, newValue in
                            print("🔮 TextEditor focus changed: \(oldValue?.uuidString ?? "nil") -> \(newValue?.uuidString ?? "nil"), id: \(subitem.id)")
                        }
                }
            }
        }
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// Add NewSubItemRow component before SubItemView
private struct NewSubItemRow: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "circle")
                .foregroundColor(isFocused.wrappedValue ? .gray : .gray.opacity(0))
                .font(.system(size: 20))
                .transition(.opacity)
            
            TextEditor(text: $text)
                .font(.body)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused(isFocused)
                .border(.purple, width: 0.5)
                .overlay(
                    Text(text.isEmpty ? "Add subitem..." : "")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.leading, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .border(.yellow, width: 0.5),
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
