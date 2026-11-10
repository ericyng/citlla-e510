import SwiftUI

/// The sidebar of the main window: one row per section that has a view today.
///
/// The list comes from `MainSection.available`, which the feature tracks append
/// to as their sections land, so the app never offers an empty section.
struct MainSidebar: View {
    @Binding var selection: MainSection

    var body: some View {
        List(
            selection: Binding<MainSection?>(
                get: { selection },
                set: { newValue in
                    if let newValue { selection = newValue }
                }
            )
        ) {
            Section("Citlla E510") {
                ForEach(MainSection.available) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
    }
}
