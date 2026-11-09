import Foundation
@preconcurrency import IOKit.hid

/// A 2.4 GHz receiver revision of the CITLLA E510 that the app recognises.
///
/// The mouse's extra buttons arrive as keystrokes from the receiver's keyboard
/// interface, so `MouseKeyTagger` has to know which HID devices belong to the
/// mouse before it can attribute those keystrokes. The E510 has shipped with
/// more than one receiver, each with its own vendor and product ID, so this is
/// a list rather than a single pair.
///
/// Matching stays on exact IDs on purpose. Matching a whole vendor would also
/// match other devices that share the vendor (the HS6209 receiver chip uses a
/// generic vendor ID), and their keystrokes would be remapped as if they came
/// from the mouse.
struct MouseReceiver: Identifiable, Hashable, Sendable {
    let vendorID: Int
    let productID: Int
    /// The product name the receiver reports to macOS.
    let name: String

    var id: String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    var idDescription: String {
        String(format: "VID 0x%04X · PID 0x%04X", vendorID, productID)
    }

    /// Every receiver revision the app knows. Add one line here when a new
    /// revision shows up; the key tagger and Diagnostics both follow.
    static let known: [MouseReceiver] = [
        MouseReceiver(vendorID: 0x1EA7, productID: 0x66, name: "2.4G Mouse"),
        MouseReceiver(vendorID: 0x32C2, productID: 0x12, name: "2.4G Wireless Receiver")
    ]

    /// One exact vendor/product pair per known receiver, for `IOHIDManager`.
    static var matchingDictionaries: [[String: Any]] {
        known.map { receiver in
            [
                kIOHIDVendorIDKey: receiver.vendorID,
                kIOHIDProductIDKey: receiver.productID
            ]
        }
    }

    /// One vendor-only match per distinct vendor.
    ///
    /// Diagnostics uses these so an unrecognised revision from a known vendor
    /// still appears in the device list. The key tagger must not use them.
    static var vendorMatchingDictionaries: [[String: Any]] {
        Set(known.map(\.vendorID)).sorted().map { [kIOHIDVendorIDKey: $0] }
    }

    static func receiver(vendorID: Int, productID: Int) -> MouseReceiver? {
        known.first { $0.vendorID == vendorID && $0.productID == productID }
    }
}
