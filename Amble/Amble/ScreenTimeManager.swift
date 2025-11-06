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
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined
    @Published var selectedActivityTokens: Set<ApplicationToken> = []
    @Published var selection: FamilyActivitySelection = FamilyActivitySelection()
    
    private let authorizationCenter = AuthorizationCenter.shared
    private let storageKey = "screenTimeActivitySelection"
    
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
    }
}

extension UserDefaults {
    func removeObjectKey(_ key: String) {
        removeObject(forKey: key)
    }
}

