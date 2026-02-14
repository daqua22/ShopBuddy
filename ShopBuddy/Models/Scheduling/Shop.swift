import Foundation

struct Shop: Identifiable, Hashable {
    var id: String
    var name: String
    var timezoneIdentifier: String

    static var active: Shop {
        Shop(
            id: ShopContext.activeShopID,
            name: "PrepIt",
            timezoneIdentifier: ShopContext.activeTimeZone.identifier
        )
    }
}
