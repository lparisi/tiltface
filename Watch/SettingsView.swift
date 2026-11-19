import SwiftUI

/// Long-press the face to open this.
struct SettingsView: View {
    @Binding var styleRaw: String
    @Binding var flipTilt: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sprites") {
                    ForEach(SpriteStyle.allCases) { style in
                        Button {
                            styleRaw = style.rawValue
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                let preview = style.nodeSize(unit: 12)
                                SpriteArtwork(style: style)
                                    .frame(width: preview.width, height: preview.height)
                                    .frame(width: 32)
                                Text(style.title)
                                Spacer(minLength: 0)
                                if style.rawValue == styleRaw {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(style.accent)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Flip tilt", isOn: $flipTilt)
                } footer: {
                    Text("Turn on if things roll uphill. Tap the face to shake; long-press for this menu.")
                }
            }
            .navigationTitle("TiltFace")
        }
    }
}
