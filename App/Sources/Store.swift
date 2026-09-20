import Foundation
import StoreKit

/// The one purchase (DESIGN.md §16): `show.contract`, non-consumable, Family Sharing on, bought
/// once and never again. StoreKit 2 only — no server, no receipt parsing, no analytics. The
/// entitlement is whatever `Transaction.currentEntitlements` says: read silently at every launch
/// and watched afterwards by `Transaction.updates`, which is how a purchase made on another
/// device arrives and how a refund is heard about.
///
/// A cached flag in `UserDefaults` answers `isEntitled` before StoreKit has replied, so an
/// entitled player who opens the app on a plane starts in The Show. It only ever mirrors what
/// StoreKit last said and is never the source of truth.
///
/// Nothing here decides anything about the game. It reports an entitlement and a price; the
/// ceiling is `GameController`'s business and the machine's.
@MainActor
final class Store {
    /// The only product there will ever be. §15 rules out a second one.
    static let productID = "show.contract"

    /// What the contract card has to say for itself right now. Never a countdown, a badge or a
    /// banner: one plain word, or nothing.
    enum Phase: Equatable {
        /// The card as it is offered, and the card after a purchase has been asked for and
        /// answered well: nothing extra is said.
        case idle
        /// The system sheet is up.
        case purchasing
        /// Ask to Buy: a parent has to approve it. The player goes back to Triple-A and the
        /// transaction lands whenever it lands.
        case pending
        case cancelled
        /// No store, no network, or a transaction that did not verify.
        case failed
    }

    private(set) var isEntitled: Bool
    private(set) var phase: Phase = .idle
    private(set) var product: Product?

    /// Called on the main actor whenever `isEntitled` changes, in either direction: signed,
    /// restored, a pending purchase landing, a purchase made on another device, a refund.
    var onEntitlementChange: (() -> Void)?

    private var updates: Task<Void, Never>?

    /// Mirrors `SaveStore`: a run that does not write the career does not write the entitlement
    /// it was launched with either, so a debug run cannot leak into a real one.
    private static let cacheKey = "contract.entitled.v1"
    private static var cacheEnabled: Bool { SaveStore.isEnabled }

    init() {
        #if DEBUG
        if let forced = Self.forcedEntitlement {
            isEntitled = forced
            return
        }
        #endif
        isEntitled = Self.cacheEnabled && UserDefaults.standard.bool(forKey: Self.cacheKey)
    }

    deinit { updates?.cancel() }

    /// Start listening before asking anything, so a transaction that lands mid-launch is not
    /// missed. Called once, from `GameController.init`.
    func start() async {
        listen()
        await loadProduct()
        await refreshEntitlements()
    }

    /// A card put up again — from the stats board, a career later — says nothing until this run
    /// of it has something to say.
    func clearPhase() {
        if phase != .purchasing { phase = .idle }
    }

    // MARK: - The price

    /// The price as the card should draw it: the store's own localized `displayPrice` when the
    /// 3×5 face has every glyph in it, and the ISO code with the number when it does not
    /// (`BRL 14.90`). Nil when the store has not answered, which is when there is no store.
    var priceText: String? {
        guard let product else { return Self.placeholderPrice }
        let display = product.displayPrice
        if PixelCanvas.hasGlyphs(for: display) { return display }
        let amount = NSDecimalNumber(decimal: product.price).doubleValue
        return "\(product.priceFormatStyle.currencyCode) \(String(format: "%.2f", amount))"
    }

    private func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    // MARK: - Signing, and getting it back

    /// Slicing the dotted line lands here: the system purchase sheet, and then one of the words
    /// the card knows. Success says nothing — `onEntitlementChange` cuts the card away.
    func sign() async {
        guard phase != .purchasing else { return }
        guard let product else { phase = .failed; return }
        phase = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard let transaction = Self.verified(result) else { phase = .failed; return }
                await transaction.finish()
                phase = .idle
                await refreshEntitlements()
            case .pending:
                phase = .pending
            case .userCancelled:
                phase = .cancelled
            @unknown default:
                phase = .failed
            }
        } catch {
            phase = .failed
        }
    }

    /// `RESTORE` in the corner. Entitlements are read at every launch anyway, so this is almost
    /// always a no-op; the word is there because App Review requires it.
    func restore() async {
        guard phase != .purchasing else { return }
        phase = .purchasing
        do {
            try await AppStore.sync()
            phase = .idle
            await refreshEntitlements()
        } catch StoreKitError.userCancelled {
            phase = .cancelled
        } catch {
            phase = .failed
        }
    }

    /// What the player owns, as of now. Revoked purchases are already absent from
    /// `currentEntitlements`; `revocationDate` is checked anyway.
    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = Self.verified(result),
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            entitled = true
        }
        setEntitled(entitled)
    }

    /// Purchases made elsewhere, pending purchases landing, and refunds.
    private func listen() {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if let transaction = Self.verified(update) { await transaction.finish() }
                guard let self else { return }
                await self.refreshEntitlements()
            }
        }
    }

    /// An unverified transaction is not a purchase. There is no server to ask, so the only
    /// honest answer is to ignore it.
    private static func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction): return transaction
        case .unverified: return nil
        }
    }

    private func setEntitled(_ value: Bool) {
        #if DEBUG
        if Self.forcedEntitlement != nil { return }
        #endif
        if Self.cacheEnabled { UserDefaults.standard.set(value, forKey: Self.cacheKey) }
        guard value != isEntitled else { return }
        isEntitled = value
        onEntitlementChange?()
    }

    // MARK: - Dev launch arguments

    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    /// `-contract` offers the card: Triple-A, not entitled, nothing yet declined. `-entitled`
    /// forces the other side. `-autoslice` and `-nosave` are robot runs that must not be stopped
    /// at park 3, so they count as entitled. Nil means "ask the store", the shipping path.
    static let forcedEntitlement: Bool? = {
        if arguments.contains(where: { $0 == "-contract" || $0 == "-declined" }) { return false }
        if arguments.contains("-entitled") { return true }
        if arguments.contains(where: { $0 == "-autoslice" || $0 == "-nosave" }) { return true }
        return nil
    }()

    /// Launched by `simctl` there is no `.storekit` configuration and so no store at all:
    /// `Product.products` comes back empty and the card would have no price to draw. A
    /// `-contract` screenshot run gets this instead. Signing still fails, with `NO CONNECTION`.
    private static var placeholderPrice: String? {
        arguments.contains(where: { $0 == "-contract" || $0 == "-declined" }) ? "$1.99" : nil
    }
    #else
    private static let placeholderPrice: String? = nil
    #endif
}
