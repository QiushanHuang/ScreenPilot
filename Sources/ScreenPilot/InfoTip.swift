import SwiftUI

/// Supplemental details stay available to mouse, keyboard and VoiceOver users.
struct InfoTip: View {
    let title: String
    let message: String
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "info.circle")
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("\(title)说明")
        .help(title)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(16)
        }
    }
}
