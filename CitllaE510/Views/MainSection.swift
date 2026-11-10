import Foundation

/// A section of the main window's sidebar.
///
/// The contract commit defines the whole set so the app-shell track can build
/// the navigation, and the features behind each section land in their own
/// tracks. `available` is the list the shell shows: a section is added to it in
/// the same merge that adds its view, so the app never shows an empty one.
enum MainSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case buttons
    case actions
    case profiles
    case scrolling
    case advanced
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .buttons: "Buttons"
        case .actions: "Actions"
        case .profiles: "Profiles"
        case .scrolling: "Scrolling"
        case .advanced: "Advanced"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .buttons: "computermouse"
        case .actions: "list.number"
        case .profiles: "app.badge.checkmark"
        case .scrolling: "scroll"
        case .advanced: "wrench.and.screwdriver"
        case .permissions: "lock.shield"
        case .about: "info.circle"
        }
    }

    /// Sections that have a view today. Tracks append their case when their
    /// view lands: actions (macro-ui), profiles (profiles), scrolling
    /// (scrolling).
    static var available: [MainSection] {
        [.overview, .buttons, .advanced, .permissions, .about]
    }
}
