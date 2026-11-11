import SwiftUI

struct InspectorHelpButton: View {
    let title: String
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                Text(text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .padding(16)
            .frame(width: 420, alignment: .leading)
        }
        .accessibilityLabel("Help for \(title)")
    }
}
