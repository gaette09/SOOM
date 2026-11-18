import Foundation
import MapboxMaps

enum SOOMMapboxConfiguration {
    static let styleURIString = "mapbox://styles/gaette09/cmqtub3xc004m01rg7s331tq2"
    // The detail style imports Mapbox Standard, which Static Images does not
    // render. Use the compatible street basemap for static previews; the
    // privacy-masked course geometry still comes from the same workout route.
    // https://docs.mapbox.com/api/maps/static-images/
    static let staticImagesStyleID = "mapbox/streets-v12"

    static var styleURI: StyleURI {
        StyleURI(rawValue: styleURIString)!
    }
}
