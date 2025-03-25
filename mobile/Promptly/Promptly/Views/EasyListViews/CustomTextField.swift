import SwiftUI

/// A custom text field implementation that provides enhanced control over text input behavior
/// and appearance, including support for strikethrough text, placeholder styling, and return key handling.
struct CustomTextField: UIViewRepresentable {
    // MARK: - Properties
    
    /// The text binding that controls and monitors the text field's content
    @Binding var text: String
    
    /// The color of the text in the text field
    var textColor: UIColor = .white
    
    /// The placeholder text to display when the text field is empty
    var placeholder: String = ""
    
    /// The color of the placeholder text
    var placeholderColor: UIColor = .gray
    
    /// Whether to apply a strikethrough style to the text
    var isStrikethrough: Bool = false
    
    /// The text style to use for the text field
    var textStyle: UIFont.TextStyle = .body
    
    /// Whether the text should automatically resize to fit the width
    var isResizable: Bool = false
    
    /// Callback triggered when the return key is pressed
    var onReturn: (() -> Void)?
    
    /// Callback triggered when the text changes
    var onTextChange: ((String) -> Void)?

    // MARK: - UIViewRepresentable Implementation
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.backgroundColor = .clear
        textField.returnKeyType = .next
        textField.delegate = context.coordinator
        
        updateTextFieldAttributes(textField)
        
        // Support dynamic type with size constraints
        textField.adjustsFontForContentSizeCategory = true
        textField.font = .preferredFont(forTextStyle: textStyle)
        textField.adjustsFontSizeToFitWidth = isResizable
        
        // Align text to the left
        textField.textAlignment = .left
        
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.didBeginEditing(_:)), for: .editingDidBegin)
        textField.addTarget(context.coordinator, action: #selector(Coordinator.didEndEditing(_:)), for: .editingDidEnd)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Always update attributes to ensure strikethrough and other properties are current
        updateTextFieldAttributes(uiView)
        
        // Update resizable state
        uiView.adjustsFontSizeToFitWidth = isResizable
        
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
    }
    
    // MARK: - Private Methods
    
    private func updateTextFieldAttributes(_ textField: UITextField) {
        // Store current cursor position
        let currentPosition = textField.selectedTextRange
        
        let attributes: [NSAttributedString.Key: Any] = [
            .strikethroughStyle: isStrikethrough ? NSUnderlineStyle.single.rawValue : 0,
            .strikethroughColor: UIColor.gray,
            .foregroundColor: textColor,
            .font: UIFont.preferredFont(forTextStyle: textStyle)
        ]
        
        textField.attributedText = NSAttributedString(string: text, attributes: attributes)
        
        // Restore cursor position
        if let position = currentPosition {
            textField.selectedTextRange = position
        }
    }

    // MARK: - Coordinator
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CustomTextField

        init(_ parent: CustomTextField) {
            self.parent = parent
            super.init()
        }

        @objc func textChanged(_ textField: UITextField) {
            let newText = textField.text ?? ""
            DispatchQueue.main.async {
                self.parent.text = newText
                self.parent.onTextChange?(newText)
            }
        }

        @objc func didBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                textField.selectedTextRange = textField.textRange(from: textField.endOfDocument, to: textField.endOfDocument)
            }
        }
        
        @objc func didEndEditing(_ textField: UITextField) {
            // Clear text selection when editing ends
            textField.selectedTextRange = nil
        }
        
        // Handle return key press
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let onReturn = parent.onReturn {
                onReturn()
            }
            return false
        }
    }
} 