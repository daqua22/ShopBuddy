import Foundation

enum ShopContext {
    static let activeShopIDKey = "activeShopID"
    static let activeTimeZoneIDKey = "activeShopTimeZoneID"
    static let defaultShopID = "default-shop"

    static var activeShopID: String {
        let stored = UserDefaults.standard.string(forKey: activeShopIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? defaultShopID : stored
    }

    static var activeTimeZone: TimeZone {
        if let identifier = UserDefaults.standard.string(forKey: activeTimeZoneIDKey),
           let zone = TimeZone(identifier: identifier) {
            return zone
        }
        return .current
    }
}

