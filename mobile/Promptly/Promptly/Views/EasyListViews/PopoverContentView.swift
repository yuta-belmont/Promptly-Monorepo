import SwiftUI
import UIKit

struct PopoverContentView: View {
    // Item properties needed for display
    let itemId: UUID
    let itemDate: Date
    let itemNotification: Date?
    // Change from constant to state for UI updates
    @State private var currentGroupId: UUID?
    let isGroupDetailsView: Bool
    
    @Binding var isGroupSectionExpanded: Bool
    let onNotificationChange: ((Date?) -> Void)?
    let onGroupChange: ((UUID?) -> Void)?
    let onDelete: () -> Void
    let showDeleteOption: Bool
    @State private var isNotificationEnabled: Bool
    @State private var selectedTime: Date
    @State private var isTestSectionExpanded: Bool = false
    @State private var selectedOption: Int? = nil
    @ObservedObject private var groupStore = GroupStore.shared
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    @State private var deleteConfirmationActive = false
    @State private var deleteTimer: Timer?
    @Environment(\.dismiss) private var dismiss
    
    init(
        itemId: UUID,
        itemDate: Date,
        itemNotification: Date?,
        itemGroupId: UUID?,
        isGroupSectionExpanded: Binding<Bool>,
        onNotificationChange: ((Date?) -> Void)?,
        onGroupChange: ((UUID?) -> Void)? = nil,
        onDelete: @escaping () -> Void,
        showDeleteOption: Bool = true,
        isGroupDetailsView: Bool = false
    ) {
        self.itemId = itemId
        self.itemDate = itemDate
        self.itemNotification = itemNotification
        // Initialize the state variable with the initial value
        self._currentGroupId = State(initialValue: itemGroupId)
        self._isGroupSectionExpanded = isGroupSectionExpanded
        self.onNotificationChange = onNotificationChange
        self.onGroupChange = onGroupChange
        self.onDelete = onDelete
        self.showDeleteOption = showDeleteOption
        self.isGroupDetailsView = isGroupDetailsView
        _isNotificationEnabled = State(initialValue: itemNotification != nil)
        _selectedTime = State(initialValue: itemNotification ?? Date())
    }
    
    // Convenience initializer to create from PlannerItemDisplayData
    init(
        displayData: PlannerItemDisplayData,
        isGroupSectionExpanded: Binding<Bool>,
        onNotificationChange: ((Date?) -> Void)?,
        onGroupChange: ((UUID?) -> Void)? = nil,
        onDelete: @escaping () -> Void,
        showDeleteOption: Bool = true,
        isGroupDetailsView: Bool = false
    ) {
        self.init(
            itemId: displayData.id,
            itemDate: displayData.date,
            itemNotification: displayData.notification,
            itemGroupId: displayData.groupId,
            isGroupSectionExpanded: isGroupSectionExpanded,
            onNotificationChange: onNotificationChange,
            onGroupChange: onGroupChange,
            onDelete: onDelete,
            showDeleteOption: showDeleteOption,
            isGroupDetailsView: isGroupDetailsView
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Notify Row - Only toggle is interactive
            HStack {
                Image(systemName: "bell")
                    .frame(width: 24)
                Text("Notify")
                Spacer()
                Toggle("", isOn: $isNotificationEnabled)
                    .labelsHidden()
                    .onChange(of: isNotificationEnabled) { oldValue, newValue in
                        if newValue {
                            // Toggle turned ON - set notification with current time
                            let calendar = Calendar.current
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
                            var dateComponents = calendar.dateComponents([.year, .month, .day], from: itemDate)
                            dateComponents.hour = timeComponents.hour
                            dateComponents.minute = timeComponents.minute
                            
                            if let combinedDate = calendar.date(from: dateComponents) {
                                // This will update both the parent's local state and call the callback
                                // to inform EasyListViewModel of the change
                                onNotificationChange?(combinedDate)
                            }
                        } else {
                            // Toggle turned OFF - remove notification
                            // This will update both the parent's local state and call the callback
                            // to inform EasyListViewModel of the change
                            onNotificationChange?(nil)
                        }
                    }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Time Picker (shown when notification is enabled)
            if isNotificationEnabled {
                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .scaleEffect(0.6)
                    .colorScheme(.dark)
                    .frame(height: 100)
                    .padding(.horizontal, 0)
                    .onChange(of: selectedTime) { oldTime, newTime in
                        if isNotificationEnabled {
                            // Combine the selected time with the checklist date
                            let calendar = Calendar.current
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: newTime)
                            var dateComponents = calendar.dateComponents([.year, .month, .day], from: itemDate)
                            dateComponents.hour = timeComponents.hour
                            dateComponents.minute = timeComponents.minute
                            
                            if let combinedDate = calendar.date(from: dateComponents) {
                                // This will update both the parent's local state and call the callback
                                // to inform EasyListViewModel of the change
                                onNotificationChange?(combinedDate)
                            }
                        }
                    }
            }
            
            if !isGroupDetailsView {
                Divider()
                    .background(Color.white.opacity(0.2))
                
                // Group Row - Entire row is tappable
                Button(action: {
                    withAnimation(.linear(duration: 0.1)) {
                        isGroupSectionExpanded.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "folder")
                            .frame(width: 24)
                        Text("Group")
                        Spacer()
                        Image(systemName: isGroupSectionExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())  // Make entire area tappable
                }
                .buttonStyle(.plain)
                
                // Group Section (expanded)
                if isGroupSectionExpanded {
                    VStack(spacing: 0) {
                        // Existing Groups List
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(groupStore.groups) { group in
                                    Button(action: {
                                        // If already in this group, remove from group (toggle behavior)
                                        if currentGroupId == group.id {
                                            feedbackGenerator.impactOccurred()
                                            // Update local state first
                                            currentGroupId = nil
                                            // Then notify parent
                                            onGroupChange?(nil)
                                        } else {
                                            feedbackGenerator.impactOccurred()
                                            // Update local state first
                                            currentGroupId = group.id
                                            // Then notify parent
                                            onGroupChange?(group.id)
                                        }
                                         
                                    }) {
                                        HStack {
                                            // Check if this is the current group
                                            let isCurrentGroup = currentGroupId == group.id
                                            
                                            Image(systemName: isCurrentGroup ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(isCurrentGroup ? .green : .gray)
                                                .frame(width: 24)
                                                .padding(.leading, 12)
                                            
                                            Text(group.title)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                            
                                            Spacer()
                                        }
                                        .foregroundColor(.white)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Show a message if no groups exist
                                if groupStore.groups.isEmpty {
                                    VStack(spacing: 8) {
                                        Text("You have no groups.")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        
                                        Button(action: {
                                            // Close the current popover
                                            isGroupSectionExpanded = false
                                            
                                            // Dismiss the parent popover
                                            dismiss()
                                            
                                            // Show the ManageGroupsView
                                            NotificationCenter.default.post(
                                                name: NSNotification.Name("ShowManageGroupsView"),
                                                object: nil
                                            )
                                            
                                            // Provide haptic feedback
                                            feedbackGenerator.impactOccurred()
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "line.3.horizontal")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                Text("Manage groups")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                                    .underline()
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                        .frame(maxHeight: 150)  // Increased height since we removed the creation UI
                    }
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(8)
                    .padding(.horizontal, 4)
                }
            }

            // Delete option
            if showDeleteOption {
                Divider()
                Button(action: {
                    feedbackGenerator.impactOccurred()
                    
                    if deleteConfirmationActive {
                        // Second tap - perform delete
                        deleteTimer?.invalidate()
                        deleteTimer = nil
                        deleteConfirmationActive = false
                        dismiss()  // Dismiss the popover first
                        
                        // Call onDelete after a short delay to allow the popover to dismiss
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            onDelete()  // This will trigger the actual deletion
                        }
                    } else {
                        // First tap - start confirmation timer
                        deleteConfirmationActive = true
                        deleteTimer?.invalidate()
                        deleteTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                            deleteConfirmationActive = false
                        }

                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .frame(width: 24)
                        Text(deleteConfirmationActive ? "Confirm" : "Delete")
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(.red)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            // Prepare haptic feedback when view appears
            feedbackGenerator.prepare()
        }
        .onDisappear {
            // Clean up timer when view disappears
            deleteTimer?.invalidate()
            deleteTimer = nil
            deleteConfirmationActive = false
        }
    }
} 
