import SwiftUI

/// Root SwiftUI view for the notch panel.
/// Switches between collapsed (wing layout) and expanded (full UI) states.
struct NotchContentView: View {
    let appState: AppState
    let panelController: NotchPanelController
    let notchGeometry: NotchGeometry

    var body: some View {
        Group {
            if appState.isExpanded {
                NotchExpandedView(appState: appState, panelController: panelController)
            } else {
                NotchCollapsedView(appState: appState, notchGeometry: notchGeometry)
            }
        }
        .onTapGesture {
            appState.isExpanded.toggle()
        }
        .onChange(of: appState.isExpanded) { _, newValue in
            panelController.setExpanded(newValue)
        }
    }
}
