import SwiftUI

public struct NotesView: View {
    @Binding var notes: String
    let onSave: () -> Void
    @FocusState var isTextEditorFocused: Bool
    var onFocusChange: ((Bool) -> Void)?
    
    public init(notes: Binding<String>, onSave: @escaping () -> Void, onFocusChange: ((Bool) -> Void)? = nil) {
        self._notes = notes
        self.onSave = onSave
        self.onFocusChange = onFocusChange
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(
                get: { notes },
                set: { 
                    // Limit input to max characters
                    notes = String($0.prefix(Checklist.maxNotesLength))
                    onSave()
                }
            ))
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .focused($isTextEditorFocused)
            .onChange(of: isTextEditorFocused) { newValue in
                onFocusChange?(newValue)
            }
            
            // Add a small spacer at the bottom for better spacing
            Spacer()
                .frame(height: 8)
        }
        .padding(.bottom, 6)
    }
} 