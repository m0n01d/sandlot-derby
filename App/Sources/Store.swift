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
    ///
    /// #47: `.failed` used to cover every way signing or restoring could fail, so the card said
    /// `NO CONNECTION` for a missing App Store Connect record just as it did for an actual
    /// network drop — Dwight, from an iPad, on the restore path: "The Show restore makes me
    /// login and i get No Connection. is that normal?" It was normal, but the card was lying
    /// about why. Split into the real causes below; nothing here is a sale word.
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
        /// A network failure and nothing else: `StoreKitError.networkError`, a bare `URLError`.
        case noConnection
        /// The store answered, but there is nothing to sell here: no product after a load that
        /// did not throw (no app record, no `show.contract` in App Store Connect, the Paid Apps
        /// agreement unsigned), `StoreKitError.notAvailableInStorefront`, `.notEntitled`,
        /// `.unsupported`, any `Product.PurchaseError`, an unverified transaction, or a system
        /// error StoreKit itself could not explain.
        case notAvailable
        /// `AppStore.sync()` came back clean and `currentEntitlements` is still empty: there was
        /// genuinely nothing to restore, not a failure.
        case nothingToRestore
    }

    private(set) var isEntitled: Bool
    private(set) var phase: Phase = .idle
    private(set) var product: Product?
    /// Why `product` is nil, recorded when `loadProduct()` runs so `sign()` can say the right
    /// thing about it later rather than treating every empty `product` as the same kind of
    /// nothing (#47). Nil once a product has loaded.
    private var productLoadFailure: Phase?

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
        if let forced = Self.debugCardPhase { phase = forced }
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
    /// of it has something to say. `-cardphase` (DEBUG) is the one thing that overrides this: a
    /// forced phase is what the card was put up to show, and `reset()` calls this on every
    /// presentation, so without the guard a screenshot run's own phase would never survive the
    /// card's first frame (#47).
    func clearPhase() {
        #if DEBUG
        if Self.debugCardPhase != nil { return }
        #endif
        if phase != .purchasing { phase = .idle }
    }

    // MARK: - The price

    /// The price as the card should draw it: the store's own localized `displayPrice` when the
    /// **5×7** face has every glyph in it — that is the face the card draws the price in — and
    /// the ISO code with the number when it does not (`BRL 14.90`). Nil when the store has not
    /// answered, which is when there is no store.
    var priceText: String? {
        guard let product else { return Self.placeholderPrice }
        let display = product.displayPrice
        if PixelCanvas.hasGlyphs5(for: display) { return display }
        return isoPriceText
    }

    /// The price the stats board draws: always the ISO code and the number, never a symbol. The
    /// board's rows are 7 px apart and its whole grammar is the 3×5 face, which has no `$` — so
    /// rather than mix faces in one row, that row says `USD 1.99` and is unambiguous everywhere.
    var boardPriceText: String? {
        guard product != nil else { return Self.placeholderBoardPrice }
        return isoPriceText
    }

    private var isoPriceText: String? {
        guard let product else { return nil }
        let amount = NSDecimalNumber(decimal: product.price).doubleValue
        return "\(product.priceFormatStyle.currencyCode) \(String(format: "%.2f", amount))"
    }

    /// Loads the product and, if there isn't one, records *why* — a thrown error is a real
    /// failure (network, or something StoreKit itself refused), while an empty list from a call
    /// that did not throw means the store answered and there is simply nothing to sell (no app
    /// record, no `show.contract`, the Paid Apps agreement unsigned) (#47).
    private func loadProduct() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
            productLoadFailure = product == nil ? .notAvailable : nil
        } catch {
            product = nil
            productLoadFailure = Self.phase(for: error)
        }
    }

    /// Sorts a thrown `StoreKitError`/`Product.PurchaseError`/anything else into one plain word
    /// (#47). Only a real network failure gets `NO CONNECTION`; everything StoreKit itself
    /// refused, or could not explain, is `NOT AVAILABLE` — there is no third bucket honest enough
    /// to put an unknown error in.
    private static func phase(for error: Error) -> Phase {
        if let skError = error as? StoreKitError {
            switch skError {
            case .networkError: return .noConnection
            case .userCancelled: return .cancelled
            case .notAvailableInStorefront, .notEntitled, .unsupported, .systemError, .unknown:
                return .notAvailable
            @unknown default: return .notAvailable
            }
        }
        if error is URLError { return .noConnection }
        if error is Product.PurchaseError { return .notAvailable }
        return .notAvailable
    }

    // MARK: - Signing, and getting it back

    /// Slicing the dotted line lands here: the system purchase sheet, and then one of the words
    /// the card knows. Success says nothing — `onEntitlementChange` cuts the card away.
    func sign() async {
        guard phase != .purchasing else { return }
        // No product: whatever `loadProduct()` found out about why, since a bare nil could be a
        // dropped network call or a store that answered "no such thing" (#47).
        guard let product else { phase = productLoadFailure ?? .notAvailable; return }
        phase = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let result):
                // An unverified transaction is not a purchase, and it is not a network problem
                // either — the store answered, StoreKit just would not vouch for it.
                guard let transaction = Self.verified(result) else { phase = .notAvailable; return }
                await transaction.finish()
                phase = .idle
                await refreshEntitlements()
            case .pending:
                phase = .pending
            case .userCancelled:
                phase = .cancelled
            @unknown default:
                phase = .notAvailable
            }
        } catch {
            phase = Self.phase(for: error)
        }
    }

    /// `RESTORE` in the corner. Entitlements are read at every launch anyway, so this is almost
    /// always a no-op; the word is there because App Review requires it.
    func restore() async {
        guard phase != .purchasing else { return }
        phase = .purchasing
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            // `sync()` itself did not throw: the store answered. Whether there was anything to
            // restore is a separate question, and "nothing" is not a failure (#47).
            phase = isEntitled ? .idle : .nothingToRestore
        } catch StoreKitError.userCancelled {
            phase = .cancelled
        } catch {
            phase = Self.phase(for: error)
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
        if arguments.contains(where: { $0 == "-autoslice" || $0 == "-nosave" || $0 == "-park"
            || $0 == "-streak" || $0 == "-replay" || $0 == "-replayscreen"
            || $0 == "-warmup" || $0 == "-warmupcard" || $0 == "-records" }) { return true }
        return nil
    }()

    /// `-cardphase <name>`, with `-contract`: force the card to one particular phase for a
    /// screenshot, since none of `NO CONNECTION` / `NOT AVAILABLE` / `NOTHING TO RESTORE` /
    /// `CANCELLED` / `PENDING` can be reached for real under `simctl` (#47) — there is no store
    /// at all, so `sign()`/`restore()` never run and never produce most of these on their own.
    /// Not on `forcedEntitlement`'s robot list: the whole point is to reach the card, which only
    /// a non-entitled run offers, so it must go on being stopped at the paywall like `-contract`
    /// already is.
    static let debugCardPhase: Phase? = {
        let args = arguments
        guard let i = args.firstIndex(of: "-cardphase"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "noconnection": return .noConnection
        case "notavailable": return .notAvailable
        case "nothingtorestore": return .nothingToRestore
        case "cancelled": return .cancelled
        case "pending": return .pending
        default: return nil
        }
    }()

    /// Launched by `simctl` there is no `.storekit` configuration and so no store at all:
    /// `Product.products` comes back empty and the card would have no price to draw. A
    /// `-contract` screenshot run gets this instead, and since #47 that reads as `NOT AVAILABLE`
    /// — the store answered with nothing to sell, which under `simctl` is the honest word for it.
    private static var placeholderPrice: String? {
        hasContractArgument ? "$1.99" : nil
    }

    private static var placeholderBoardPrice: String? {
        hasContractArgument ? "USD 1.99" : nil
    }

    private static var hasContractArgument: Bool {
        arguments.contains { $0 == "-contract" || $0 == "-declined" }
    }
    #else
    private static let placeholderPrice: String? = nil
    private static let placeholderBoardPrice: String? = nil
    #endif
}
