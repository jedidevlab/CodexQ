import AppKit
import SwiftUI

struct TokenHistoryWeekDatePicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.selectionChanged(_:))
        picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        if picker.dateValue != selection {
            picker.dateValue = selection
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding private var selection: Date

        init(selection: Binding<Date>) {
            _selection = selection
        }

        @objc func selectionChanged(_ sender: NSDatePicker) {
            selection = sender.dateValue
        }
    }
}
