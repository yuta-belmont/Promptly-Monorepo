import SwiftUI

struct NotesView: View {
    @Binding var notes: String
    @FocusState var isFocused: Bool
    @Binding var isEditing: Bool
    let title: String
    let onSave: (String) -> Void
    @EnvironmentObject private var focusManager: FocusManager
    
    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $notes)
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
                .overlay(
                    Group {
                        if notes.isEmpty && !isEditing  {
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
                Text("\(notes.count)/2000")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.trailing)
                    .padding(.bottom, 2)
            }
        }
        .onChange(of: notes) { oldValue, newValue in
            if newValue.count > 2000 {
                notes = String(newValue.prefix(2000))
            }
            onSave(notes)
        }
        .onChange(of: isFocused) { oldValue, newValue in
            isEditing = newValue
        }
        .onChange(of: focusManager.currentFocusedView) { oldValue, newValue in
            if oldValue == .easyList && newValue != .easyList {
                isFocused = false
            }
        }
    }
} 
