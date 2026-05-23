# Phase B — Paywall (Trial + Lifetime)

**Date:** 2026-05-23
**Author:** Marcel R. G. Berger
**Status:** Planned

---

## 1. Goal

Convert the App Store distribution into a freemium product:

- **Day 1–14**: full Pro trial — everything unlocked, no card needed
- **Day 15+ (no purchase)**: Free tier — core browsing stays usable, the Pro pillars (Mount, Sync, S3-to-S3) lock
- **Pro Lifetime** at €14.99 (one-time IAP) — unlocks every feature forever, no subscription

This is the classic "evaluate for two weeks → buy once, own forever" model. No subscription billing, no ongoing customer obligation, no auto-renew compliance overhead.

---

## 2. Tier matrix

| Capability | Trial (Day 1–14) | Free (Day 15+) | Pro |
|---|---|---|---|
| Unlimited accounts | ✓ | ✓ | ✓ |
| Browse buckets and objects | ✓ | ✓ | ✓ |
| Upload / Download (single + multipart) | ✓ | ✓ | ✓ |
| Drag-and-drop in / out | ✓ | ✓ | ✓ |
| Delete / Rename / Create folder | ✓ | ✓ | ✓ |
| Quick Look preview | ✓ | ✓ | ✓ |
| Connection test, biometric reveal | ✓ | ✓ | ✓ |
| Test Connection | ✓ | ✓ | ✓ |
| **Mount as Finder drive (File Provider)** | ✓ | — | ✓ |
| **S3-to-S3 / S3-to-Azure copy and move** | ✓ | — | ✓ |
| **Mirror / sync jobs (scheduled)** | ✓ | — | ✓ |
| **Menubar background mode** | ✓ | — | ✓ |
| Localised in 10 languages | ✓ | ✓ | ✓ |

The four Pro pillars (Mount, Sync, S3-to-S3, Menubar) are the things that drive ongoing value — they sit perfectly behind the wall. The day-to-day browsing stays in the free tier so the app remains genuinely useful even without paying.

---

## 3. IAP product

| | |
|---|---|
| **Product ID** | `za.co.digitalfreedom.bucketeer.pro.lifetime` |
| **Type** | Non-consumable (in-app purchase) |
| **Price tier** | Tier corresponding to €14.99 |
| **Family Sharing** | Enabled (single purchase covers the family) |
| **Subscription** | No |

Single product. Future: a `pro.lifetime.educational` discount tier if there's demand.

---

## 4. Entitlement state machine

Tracked at app launch and on every change to StoreKit transactions:

```
        ┌──────────────┐
        │  TrialActive │  ── elapsed > 14 days ──▶ ┌──────┐
        │ (T-installed │                            │ Free │
        │  + N <= 14)  │                            └──────┘
        └──────────────┘                                │
              │                                         │
              │ user purchases Pro                       │ user purchases Pro
              ▼                                         ▼
        ┌──────────────┐                          ┌──────────┐
        │     Pro      │ ◀─────────────────────── │    Pro   │
        └──────────────┘                          └──────────┘
```

Three observable states: `.trial(daysRemaining: Int)`, `.free`, `.pro`.

- **TrialActive**: trial start date persisted in UserDefaults on first launch; never reset
- **Free**: trial expired, no purchase
- **Pro**: `Transaction.currentEntitlements` contains the product ID and is unrevoked

---

## 5. Architecture

### 5.1 New service

```swift
@MainActor @Observable
final class EntitlementManager {
    enum State { case trial(daysRemaining: Int), free, pro }
    private(set) var state: State

    func refresh() async              // poll StoreKit + UserDefaults
    func purchasePro() async throws   // initiates the StoreKit purchase
    func restorePurchases() async throws
    func isUnlocked(_ feature: ProFeature) -> Bool
}

enum ProFeature: String, Sendable {
    case mountDrive
    case syncEngine
    case s3ToS3Copy
    case menubarBackground
}
```

### 5.2 Trial bookkeeping

```swift
extension EntitlementManager {
    private static let trialStartKey = "bucketeer.trial.start"
    private static let trialLength: TimeInterval = 14 * 24 * 60 * 60

    private func trialDaysRemaining() -> Int? {
        let defaults = UserDefaults.standard
        let start: Date
        if let existing = defaults.object(forKey: Self.trialStartKey) as? Date {
            start = existing
        } else {
            start = Date()
            defaults.set(start, forKey: Self.trialStartKey)
        }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, Self.trialLength - elapsed)
        guard remaining > 0 else { return nil }
        return Int(ceil(remaining / 86_400))
    }
}
```

Persisting the trial start in UserDefaults is the simplest viable approach. A determined user can reset it by deleting the app's preferences — that is acceptable for the price point and avoids server-side licensing infrastructure.

### 5.3 StoreKit integration

```swift
import StoreKit

extension EntitlementManager {
    func refresh() async {
        // Pro overrides everything
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result,
               txn.productID == AppConstants.proProductID,
               txn.revocationDate == nil {
                state = .pro
                return
            }
        }
        // Otherwise trial or free
        if let days = trialDaysRemaining() {
            state = .trial(daysRemaining: days)
        } else {
            state = .free
        }
    }

    func purchasePro() async throws {
        guard let product = try await Product.products(for: [AppConstants.proProductID]).first else {
            throw EntitlementError.productUnavailable
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified = verification {
                await refresh()
            }
        case .userCancelled, .pending:
            return
        @unknown default:
            return
        }
    }
}
```

Listen to `Transaction.updates` continuously so refunds and family-share changes propagate.

### 5.4 Feature gating

UI uses one helper:

```swift
@Environment(EntitlementManager.self) private var entitlement

if entitlement.isUnlocked(.mountDrive) {
    Button("Mount as Drive") { ... }
} else {
    Button("Mount as Drive") { paywall.show(.mountDrive) }
        .overlay(alignment: .topTrailing) {
            ProBadge()
        }
}
```

Gated entry points:
- File Provider mount toggle in the sidebar bucket context menu
- "New Sync Job" button in the Sync section
- S3-to-S3 copy/move target picker shows the upsell when the destination is on a different account/provider and the user is not Pro
- "Run in background" toggle in Settings

When a Free user taps a locked feature, the Paywall sheet opens instead of running the action.

### 5.5 Paywall sheet

```
┌──────────────────────────────────────────────────────────┐
│              Bucketeer Pro                                │
│                                                            │
│  Unlock the features that turn Bucketeer into a real     │
│  cloud workstation:                                       │
│                                                            │
│   ✓ Mount any bucket in Finder                            │
│   ✓ Background sync between any S3 or Azure location      │
│   ✓ Copy / mirror across providers and accounts           │
│   ✓ Menubar mode that keeps everything alive              │
│                                                            │
│  ┌──────────────────────────────────────────────────┐    │
│  │           Pro Lifetime — €14.99                  │    │
│  │      one-time purchase, no subscription          │    │
│  └──────────────────────────────────────────────────┘    │
│                                                            │
│           [   Restore Purchase   ]                        │
│                                                            │
│  Family Sharing enabled.  Terms · Privacy · Refund        │
└──────────────────────────────────────────────────────────┘
```

- Title, copy and bullets localised
- Big "Pro Lifetime — €14.99" button → `EntitlementManager.purchasePro()`
- "Restore Purchase" link → `EntitlementManager.restorePurchases()`
- Footer links to bundled Terms, Privacy, Refund Policy
- During an active trial, the sheet shows "X days of Pro trial remaining — buy now to skip the reminder"

### 5.6 Reminders (non-intrusive)

- A small Pro badge in the sidebar header for Free users — opens the paywall on click
- Settings → Pro tab shows current state and the same Buy button
- A one-time notification when the trial ends (in-app banner, not push)

No interstitial popups. No nag dialogs. The product is good enough that users either need the Pro features or they don't.

---

## 6. App Store Connect

- Create a non-consumable IAP: `za.co.digitalfreedom.bucketeer.pro.lifetime`, tier €14.99, Family Sharing on
- Add Bucketeer.storekit file for local testing
- Reference in the project's Scheme: `Run → Options → StoreKit Configuration`
- App Privacy Nutrition Label updated: "Purchase History" linked to identity for App Functionality (RevenueCat is **not** used; pure StoreKit)

---

## 7. Bundled docs delta

The existing legal bundle already includes the Refund Policy template. Bucketeer-specific tweaks for the EULA / Refund Policy:

- EULA §6 (Commercial Terms) — explicitly call out the 14-day trial and the €14.99 one-time price
- Refund Policy — reference Apple's standard App Store refund flow (`reportaproblem.apple.com`); the publisher does not process refunds directly
- Privacy Policy — disclose that purchase / transaction data is processed by Apple under their privacy policy; the publisher receives only aggregated payout reports

---

## 8. Sub-phases

| # | Slice | Effort | Deliverable |
|---|---|---|---|
| **B.1** | EntitlementManager + StoreKit + state machine + trial bookkeeping | 1 session | App boots in the right state, can simulate trial expiry via StoreKit config |
| **B.2** | Paywall sheet + Settings → Pro tab + sidebar Pro badge | 1 session | Free users can complete a purchase locally |
| **B.3** | Feature gating across Mount / Sync / S3-to-S3 / Menubar | 0.5 session | All gated entry points show the paywall when the user is Free |
| **B.4** | App Store Connect product, Bucketeer.storekit, scheme wiring, IAP testing | 0.5 session | TestFlight build with working IAP |
| **B.5** | Legal updates (EULA §6, Refund Policy reference, Privacy disclosure) | 0.5 session | App Store-ready legal bundle |
| **B.6** | Codex review + manual test matrix (trial → free → pro, restore, family share) | 0.5 session | Sign-off |

Total: ~4 sessions.

---

## 9. Roadmap placement

```
Phase 5 (done)
   ⇩
Phase A (Azure)            — needs §8 confirms
   ⇩
Phase 6 (Preview)
   ⇩
Phase 7 (Drag-and-Drop)
   ⇩
Phase 8 (Menubar)
   ⇩
Phase 9 (File Provider)
   ⇩
Phase 10 (Sync Engine)
   ⇩
Phase B (Paywall)          — this phase
   ⇩
Phase 11 (Localisation finalisation)
   ⇩
Phase 12 (Hardening + App Store metadata)
   ⇩
Ship v1.0 to TestFlight internal
```

Paywall sits **after** Phase 10 because the gated features must actually exist before they can be gated. Building the entitlement manager earlier is wasted churn if features land underneath it. Trial bookkeeping starts on the first launch of the shipped app, which is fine because no user is shipped until v1.0.

---

## 10. Open decisions

1. **Price tier**: €14.99 confirmed. Alternative tiers (€9.99 launch / €19.99 once popular) deferred.
2. **Family Sharing**: enabled — covers the "two-Mac household" case at no extra cost to publisher.
3. **Educational discount**: parked for v1.1.
4. **Trial reset on bundle re-install**: accepted. Users who delete and re-install get a fresh trial. The product is priced to make this not worth the friction.
5. **Refund handling**: deferred entirely to Apple's `reportaproblem.apple.com`.

*End of phase plan.*
