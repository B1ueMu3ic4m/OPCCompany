import Foundation

/// Minimal string helpers used by the logic layer.
///
/// Lived in OperationsSuiteView.swift (a UI file) while everything was
/// macOS-only; spike #5's census showed CompanyStore+Runtime/Tasks/Reports
/// call `nilIfBlank`, so it belongs in the portable core. Behavior unchanged.
extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
