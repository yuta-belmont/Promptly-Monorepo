// mobile/Promptly/Promptly/Views/Common/InterceptingTextField.swift
import SwiftUI
import UIKit

struct InterceptingTextField: UIViewRepresentable {

    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding // Use FocusState binding directly
    var onCommit: () -> Void // Renamed from onSubmit for clarity with SwiftUI modifiers

    // Internal Coordinator class
    class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding
        var onCommit: () -> Void
        private var isFirstResponderProgrammaticallySet: Bool = false // Flag to prevent update loops

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onCommit: @escaping () -> Void) {
            _text = text
            self.isFocused = isFocused
            self.onCommit = onCommit
        }

        // Update SwiftUI text binding when UIKit text changes
        func textFieldDidChangeSelection(_ textField: UITextField) {
            // Ensure the update comes from user interaction, not programmatic change
             DispatchQueue.main.async { // Ensure binding update happens on main thread safely
                self.text = textField.text ?? ""
            }
        }

        // Handle the Return key press
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if !(textField.text?.isEmpty ?? true) {
                // Text is not empty:
                print("InterceptingTextField: textFieldShouldReturn - Committing (text not empty)")
                onCommit() // Call the commit action (adds item, clears text state via binding)
                // DO NOT clear textField.text here - let SwiftUI binding handle it
                return false // *** Prevent default behavior (resign focus) ***
            } else {
                // Text is empty:
                print("InterceptingTextField: textFieldShouldReturn - Resigning focus (text empty)")
                textField.resignFirstResponder() // Allow focus loss
                return true // Allow default behavior (which includes resigning focus)
            }
        }

        // Update focus state binding when editing begins
        func textFieldDidBeginEditing(_ textField: UITextField) {
            // Only update binding if focus wasn't set programmatically by updateUIView
            if !isFirstResponderProgrammaticallySet {
                 DispatchQueue.main.async { // Ensure binding update happens on main thread safely
                     print("InterceptingTextField: textFieldDidBeginEditing - Setting focus binding to true")
                    self.isFocused.wrappedValue = true
                 }
            }
             isFirstResponderProgrammaticallySet = false // Reset flag
        }

        // Update focus state binding when editing ends
        func textFieldDidEndEditing(_ textField: UITextField) {
             DispatchQueue.main.async { // Ensure binding update happens on main thread safely
                 print("InterceptingTextField: textFieldDidEndEditing - Setting focus binding to false")
                self.isFocused.wrappedValue = false
             }
        }
    }

    // Create the Coordinator
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, onCommit: onCommit)
    }

    // Create the underlying UIKit view
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.returnKeyType = .done // Or .next, .search depending on context
        textField.autocorrectionType = .no // Optional: Adjust as needed
        textField.spellCheckingType = .no   // Optional: Adjust as needed
        textField.setContentHuggingPriority(.defaultHigh, for: .vertical) // Helps with layout
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // Allows shrinking
        // Basic styling (can be customized further)
        textField.borderStyle = .none
        textField.textColor = .white // Adapts to light/dark mode? Consider UIColor(dynamicProvider:)
        textField.font = UIFont.preferredFont(forTextStyle: .body) // Use dynamic type
        return textField
    }

    // Update the UIKit view when SwiftUI state changes
    func updateUIView(_ uiView: UITextField, context: Context) {
        // Update text if different
        if uiView.text != text {
             print("InterceptingTextField: updateUIView - Updating text field text to: '\(text)'")
            uiView.text = text
        }

        // Update placeholder (less critical, but good practice)
        uiView.placeholder = placeholder

        // Update placeholder color based on focus (example)
        let placeholderColor: UIColor = isFocused.wrappedValue ? .gray : .gray // Same for now, adjust if needed
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )

        // Update text color based on focus (example)
        uiView.textColor = isFocused.wrappedValue ? .white : .gray

        // Update focus state if different
        if isFocused.wrappedValue && !uiView.isFirstResponder {
            print("InterceptingTextField: updateUIView - Becoming first responder")
            context.coordinator.isFirstResponderProgrammaticallySet = true // Set flag
            uiView.becomeFirstResponder()
        } else if !isFocused.wrappedValue && uiView.isFirstResponder {
            print("InterceptingTextField: updateUIView - Resigning first responder")
            uiView.resignFirstResponder()
        }
         // Reset the flag if focus state matches responder state without intervention
        if (isFocused.wrappedValue && uiView.isFirstResponder) || (!isFocused.wrappedValue && !uiView.isFirstResponder) {
             context.coordinator.isFirstResponderProgrammaticallySet = false
        }
    }
}
