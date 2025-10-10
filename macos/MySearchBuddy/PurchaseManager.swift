import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published private(set) var subscriptionActive = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isReady = false
    @Published var isProcessing = false
    @Published var lastError: String?

    private let subscriptionProductID = "com.mysearchbuddy.subscription.yearly"
    private var hasStarted = false
    private var updatesTask: Task<Void, Never>? = nil

    // Debug: Set to true to bypass paywall for local testing
    // Set to TRUE for TestFlight (free testing), FALSE for App Store release
    private let debugBypassPaywall = true

    init() {
        NSLog("[PurchaseManager] Initializing")
    }

    deinit {
        updatesTask?.cancel()
    }

    func start() async {
        NSLog("[PurchaseManager] start() called, hasStarted=%d, debugBypassPaywall=%d", hasStarted, debugBypassPaywall)
        guard !hasStarted else {
            NSLog("[PurchaseManager] Already started")
            // Don't refresh entitlements if debug bypass is enabled
            if !debugBypassPaywall {
                NSLog("[PurchaseManager] Refreshing entitlements")
                await refreshEntitlements()
            }
            return
        }
        hasStarted = true

        // Debug bypass for local testing
        if debugBypassPaywall {
            NSLog("[PurchaseManager] Debug bypass enabled, setting subscriptionActive=true, isReady=true")
            subscriptionActive = true
            isReady = true
            NSLog("[PurchaseManager] Debug bypass complete")
            return
        }

        await loadProducts()
        await refreshEntitlements()
        listenForTransactions()
    }

    var subscriptionProduct: Product? {
        products.first
    }

    func purchaseSubscription() async {
        guard !isProcessing else { return }
        guard let product = subscriptionProduct else {
            lastError = "Subscription not available yet."
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                await handle(transactionResult: verificationResult)
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase pending approval."
            @unknown default:
                lastError = "Unknown purchase state."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: [subscriptionProductID])
            products = storeProducts.sorted(by: { $0.displayName < $1.displayName })
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == subscriptionProductID,
                   transaction.revocationDate == nil,
                   (transaction.expirationDate ?? .distantFuture) > Date() {
                    active = true
                }
            case .unverified:
                continue
            }
        }
        subscriptionActive = active
        isReady = true
    }

    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                await self.handle(transactionResult: update)
            }
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        switch transactionResult {
        case .verified(let transaction):
            if transaction.productID == subscriptionProductID {
                subscriptionActive = transaction.revocationDate == nil && (transaction.expirationDate ?? .distantFuture) > Date()
            }
            await transaction.finish()
        case .unverified(_, let error):
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }
}
