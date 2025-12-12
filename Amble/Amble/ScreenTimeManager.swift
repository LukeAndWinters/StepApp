//
//  ScreenTimeManager.swift
//  Amble
//
//  Created on 6/11/2025.
//

import Foundation
import FamilyControls
import ManagedSettings
import Combine

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var selectedActivityTokens: Set<ApplicationToken> = []
    @Published var selection: FamilyActivitySelection = FamilyActivitySelection()
    @Published var isBlocking: Bool = false
    
    private let authorizationCenter = AuthorizationCenter.shared
    private let storageKey = "screenTimeActivitySelection"
    private let store = ManagedSettingsStore()
    
    init() {
        authorizationStatus = authorizationCenter.authorizationStatus
        loadSelectedTokens()
    }
    
    func requestAuthorization() async {
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
        } catch {
            print("Screen Time authorization error: \(error)")
            authorizationStatus = authorizationCenter.authorizationStatus
        }
    }
    
    func saveSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        selectedActivityTokens = newSelection.applicationTokens
        
        // FamilyActivitySelection is Codable, so we can persist it
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(newSelection)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to save Screen Time selection: \(error)")
        }
    }
    
    private func loadSelectedTokens() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let loadedSelection = try decoder.decode(FamilyActivitySelection.self, from: data)
            selection = loadedSelection
            selectedActivityTokens = loadedSelection.applicationTokens
        } catch {
            print("Failed to load Screen Time selection: \(error)")
        }
    }
    
    func clearSelectedTokens() {
        selectedActivityTokens.removeAll()
        selection = FamilyActivitySelection()
        UserDefaults.standard.removeObjectKey(storageKey)
        // Also unblock when clearing
        unblockApps()
    }
    
    // MARK: - App Blocking
    
    /// Updates app blocking based on the allowed state
    /// - Parameter isAllowed: true if the device is in an allowed state (e.g., user is moving)
    func updateBlocking(isAllowed: Bool) {
        if isAllowed {
            unblockApps()
        } else {
            blockApps()
        }
    }
    
    /// Blocks all selected apps
    func blockApps() {
        guard !selectedActivityTokens.isEmpty else {
            isBlocking = false
            return
        }
        
        store.shield.applications = selectedActivityTokens
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
            selection.categoryTokens
        )
        store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.specific(
            selection.categoryTokens
        )
        
        isBlocking = true
        print("Apps blocked: \(selectedActivityTokens.count) apps")
    }
    
    /// Unblocks all apps
    func unblockApps() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        
        isBlocking = false
        print("Apps unblocked")
    }
}

extension UserDefaults {
    func removeObjectKey(_ key: String) {
        removeObject(forKey: key)
    }
}

