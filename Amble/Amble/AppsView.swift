import SwiftUI
import Combine
import FamilyControls

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let urlScheme: String?
}

final class AppsViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var installedApps: [AppItem] = []
    @Published var selectedAppIds: Set<String> = []
    @Published var showScreenTimePicker: Bool = false
    private(set) var installedIds: Set<String> = []

    private let prioritizedIds: [String] = ["instagram", "youtube", "facebook", "snapchat"]
    private let allCatalog: [AppItem] = [
        AppItem(id: "instagram", name: "Instagram", urlScheme: "instagram://"),
        AppItem(id: "youtube", name: "YouTube", urlScheme: "youtube://"),
        AppItem(id: "facebook", name: "Facebook", urlScheme: "fb://"),
        AppItem(id: "snapchat", name: "Snapchat", urlScheme: "snapchat://"),
        AppItem(id: "twitter", name: "X (Twitter)", urlScheme: "twitter://"),
        AppItem(id: "tiktok", name: "TikTok", urlScheme: "tiktok://"),
        AppItem(id: "whatsapp", name: "WhatsApp", urlScheme: "whatsapp://"),
        AppItem(id: "messenger", name: "Messenger", urlScheme: "fb-messenger://"),
        AppItem(id: "reddit", name: "Reddit", urlScheme: "reddit://"),
        AppItem(id: "pinterest", name: "Pinterest", urlScheme: "pinterest://"),
        AppItem(id: "netflix", name: "Netflix", urlScheme: "nflx://"),
        AppItem(id: "spotify", name: "Spotify", urlScheme: "spotify://")
    ]

    private let storageKey = "selectedAppIds"

    func load() {
        selectedAppIds = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
        refreshInstalled()
    }

    func toggleSelection(for app: AppItem) {
        if selectedAppIds.contains(app.id) {
            selectedAppIds.remove(app.id)
        } else {
            selectedAppIds.insert(app.id)
        }
        UserDefaults.standard.set(Array(selectedAppIds), forKey: storageKey)
    }

    func filteredApps() -> [AppItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = installedApps
        guard !q.isEmpty else { return source }
        return source.filter { $0.name.lowercased().contains(q) }
    }

    private func refreshInstalled() {
        // Detect installed IDs using canOpenURL on our curated catalog
        var detected: Set<String> = []
        for item in allCatalog {
            if let scheme = item.urlScheme, let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                detected.insert(item.id)
            }
        }
        installedIds = detected

        // Build visible list as full catalog, sorting by: prioritized+installed, installed, then name
        let prioritizedSet = Set(prioritizedIds)
        var all = allCatalog
        all.sort { a, b in
            let aPriorInstalled = prioritizedSet.contains(a.id) && installedIds.contains(a.id)
            let bPriorInstalled = prioritizedSet.contains(b.id) && installedIds.contains(b.id)
            if aPriorInstalled != bPriorInstalled { return aPriorInstalled && !bPriorInstalled }

            let aInstalled = installedIds.contains(a.id)
            let bInstalled = installedIds.contains(b.id)
            if aInstalled != bInstalled { return aInstalled && !bInstalled }

            let aPriorityOnly = prioritizedSet.contains(a.id)
            let bPriorityOnly = prioritizedSet.contains(b.id)
            if aPriorityOnly != bPriorityOnly { return aPriorityOnly && !bPriorityOnly }

            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        installedApps = all
    }

    func isInstalled(_ app: AppItem) -> Bool { installedIds.contains(app.id) }
}

struct AppsView: View {
    @StateObject private var viewModel = AppsViewModel()
    @StateObject private var screenTimeManager = ScreenTimeManager()

    var body: some View {
        List {
            // Screen Time Section
            Section {
                if screenTimeManager.authorizationStatus == .approved {
                    Button(action: { viewModel.showScreenTimePicker = true }) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.tint)
                            Text("Select Apps via Screen Time")
                            Spacer()
                            if !screenTimeManager.selectedActivityTokens.isEmpty {
                                Text("\(screenTimeManager.selectedActivityTokens.count) selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    
                    if !screenTimeManager.selectedActivityTokens.isEmpty {
                        Button(role: .destructive, action: {
                            screenTimeManager.clearSelectedTokens()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Screen Time Selection")
                            }
                        }
                    }
                } else {
                    Button(action: {
                        Task {
                            await screenTimeManager.requestAuthorization()
                        }
                    }) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                            Text("Enable Screen Time Access")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Screen Time")
            } footer: {
                if screenTimeManager.authorizationStatus == .approved {
                    Text("Select apps using Screen Time to see all installed apps on your device.")
                } else {
                    Text("Screen Time allows you to select from all installed apps on your device.")
                }
            }
            
            // URL Scheme Catalog Section
            Section {
                ForEach(viewModel.filteredApps()) { app in
                    Button(action: { viewModel.toggleSelection(for: app) }) {
                        HStack(spacing: 12) {
                            Image(systemName: viewModel.isInstalled(app) ? "app.fill" : "app")
                                .foregroundStyle(viewModel.isInstalled(app) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            Text(app.name)
                            Spacer()
                            if viewModel.isInstalled(app) {
                                Text("Installed").font(.caption).foregroundStyle(.secondary)
                            }
                            if viewModel.selectedAppIds.contains(app.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Popular Apps")
            } footer: {
                Text("Apps detected via URL schemes. Limited to apps with known schemes.")
            }
        }
        .navigationTitle("Apps")
        .searchable(text: $viewModel.query, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear { viewModel.load() }
        .sheet(isPresented: $viewModel.showScreenTimePicker) {
            NavigationView {
                FamilyActivityPicker(selection: $screenTimeManager.selection)
                    .navigationTitle("Select Apps")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                viewModel.showScreenTimePicker = false
                                screenTimeManager.saveSelection(screenTimeManager.selection)
                            }
                        }
                    }
            }
        }
    }
}

#Preview {
    NavigationView { AppsView() }
}


