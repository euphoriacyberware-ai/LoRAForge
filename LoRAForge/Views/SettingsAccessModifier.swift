import SwiftUI

extension View {
    @ViewBuilder
    func withSettingsAccess() -> some View {
        #if os(iOS)
        modifier(SettingsAccessModifier())
        #else
        self
        #endif
    }
}

#if os(iOS)
private struct SettingsAccessModifier: ViewModifier {
    @State private var showingSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView()
                        .navigationTitle("Settings")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingSettings = false }
                            }
                        }
                }
            }
    }
}
#endif
