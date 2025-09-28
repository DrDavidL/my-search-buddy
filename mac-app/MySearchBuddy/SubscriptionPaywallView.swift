import SwiftUI

struct SubscriptionPaywallView: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)
            Text("Unlock My Search Buddy")
                .font(.title2)
                .bold()
            Text("Start your 30-day free trial to keep automatic indexing, cloud awareness, and continuous feature updates.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
            if let product = purchaseManager.subscriptionProduct {
                Text("30 days free, then \(product.displayPrice)/year. Cancel anytime.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("Loading subscription details…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            VStack(spacing: 12) {
                Button {
                    Task { await purchaseManager.purchaseSubscription() }
                } label: {
                    HStack {
                        if purchaseManager.isProcessing { ProgressView() }
                        Text(purchaseManager.isProcessing ? "Processing…" : "Start Free Trial")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(purchaseManager.isProcessing || purchaseManager.subscriptionProduct == nil)

                Button("Restore Purchase") {
                    Task { await purchaseManager.restorePurchases() }
                }
                .buttonStyle(.bordered)
            }
            if let error = purchaseManager.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .shadow(radius: 16)
        .padding()
    }
}

#Preview {
    SubscriptionPaywallView()
        .environmentObject(PurchaseManager())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.4))
}
