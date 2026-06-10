import Foundation

struct EndpointStatus: Equatable {
    enum Reachability: Equatable {
        case notChecked
        case checking
        case reachable
        case unreachable
    }

    let endpointName: String
    let endpointDescription: String
    let reachability: Reachability
    let message: String?
    let downloadSpeedBytesPerSecond: Int64
    let connections: Int
}
