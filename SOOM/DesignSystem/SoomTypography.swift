import SwiftUI

enum SOOMFont {
    enum Weight {
        case regular
        case bold
    }

    enum Size {
        static let caption: CGFloat = 12
        static let subheadline: CGFloat = 14
        static let body: CGFloat = 16
        static let headline: CGFloat = 18
        static let title: CGFloat = 22
    }

    static let displayBoldName = "GmarketSansTTFBold"
    static let displayMediumName = "GmarketSansTTFMedium"
    static let bodyRegularName = "NanumSquareNeoTTF-bRg"
    static let bodyBoldName = "NanumSquareNeoTTF-cBd"

    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(displayBoldName, size: size, relativeTo: style)
    }

    static func displayMedium(_ size: CGFloat, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom(displayMediumName, size: size, relativeTo: style)
    }

    static func body(_ size: CGFloat, weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(weight == .bold ? bodyBoldName : bodyRegularName, size: size, relativeTo: style)
    }
}
