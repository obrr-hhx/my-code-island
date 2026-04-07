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
            // Don't allow collapsing while permissions or questions are pending
            if appState.isExpanded
                && (!appState.pendingPermissions.isEmpty || !appState.pendingQuestions.isEmpty) {
                return
            }
            appState.isExpanded.toggle()
        }
        .id(appState.appTheme)  // Force full re-render on theme change
        .onChange(of: appState.isExpanded) { _, newValue in
            panelController.setExpanded(newValue)
        }
    }
}
