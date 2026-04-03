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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                appState.isExpanded.toggle()
                panelController.setExpanded(appState.isExpanded)
            }
        }
        .onChange(of: appState.isExpanded) { _, newValue in
            panelController.setExpanded(newValue)
        }
    }
}
