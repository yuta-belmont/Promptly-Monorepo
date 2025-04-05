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
    
    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $localNotes)
                .font(.body)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .padding(4)
                .padding(.horizontal, 6)
                .padding(.top, 0)
                .focused($isFocused)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
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
        .padding(.vertical, 0.5)
        .padding(.horizontal, 6)
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
            // Initialize local notes when view appears
            localNotes = notes
        }
        .onChange(of: notes) { oldValue, newValue in
            // Keep local notes in sync with external changes
            if localNotes != newValue {
                localNotes = newValue
            }
        }
    }
    
    private func saveNotes() {
        onSave(localNotes)
    }
} 
