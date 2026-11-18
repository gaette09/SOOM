import SwiftUI

struct CheckInScaleSelector: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let caption: String
    let lowText: String
    let highText: String
    @Binding var selection: Int

    var body: some View {
        SOOMCard {
            SOOMSectionHeader(title, caption: caption)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: SOOMLayout.CheckIn.optionSpacing))
                : AnyLayout(HStackLayout(spacing: SOOMLayout.CheckIn.optionSpacing))
            layout {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        VStack(spacing: SOOMLayout.SectionHeader.spacing) {
                            Text("\(value)")
                                .font(SOOMFont.body(15, weight: .bold, relativeTo: .subheadline))
                            Text(label(for: value))
                                .font(SOOMFont.body(12, weight: .bold, relativeTo: .caption))
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .opacity(selection == value ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(selection == value ? SOOMColor.white : SOOMColor.ink)
                        .frame(maxWidth: .infinity, minHeight: SOOMLayout.CheckIn.optionMinHeight)
                        .background(selection == value ? SOOMColor.green : SOOMColor.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: SOOMLayout.CheckIn.optionCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(value)점")
                    .accessibilityValue("\(label(for: value))\(selection == value ? ", 선택됨" : "")")
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
                    .accessibilityIdentifier("checkin.scale.\(title).\(value)")
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

