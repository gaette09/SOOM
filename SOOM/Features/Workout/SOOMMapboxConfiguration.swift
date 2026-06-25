import Foundation
import MapboxMaps

enum SOOMMapboxConfiguration {
    static let styleURIString = "mapbox://styles/gaette09/cmqtub3xc004m01rg7s331tq2"
    static let staticImagesStyleID = "gaette09/cmqtub3xc004m01rg7s331tq2"

    static var styleURI: StyleURI {
        StyleURI(rawValue: styleURIString)!
    }
}
