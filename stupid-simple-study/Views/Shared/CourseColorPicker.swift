import SwiftUI

struct CourseColorPicker: View {
    @Binding var colorHex: String

    private var color: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) },
            set: { colorHex = $0.hexString() }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(CourseColorPalette.hexColors, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if colorHex.uppercased() == hex.uppercased() {
                                        Circle().strokeBorder(.white, lineWidth: 2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                ColorPicker("", selection: color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 22)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
