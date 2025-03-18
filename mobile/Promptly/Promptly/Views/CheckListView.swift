import SwiftUI

// MARK: - Helper Types

struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Header Component

struct CheckListHeader: View {
    let isEditing: Bool
    let hasUnsavedChanges: Bool
    let isKeyboardActive: Bool
    let onEdit: () -> Void
    let onImportCalendar: () async -> Void
    let onImportYesterday: () async -> Void
    let onImportFromDate: (Date) async -> Void
    let onDiscard: () -> Void
    let onSave: () -> Void
    @Binding var showingDiscardAlert: Bool
    @Binding var showingImportYesterdayConfirmation: Bool
    @Binding var showingImportYesterdayOptions: Bool
    @Binding var showingImportDateConfirmation: Bool
    @Binding var showingImportDateOptions: Bool
    @Binding var selectedImportDate: Date
    let onConfirmImport: () async -> Void
    let onOverwriteImport: () async -> Void
    let onConfirmDateImport: () async -> Void
    let onOverwriteDateImport: () async -> Void
    
    @State private var showingDatePicker = false
    
    // Haptic feedback generator
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        HStack(alignment: .center) {
            Button(action: {
                // No haptic feedback for edit/save button
                if isEditing {
                    onSave()
                } else {
                    // Enter edit mode
                    onEdit()
                }
            }) {
                Text(isEditing ? "Save" : "Edit")
            }
            .padding(.horizontal, 8)
            .buttonStyle(.plain)
            
            Spacer()
            
            if isEditing {
                Button(action: { 
                    showingDatePicker = true
                }) {
                    HStack(spacing: 4) {
                        Text("import from")
                            .font(.caption)
                            .fontWeight(.regular)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.blue.opacity(0.2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .help("Select a date to import items from")
                .popover(isPresented: $showingDatePicker) {
                    ZStack {
                        // Semi-transparent background
                        Color.black.opacity(0.001) // Nearly invisible color to allow touches
                            .background(.ultraThinMaterial)
                            .ignoresSafeArea()
                        
                        VStack(spacing: 10) {
                            Text("Select a Date")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top)
                            
                            DatePicker(
                                "Select Date",
                                selection: $selectedImportDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding()
                            
                            Button("import from this date") {
                                showingDatePicker = false
                                Task {
                                    await onImportFromDate(selectedImportDate)
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Color.blue.opacity(0.2)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(10)
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            .padding(.bottom)
                        }
                        .padding()
                    }
                }
                .confirmationDialog(
                    "Import from selected date?",
                    isPresented: $showingImportDateConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Import") {
                        Task {
                            await onConfirmDateImport()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog(
                    "Import from selected date?",
                    isPresented: $showingImportDateOptions,
                    titleVisibility: .visible
                ) {
                    Button("Overwrite current items") {
                        Task {
                            await onOverwriteDateImport()
                        }
                    }
                    Button("Append to current items") {
                        Task {
                            await onConfirmDateImport()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Choose how to import items from the selected date")
                }
                
                Button(action: { 
                    Task { 
                        await onImportYesterday() 
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("import yesterday")
                            .font(.caption2)
                            .fontWeight(.regular)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Color.blue.opacity(0.2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .help("Import items from yesterday")
                .confirmationDialog(
                    "Import from yesterday?",
                    isPresented: $showingImportYesterdayConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Import") {
                        Task {
                            await onConfirmImport()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog(
                    "Import from yesterday?",
                    isPresented: $showingImportYesterdayOptions,
                    titleVisibility: .visible
                ) {
                    Button("Overwrite current items") {
                        Task {
                            await onOverwriteImport()
                        }
                    }
                    Button("Append to current items") {
                        Task {
                            await onConfirmImport()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Choose how to import items from yesterday")
                }
                
                Button(action: { 
                    // Only show the confirmation dialog if there are changes to discard
                    if hasUnsavedChanges {
                        showingDiscardAlert = true
                    } else {
                        // If no changes, just exit edit mode directly
                        onDiscard()
                    }
                }) {
                    Image(systemName: "xmark.circle")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 8)
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .confirmationDialog(
                    "Discard changes?",
                    isPresented: $showingDiscardAlert,
                    titleVisibility: .visible
                ) {
                    Button("Yes", role: .destructive, action: onDiscard)
                    Button("No", role: .cancel) {}
                }
            }
        }
        .onAppear {
            // Prepare the feedback generator when the view appears
            feedbackGenerator.prepare()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .headerBackground()
        .cornerRadius(16, corners: [.topLeft, .topRight])
    }
}

// MARK: - Footer Component

struct CheckListFooter: View {
    let completedCount: Int
    let totalCount: Int
    @Binding var isDragging: Bool

    var body: some View {
        ZStack {
            // Left side content
            HStack {
                Text("\(completedCount)/\(totalCount) completed")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.ultraThinMaterial.opacity(0.9))
                    )
                Spacer()
            }
            
            // Right side content
            HStack {
                Spacer()
                if totalCount > 0 {
                    ProgressView(value: Double(completedCount), total: Double(totalCount))
                        .progressViewStyle(LinearProgressViewStyle(tint: .green))
                        .frame(width: 80)
                }
            }
        }
        .padding(.bottom, 5)
        .padding(.top, 2)
        .padding(.horizontal, 32)
        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
        .ignoresSafeArea(.all, edges: .bottom)
    }
}

// MARK: - New Item Input Component

struct NewItemInput: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    let onSubmit: () -> Void
    let shouldFocus: Bool

    var body: some View {
        HStack {
            Image(systemName: "circle")
                .foregroundColor(.gray)
            TextField("New item", text: $text)
                .submitLabel(.next)
                .focused($isFocused)
                .onSubmit {
                    let currentText = text
                    if !currentText.isEmpty {
                        onSubmit()
                        isFocused = true
                    }
                }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 28)
        .onChange(of: shouldFocus) { newValue in
            if newValue {
                isFocused = true
            }
        }
    }
}

// MARK: - Checklist Item Component

struct ChecklistItemView: View {
    let item: ChecklistItem
    let isEditing: Bool
    let isEditingThis: Bool
    @Binding var editedTitle: String
    @Binding var editedNotification: Date?
    let onToggle: () -> Void
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onPartialSave: () -> Void
    let onDelete: () -> Void
    let checklistDate: Date
    @FocusState private var isTitleFocused: Bool
    @State private var showingDeleteAlert = false
    
    // Haptic feedback generator for item toggling
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    
    init(item: ChecklistItem, isEditing: Bool, isEditingThis: Bool, editedTitle: Binding<String>,
         editedNotification: Binding<Date?>,
         onToggle: @escaping () -> Void, onStartEdit: @escaping () -> Void,
         onSaveEdit: @escaping () -> Void, onPartialSave: @escaping () -> Void,
         onDelete: @escaping () -> Void, checklistDate: Date) {
        self.item = item
        self.isEditing = isEditing
        self.isEditingThis = isEditingThis
        self._editedTitle = editedTitle
        self._editedNotification = editedNotification
        self.onToggle = onToggle
        self.onStartEdit = onStartEdit
        self.onSaveEdit = onSaveEdit
        self.onPartialSave = onPartialSave
        self.onDelete = onDelete
        self.checklistDate = checklistDate
    }

    var body: some View {
        Group {
            if isEditingThis {
                expandedView
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.8)),
                        removal: .scale(scale: 0.95).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.8))
                    ))
            } else {
                collapsedView
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.05).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.8)),
                        removal: .scale(scale: 1.05).combined(with: .opacity).animation(.spring(response: 0.3, dampingFraction: 0.8))
                    ))
            }
        }
        .onAppear {
            // Prepare the feedback generator when the view appears
            feedbackGenerator.prepare()
        }
    }
    
    private var expandedView: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation {
                        onPartialSave() // Save before closing
                        onSaveEdit() // This will close the expanded view
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal)
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.vertical, 8)
            
            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $editedTitle)
                    .submitLabel(.next)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isTitleFocused)
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable Notification", isOn: Binding(
                        get: { editedNotification != nil },
                        set: { if !$0 { 
                            // When turning off notifications, set to nil and save immediately
                            editedNotification = nil 
                            onPartialSave()
                        } else if editedNotification == nil { 
                            // Create a notification for the current time on the checklist date
                            let calendar = Calendar.current
                            let now = Date()
                            let timeComponents = calendar.dateComponents([.hour, .minute], from: now)
                            var dateComponents = calendar.dateComponents([.year, .month, .day], from: checklistDate)
                            dateComponents.hour = timeComponents.hour
                            dateComponents.minute = timeComponents.minute
                            
                            if let combinedDate = calendar.date(from: dateComponents) {
                                editedNotification = combinedDate
                                onPartialSave()
                            }
                        }}
                    ))
                    .foregroundColor(.white.opacity(0.8))
                    
                    if editedNotification != nil {
                        DatePicker(
                            "Notify at",
                            selection: Binding(
                                get: { editedNotification ?? Date() },
                                set: { 
                                    // Preserve the date part from the checklist date
                                    // and only use the time part from the selected date
                                    let calendar = Calendar.current
                                    let selectedComponents = calendar.dateComponents([.hour, .minute], from: $0)
                                    var dateComponents = calendar.dateComponents([.year, .month, .day], from: checklistDate)
                                    dateComponents.hour = selectedComponents.hour
                                    dateComponents.minute = selectedComponents.minute
                                    
                                    if let combinedDate = calendar.date(from: dateComponents) {
                                        editedNotification = combinedDate
                                        onPartialSave()
                                    }
                                }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            .onAppear { 
                isTitleFocused = true 
            }
            .onChange(of: isEditingThis) { newValue in
                if newValue {
                    isTitleFocused = true
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.3))
                .padding(.horizontal)
        }
        .onDisappear {
            // Always save when the expanded view is dismissed
            onPartialSave()
        }
        .onChange(of: isEditingThis) { isEditing in
            if !isEditing {
                // Save when transitioning from editing to non-editing
                onPartialSave()
            }
        }
    }
    
    private var collapsedView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                if isEditing {
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 20))
                            .frame(width: 44, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale)
                } else {
                    // Only show the checkbox when not in edit mode
                    Button(action: {
                        // Trigger haptic feedback when toggling item completion
                        feedbackGenerator.impactOccurred()
                        onToggle()
                    }) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.isCompleted ? .green : .gray)
                            .font(.system(size: 22))
                    }
                    .buttonStyle(.plain)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .strikethrough(item.isCompleted, color: .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if let notification = item.notification, !item.isCompleted {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundColor(notification < Date() ? .red.opacity(0.7) : .white.opacity(0.5))
                            Text(notification, style: .time)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .onTapGesture {
                    if isEditing {
                        onStartEdit()
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .background(Color.clear)
        .confirmationDialog(
            "Delete this item?",
            isPresented: $showingDeleteAlert,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - List Content Component

struct CheckListContent: View {
    @ObservedObject var viewModel: ChecklistViewModel
    @ObservedObject var viewState: ChecklistViewState
    @Binding var shouldFocusNewItem: Bool
    
    var body: some View {
        ForEach(viewModel.items) { item in
            ChecklistItemView(
                item: item,
                isEditing: viewState.isEditing,
                isEditingThis: viewState.editingItem?.id == item.id,
                editedTitle: viewState.editingItem?.id == item.id ? $viewState.editedTitle : .constant(""),
                editedNotification: viewState.editingItem?.id == item.id ? $viewState.editedNotification : .constant(nil),
                onToggle: { viewState.toggleItem(item) },
                onStartEdit: { 
                    // Save the current item before switching to a new one
                    if viewState.editingItem != nil {
                        viewState.saveEditWithoutClosing()
                    }
                    viewState.startEditing(item)
                },
                onSaveEdit: {
                    viewState.saveEdit()
                },
                onPartialSave: { viewState.saveEditWithoutClosing() },
                onDelete: {
                    withAnimation {
                        viewState.deleteItems(at: IndexSet([viewModel.items.firstIndex(of: item)!]))
                    }
                },
                checklistDate: viewState.checklistDate
            )
        }
        .onMove { from, to in
            withAnimation {
                viewModel.moveItems(from: from, to: to)
            }
        }
        
        if viewState.isEditing {
            NewItemInput(
                text: $viewState.newItemText,
                onSubmit: {
                    viewState.addNewItem()
                    shouldFocusNewItem = true
                },
                shouldFocus: shouldFocusNewItem
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        
        if !viewState.isEditing {
            Color.clear.frame(height: 44)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        }
    }
}

// MARK: - Main CheckList View

struct CheckListView: View {
    @ObservedObject var viewModel: ChecklistViewModel
    @StateObject private var viewState: ChecklistViewState
    @State private var showingDiscardAlert = false
    @State private var shouldFocusNewItem = false
    let height: CGFloat
    @Binding var isKeyboardActive: Bool
    let onEditingChanged: (Bool) -> Void
    
    // Add state for shake animation
    @State private var shakeOffset: CGFloat = 0
    
    // Haptic feedback generator
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    
    init(viewModel: ChecklistViewModel, height: CGFloat, isKeyboardActive: Binding<Bool> = .constant(false), onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.height = height
        self._isKeyboardActive = isKeyboardActive
        self.onEditingChanged = onEditingChanged
        self._viewState = StateObject(wrappedValue: ChecklistViewState(viewModel: viewModel))
    }
    
    private func performShakeAnimation() {
        let duration = 0.1  // Faster movement
        let amplitude: CGFloat = 6.0  // Keep same amplitude
        
        withAnimation(.easeOut(duration: duration)) {  // Use easeOut for snappier movement
            shakeOffset = amplitude
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeOut(duration: duration)) {  // Use easeOut for snappier movement
                shakeOffset = -amplitude
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.easeOut(duration: duration)) {  // Use easeOut for snappier movement
                    shakeOffset = 0
                }
            }
        }
    }
    
    private func handleRestrictedAction() {
        performShakeAnimation()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CheckListHeader(
                isEditing: viewState.isEditing,
                hasUnsavedChanges: viewState.hasUnsavedChanges,
                isKeyboardActive: isKeyboardActive,
                onEdit: {
                    if !viewState.isEditing {
                        viewModel.saveSnapshot()
                        viewState.isEditing.toggle()
                        viewModel.isEditing = true
                        onEditingChanged(true)
                    }
                },
                onImportCalendar: { await viewState.importFromCalendar() },
                onImportYesterday: { await viewState.importFromYesterday() },
                onImportFromDate: { date in await viewState.importFromDate(date) },
                onDiscard: {
                    viewState.discardChanges()
                    viewModel.isEditing = false
                    onEditingChanged(false)
                },
                onSave: {
                    if viewState.editingItem != nil {
                        viewState.saveEdit()
                    }
                    if !viewState.newItemText.isEmpty {
                        viewState.addNewItem()
                        viewState.newItemText = ""
                    }
                    viewState.isEditing.toggle()
                    viewModel.isEditing = false
                    onEditingChanged(false)
                },
                showingDiscardAlert: $showingDiscardAlert,
                showingImportYesterdayConfirmation: $viewState.showingImportYesterdayConfirmation,
                showingImportYesterdayOptions: $viewState.showingImportYesterdayOptions,
                showingImportDateConfirmation: $viewState.showingImportDateConfirmation,
                showingImportDateOptions: $viewState.showingImportDateOptions,
                selectedImportDate: $viewState.selectedImportDate,
                onConfirmImport: { await viewState.confirmImportFromYesterday() },
                onOverwriteImport: { await viewState.overwriteWithYesterday() },
                onConfirmDateImport: { await viewState.confirmImportFromDate() },
                onOverwriteDateImport: { await viewState.overwriteWithDate() }
            )
            
            ZStack(alignment: .bottom) {
                List {
                    CheckListContent(
                        viewModel: viewModel,
                        viewState: viewState,
                        shouldFocusNewItem: $shouldFocusNewItem
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .cornerRadius(16, corners: [.bottomLeft, .bottomRight])
                )
                
                if !viewState.isEditing {
                    VStack {
                        Spacer()
                        CheckListFooter(
                            completedCount: viewModel.items.filter(\.isCompleted).count,
                            totalCount: viewModel.items.count,
                            isDragging: .constant(false)
                        )
                    }
                    .ignoresSafeArea(.all, edges: .bottom)
                }
            }
        }
        .frame(height: height)
        .environment(\.editMode, .constant(viewState.isEditing ? .active : .inactive))
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .interactiveDismissDisabled(viewState.isEditing)
        .offset(x: shakeOffset)
        .simultaneousGesture(
            DragGesture()
                .onChanged { _ in
                    if viewState.isEditing {
                        handleRestrictedAction()
                    }
                }
        )
        .onAppear {
            feedbackGenerator.prepare()
        }
        .onChange(of: viewState.isEditing) { isEditing in
            onEditingChanged(isEditing)
        }
    }
}
