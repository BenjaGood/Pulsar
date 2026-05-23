//
//  OuraKeychainStore.swift
//  Pulsar
//

import Foundation
import Security

protocol OuraTokenStorage {
    func loadToken() throws -> OuraStoredToken?
    func saveToken(_ token: OuraStoredToken) throws
    func deleteToken() throws
}

enum OuraKeychainError: LocalizedError, Equatable {
    case encodeFailed
    case decodeFailed
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not prepare Oura credentials for secure storage."
        case .decodeFailed:
            return "Stored Oura credentials could not be read."
        case .unexpectedStatus(let status):
            return "Keychain returned status \(status) while handling Oura credentials."
        }
    }
}

final class OuraKeychainTokenStore: OuraTokenStorage {
    private let service: String
    private let account: String

    init(
        service: String = "aetherial.Pulsar.oura.oauth",
        account: String = "current-user"
    ) {
        self.service = service
        self.account = account
    }

    func loadToken() throws -> OuraStoredToken? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw OuraKeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let token = try? JSONDecoder().decode(OuraStoredToken.self, from: data) else {
            throw OuraKeychainError.decodeFailed
        }
        return token
    }

    func saveToken(_ token: OuraStoredToken) throws {
        guard let data = try? JSONEncoder().encode(token) else {
            throw OuraKeychainError.encodeFailed
        }

        var query = baseQuery()
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OuraKeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        throw OuraKeychainError.unexpectedStatus(status)
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OuraKeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class OuraInMemoryTokenStore: OuraTokenStorage {
    private var token: OuraStoredToken?

    init(token: OuraStoredToken? = nil) {
        self.token = token
    }

    func loadToken() throws -> OuraStoredToken? {
        token
    }

    func saveToken(_ token: OuraStoredToken) throws {
        self.token = token
    }

    func deleteToken() throws {
        token = nil
    }
}

