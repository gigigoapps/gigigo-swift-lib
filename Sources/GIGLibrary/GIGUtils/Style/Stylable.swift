import Foundation

@MainActor
public protocol Stylable {
	associatedtype Style
    func withStyle(_ style: Style)
}

@MainActor
public protocol ViewStylable {
    associatedtype VStyle
    func withViewStyle(_ style: VStyle)
}
