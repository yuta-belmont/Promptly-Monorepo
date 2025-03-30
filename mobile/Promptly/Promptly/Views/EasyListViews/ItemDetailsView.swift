import SwiftUI

struct ItemDetailsView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel: ItemDetailsViewModel
    @State private var newSubitemText = ""
    @State private var showingPopover = false
    @State private var isGroupSectionExpanded = false
    @FocusState private var isSubitemFieldFocused: Bool
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
                Text(viewModel.item.title)
                    .font(.title3)
                    .foregroundColor(.white)
                    .lineLimit(4)
                    .strikethrough(viewModel.item.isCompleted, color: .gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                // Divider between header section and content
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal)
                
                // Main item details
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Subitems section - only show if there are subitems or we want to add one
                        VStack(alignment: .leading, spacing: 16) {
                            if !viewModel.item.subItems.isEmpty {
                                // List of subitems
                                VStack(alignment: .leading, spacing: 16) {
                                    ForEach(viewModel.item.subItems) { subitem in
                                        HStack(alignment: .top, spacing: 12) {
                                            // Subitem status indicator with toggle functionality
                                            Button(action: {
                                                feedbackGenerator.impactOccurred()
                                                viewModel.toggleSubitemCompleted(subitemId: subitem.id)
                                            }) {
                                                Image(systemName: subitem.isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(subitem.isCompleted ? .green : .gray)
                                                    .font(.system(size: 20))
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // Subitem title
                                            Text(subitem.title)
                                                .font(.body)
                                                .foregroundColor(.white)
                                                .lineLimit(3)
                                                .strikethrough(subitem.isCompleted, color: .gray)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                            
                            // Add subitem field
                            HStack(alignment: .top, spacing: 12) {
                                // Empty circle for new subitem (only visible when focused)
                                if isSubitemFieldFocused {
                                    Image(systemName: "circle")
                                        .foregroundColor(.gray)
                                        .font(.system(size: 20))
                                        .transition(.opacity)
                                } else {
                                    // Placeholder with same width to maintain alignment
                                    Color.clear
                                        .frame(width: 20, height: 20)
                                        .transition(.opacity)
                                }
                                
                                // Text field for new subitem
                                TextField("Add subitem...", text: $newSubitemText)
                                    .font(.body)
                                    .foregroundColor(.white)
                                    .submitLabel(.done)
                                    .focused($isSubitemFieldFocused)
                                    .onSubmit {
                                        if !newSubitemText.isEmpty {
                                            viewModel.addSubitem(newSubitemText)
                                            newSubitemText = ""
                                            // Keep focus for adding multiple items
                                            isSubitemFieldFocused = true
                                        }
                                    }
                            }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .animation(.easeInOut(duration: 0.2), value: isSubitemFieldFocused)
                        }
                    }
                    .padding(.bottom, 20)
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
        }
        .onDisappear {
            viewModel.saveChanges()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewChecklistAvailable"))) { notification in
            if let notificationDate = notification.object as? Date,
               Calendar.current.isDate(notificationDate, inSameDayAs: viewModel.item.date) {
                viewModel.loadDetails()
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
