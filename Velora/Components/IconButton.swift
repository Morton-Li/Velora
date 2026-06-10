import SwiftUI

struct IconButton: View {
    let systemName: String
    let help: String
    var role: ButtonRole?
    var isDisabled = false
    var action: () -> Void = {}

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .help(help)
    }
}
