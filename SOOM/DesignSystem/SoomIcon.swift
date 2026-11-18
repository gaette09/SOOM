import SwiftUI

enum SOOMIcon {
    static let home = "house.fill"
    static let analysis = "chart.xyaxis.line"
    static let record = "plus.circle.fill"
    static let feed = "person.2.fill"
    static let activity = "list.bullet.rectangle"
    static let clubs = "flag.checkered"
    static let profile = "person.crop.circle"
    static let swim = "soom_pool_swimming"
    static let openWaterSwim = "soom_open_water_swimming"
    static let bike = "soom_road_cycling"
    static let mountainBike = "soom_mtb"
    static let run = "soom_running"
    static let trailRun = "soom_trail_running"
    static let brick = "point.3.connected.trianglepath.dotted"
    static let back = "chevron.left"
    static let chevronLeft = "chevron.left"
    static let ranking = "trophy"
    static let settings = "gearshape"
    static let bookmarkFilled = "bookmark.fill"
    static let chevronRight = "chevron.right"
    static let collapse = "chevron.down"
    static let close = "xmark"
    static let bookmark = "bookmark"
    static let more = "ellipsis"
    static let calendar = "calendar"
    static let calendarClock = "calendar.badge.clock"
    static let checkCircle = "checkmark.circle"
    static let edit = "square.and.pencil"
    static let share = "square.and.arrow.up"
    static let trash = "trash"
    static let health = "heart.text.square"
    static let shield = "checkmark.shield.fill"
    static let map = "map"
    static let chartBar = "chart.bar"
    static let sync = "arrow.triangle.2.circlepath"
    static let package = "shippingbox"
    static let people = "person.3"
    static let personAdd = "person.badge.plus"
    static let medal = "medal"
    static let comment = "bubble.right"
    static let thumbsUp = "hand.thumbsup"
    static let sparkles = "sparkles"
    static let routeStart = "circle.fill"
    static let trend = "chart.line.uptrend.xyaxis"
    static let heart = "heart.fill"
    static let waveform = "waveform.path.ecg"
    static let chartLine = "chart.xyaxis.line"
    static let bolt = "bolt.fill"
    static let moon = "moon.fill"
    static let recovery = "heart.text.square"
    static let trendUp = "arrow.up.right"
    static let trendDown = "arrow.down.right"
    static let trendFlat = "arrow.right"
}

/// Keeps the packaged 24pt sport artwork proportional at the size of each UI slot.
/// Other activity types continue to use the existing symbol catalog.
struct SOOMSportIconView: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if SOOMPhosphorCatalog.isSportAsset(name) {
            Image(soom: name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(soom: name)
                .font(.system(size: size))
                .frame(width: size, height: size)
        }
    }
}
