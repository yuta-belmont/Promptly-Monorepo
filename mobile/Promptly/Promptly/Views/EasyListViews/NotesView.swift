import SwiftUI
import Combine

struct NotesView: View {
    @Binding var notes: String
    @FocusState var isFocused: Bool
    @Binding var isEditing: Bool
    let title: String
    let onSave: (String) -> Void
    @EnvironmentObject private var focusManager: FocusManager
    
    // For handling debounced saving
    @State private var debouncedText: String = ""
    @State private var saveWorkItem: DispatchWorkItem? = nil
    
    // Add local state to decouple from the model
    @State private var localNotes: String = ""
    
    // Add keyboard height state
    @State private var keyboardHeight: CGFloat = 16
    
    // Add namespace for animation
    @Namespace private var animation
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                TextEditor(text: $localNotes)
                    .font(.body)
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 6)
                    .padding(.top, 0)
                    .focused($isFocused)
                    .frame(height: geometry.size.height - keyboardHeight)
                    .overlay(
                        Group {
                            if localNotes.isEmpty && !isEditing  {
                                Text("Notes...")
                                    .foregroundColor(.white.opacity(0.3))
                                    .padding(.leading, 12)
                                    .padding(.top, 10)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
                
                // Character count
                HStack {
                    Spacer()
                    Text("\(localNotes.count)/2000")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.trailing)
                        .padding(.bottom, 2)
                }
            }
        }
        .onChange(of: localNotes) { oldValue, newValue in
            if newValue.count > 2000 {
                localNotes = String(newValue.prefix(2000))
                return
            }
            
            // Cancel any pending save
            saveWorkItem?.cancel()
            
            // Create a new debounced save operation
            let workItem = DispatchWorkItem {
                saveNotes()
            }
            
            // Schedule the save after a delay
            saveWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
        .onChange(of: isFocused) { oldValue, newValue in
            isEditing = newValue
            
            // Save immediately when losing focus
            if oldValue && !newValue {
                saveNotes()
            }
        }
        .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if oldValue == .easyList && newValue != .easyList {
                isFocused = false
                // Save when the view changes
                saveNotes()
            }
        }
        .onAppear {
            // Initialize local notes with current notes from model
            localNotes = notes
            
            // Initialize debounced text with current notes
            debouncedText = notes
            
            // Set up keyboard notifications
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillShowNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                      let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
                else { return }
                
                let curve = UIView.AnimationCurve(rawValue: Int(curveValue)) ?? .easeInOut
                
                withAnimation(.easeInOut(duration: duration)) {
                    switch curve {
                    case .easeIn:
                        withAnimation(.easeIn(duration: duration)) {
                            keyboardHeight = keyboardFrame.height - 24
                        }
                    case .easeOut:
                        withAnimation(.easeOut(duration: duration)) {
                            keyboardHeight = keyboardFrame.height - 24
                        }
                    case .easeInOut:
                        withAnimation(.easeInOut(duration: duration)) {
                            keyboardHeight = keyboardFrame.height - 24
                        }
                    case .linear:
                        withAnimation(.linear(duration: duration)) {
                            keyboardHeight = keyboardFrame.height - 24
                        }
                    @unknown default:
                        withAnimation(.easeInOut(duration: duration)) {
                            keyboardHeight = keyboardFrame.height - 24
                        }
                    }
                }
            }
            
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                      let curveValue = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
                else { return }
                
                let curve = UIView.AnimationCurve(rawValue: Int(curveValue)) ?? .easeInOut
                
                withAnimation(.easeInOut(duration: duration)) {
                    switch curve {
                    case .easeIn:
                        withAnimation(.easeIn(duration: duration)) {
                            keyboardHeight = +16
                        }
                    case .easeOut:
                        withAnimation(.easeOut(duration: duration)) {
                            keyboardHeight = +16
                        }
                    case .easeInOut:
                        withAnimation(.easeInOut(duration: duration)) {
                            keyboardHeight = +16
                        }
                    case .linear:
                        withAnimation(.linear(duration: duration)) {
                            keyboardHeight = +16
                        }
                    @unknown default:
                        withAnimation(.easeInOut(duration: duration)) {
                            keyboardHeight = +16
                        }
                    }
                }
            }
        }
        .onChange(of: notes) { oldValue, newValue in
            // Update local notes if the model changes externally
            if newValue != localNotes && !isFocused {
                localNotes = newValue
                debouncedText = newValue
            }
        }
        .onDisappear {
            // Save when view disappears
            saveNotes()
            
            // Clean up any pending work item
            saveWorkItem?.cancel()
            saveWorkItem = nil
        }
    }
    
    /// Save notes only if they've actually changed
    private func saveNotes() {
        if debouncedText != localNotes {
            debouncedText = localNotes
            onSave(localNotes)
        }
    }
} 
