import Foundation
import StoreKit

/// Gates the Local Chat HUD behind a one-time purchase.
///
/// - App Store build (compiled with `-DAPPSTORE`): the HUD is unlocked by a
///   non-consumable IAP and this store drives StoreKit 2.
/// - Direct DMG build (no `APPSTORE` flag): the HUD ships unlocked, since that
///   distribution is a separate paid download.
@MainActor
final class LLMEntitlementStore: ObservableObject {
    /// Non-consumable product configured in App Store Connect.
    static let productID = "com.cribble.reader.llm.unlock"

    @Published private(set) var isUnlocked: Bool
    @Published private(set) var product: Product?
    @Published private(set) var purchaseInFlight = false
    @Published var lastError: String?

    /// True only for builds that actually sell the unlock, so the UI can hide
    /// purchase affordances on the DMG build.
    let isPurchaseGated: Bool

    private var updatesTask: Task<Void, Never>?

    init() {
        #if APPSTORE
        isPurchaseGated = true
        isUnlocked = false
        startStoreKit()
        #else
        isPurchaseGated = false
        isUnlocked = true
        #endif
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Localized price string for buttons, e.g. "$6.99". Falls back to a plain
    /// label until the product loads.
    var displayPrice: String {
        product?.displayPrice ?? "$6.99"
    }

    /// Buys the unlock. No-op on builds that aren't purchase-gated.
    func purchase() async {
        #if APPSTORE
        await purchaseGated()
        #endif
    }

    /// Restores a prior purchase. No-op on builds that aren't purchase-gated.
    func restore() async {
        #if APPSTORE
        await restoreGated()
        #endif
    }

    #if APPSTORE
    private func startStoreKit() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update)
            }
        }
        Task { await refresh() }
    }

    /// Loads the product and re-checks current entitlements.
    func refresh() async {
        await loadProduct()
        await updateEntitlement()
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func purchaseGated() async {
        guard let product else {
            await loadProduct()
            guard product != nil else {
                lastError = "The unlock isn't available right now. Try again in a moment."
                return
            }
            return await purchaseGated()
        }

        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    isUnlocked = true
                } else {
                    lastError = "Purchase couldn't be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func restoreGated() async {
        do {
            try await AppStore.sync()
            await updateEntitlement()
            if !isUnlocked {
                lastError = "No previous purchase was found on this Apple ID."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func updateEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                isUnlocked = true
                return
            }
        }
        isUnlocked = false
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        if transaction.productID == Self.productID {
            isUnlocked = transaction.revocationDate == nil
        }
        await transaction.finish()
    }
    #endif
}
