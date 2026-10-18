import SwiftUI
import UIKit

/// An inline native field keeps Search above its content. Registering searchable
/// with a search-role tab lets iOS move the field into the bottom tab bar.
struct SearchQueryField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool

    func makeUIView(context: Context) -> UISearchTextField {
        let field = UISearchTextField()
        field.placeholder = "Search notes"
        field.accessibilityLabel = "Search notes"
        field.accessibilityIdentifier = "searchQueryField"
        field.returnKeyType = .search
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.tintColor = UIColor(NotoTheme.accentText)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UISearchTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        if !focused, field.isFirstResponder { field.resignFirstResponder() }
        else if focused, !field.isFirstResponder, field.window != nil { field.becomeFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchQueryField
        init(_ parent: SearchQueryField) { self.parent = parent }
        @objc func changed(_ field: UISearchTextField) { parent.text = field.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.focused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.focused = false }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.focused = false
            return true
        }
    }
}
