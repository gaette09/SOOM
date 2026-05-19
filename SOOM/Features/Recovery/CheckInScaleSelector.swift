import SwiftUI

struct CheckInScaleSelector: View {
    let title: String
    let caption: String
    let lowText: String
    let highText: String
    @Binding var selection: Int

    var body: some View {
        SOOMCard {
            SOOMSectionHeader(title, caption: caption)

            HStack(spacing: SOOMLayout.CheckIn.optionSpacing) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        VStack(spacing: SOOMLayout.SectionHeader.spacing) {
                            Text("\(value)")
                                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            Text(label(for: value))
                                .font(SOOMFont.body(10, weight: .bold, relativeTo: .caption2))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(selection == value ? SOOMColor.white : SOOMColor.ink)
                        .frame(maxWidth: .infinity, minHeight: SOOMLayout.CheckIn.optionMinHeight)
                        .background(selection == value ? SOOMColor.green : SOOMColor.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(value)점")
                    .accessibilityValue(label(for: value))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func label(for value: Int) -> String {
        switch value {
        case 1: lowText
        case 3: "보통"
        case 5: highText
        default: ""
        }
    }
}

