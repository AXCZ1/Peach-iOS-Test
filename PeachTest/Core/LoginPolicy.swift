import Foundation

enum LoginPolicy {
    static let deadline: Duration = .seconds(25)
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 30
    static let waitsForConnectivity = false
}
