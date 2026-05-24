import Foundation

enum CourseIdentitySource: String, Equatable {
    case generated
    case imported
    case futureServer
}

enum CourseDirectionEstimate: String, Equatable {
    case northbound
    case southbound
    case eastbound
    case westbound
    case loop
    case unknown
}

struct CourseIdentity: Equatable {
    let courseId: String
    let identityVersion: Int
    let estimatedCenter: WorkoutRouteCoordinate
    let estimatedDistance: Double
    let estimatedDirection: CourseDirectionEstimate?
    let source: CourseIdentitySource
}
