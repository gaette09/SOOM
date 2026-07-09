import Foundation
import UniformTypeIdentifiers

struct ActivityDetailGPXRouteImportAction {
    let importRoute: (URL) async -> ActivityDetailGPXRouteImportResult
}

enum ActivityDetailGPXRouteImportResult: Equatable {
    case success
    case failure(ActivityDetailGPXRouteImportError)
}

enum ActivityDetailGPXRouteImportError: Equatable {
    case unsupportedFileType
    case unreadableFile
    case invalidGPX
    case routeTooShort
    case alreadyHasRoute
    case unsupportedWorkoutSource
    case persistenceFailed
    case workoutNotFound
    case unknown

    var message: String {
        switch self {
        case .unsupportedFileType:
            return "GPX 또는 FIT 파일만 가져올 수 있습니다."
        case .unreadableFile:
            return "경로 파일을 읽을 수 없습니다."
        case .invalidGPX:
            return "경로 파일을 읽을 수 없습니다."
        case .routeTooShort:
            return "경로 좌표가 충분하지 않습니다."
        case .alreadyHasRoute:
            return "이미 경로가 있는 운동입니다."
        case .unsupportedWorkoutSource:
            return "이 운동에는 경로 파일을 추가할 수 없습니다."
        case .persistenceFailed:
            return "경로를 저장하지 못했습니다."
        case .workoutNotFound:
            return "운동 기록을 찾을 수 없습니다."
        case .unknown:
            return "경로를 추가하지 못했습니다."
        }
    }

    init(attachmentError: GPXRouteAttachmentError) {
        switch attachmentError {
        case .invalidGPX:
            self = .invalidGPX
        case .routeTooShort:
            self = .routeTooShort
        case .workoutNotFound:
            self = .workoutNotFound
        case .alreadyHasRoute:
            self = .alreadyHasRoute
        case .unsupportedSource:
            self = .unsupportedWorkoutSource
        case .persistenceFailed:
            self = .persistenceFailed
        }
    }

    init(attachmentError: FITRouteAttachmentError) {
        switch attachmentError {
        case .invalidFIT:
            self = .invalidGPX
        case .routeTooShort:
            self = .routeTooShort
        case .workoutNotFound:
            self = .workoutNotFound
        case .alreadyHasRoute:
            self = .alreadyHasRoute
        case .unsupportedSource:
            self = .unsupportedWorkoutSource
        case .persistenceFailed:
            self = .persistenceFailed
        }
    }
}

enum ActivityDetailGPXRouteImportEligibility {
    static func canAttachGPXRoute(to workout: UnifiedWorkout?, hasRoute: Bool) -> Bool {
        guard let workout else { return false }
        guard workout.source == .appleHealthKit else { return false }
        guard !hasRoute else { return false }
        return workout.routeMissingReason.isActionableForRouteAttachment
    }
}

enum ActivityDetailGPXRouteFileImport {
    enum RouteFileFormat: Equatable {
        case gpx
        case fit
    }

    static let allowedContentTypes: [UTType] = {
        var contentTypes: [UTType] = []
        if let gpxType = UTType(filenameExtension: "gpx") {
            contentTypes.append(gpxType)
        }
        if let fitType = UTType(filenameExtension: "fit") {
            contentTypes.append(fitType)
        }
        contentTypes.append(.xml)
        contentTypes.append(.data)
        return contentTypes
    }()

    static func isSupportedFileURL(_ url: URL) -> Bool {
        routeFileFormat(for: url) != nil
    }

    static func routeFileFormat(for url: URL) -> RouteFileFormat? {
        switch url.pathExtension.lowercased() {
        case "gpx":
            return .gpx
        case "fit":
            return .fit
        default:
            return nil
        }
    }
}
