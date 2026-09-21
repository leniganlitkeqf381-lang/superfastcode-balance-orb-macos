import Foundation
@main struct Tests {
    static func main() throws {
        // Synthetic fixtures, never real account data.
        let base: [String:Any] = ["available_cents": 19250, "plan_total_cents": 100000,
            "plan_remaining_cents": 93250, "plan_remaining_released_cents":18250,
            "plan_pending_cents":75000, "current_week_release_cents":25000,
            "wallet_cents":1000, "wallet_total_cents":5000]
        func parse(_ changes: [String:Any] = [:]) throws -> QuotaSnapshot {
            try QuotaSnapshot(account: ["credit_breakdown":base.merging(changes) { _, new in new }])
        }
        let standard = try parse()
        precondition(standard.weekly.percent == 73)
        precondition(standard.plan.percent == 93.25)
        precondition(standard.wallet.percent == 20)
        let empty = try parse(["plan_remaining_cents":75000, "plan_remaining_released_cents":0])
        precondition(empty.weekly.percent == 0 && empty.plan.percent == 75)
        let rollover = try parse(["plan_remaining_released_cents":25000,"plan_remaining_cents":75000,"plan_pending_cents":50000])
        precondition(rollover.weekly.percent == 100)
        let noPlan = try parse(["plan_total_cents":0,"plan_remaining_cents":0,"plan_remaining_released_cents":0,"plan_pending_cents":0,"current_week_release_cents":0])
        precondition(noPlan.weekly.percent == nil && noPlan.plan.percent == nil)
        var missingWalletTotal = base; missingWalletTotal.removeValue(forKey:"wallet_total_cents")
        let unknownWallet = try QuotaSnapshot(account:["credit_breakdown":missingWalletTotal])
        precondition(unknownWallet.wallet.total == nil)
        let clamped = try parse(["wallet_cents":999999])
        precondition(clamped.wallet.remaining == standard.available)
        var malformed = base; malformed.removeValue(forKey:"plan_total_cents")
        do { _ = try QuotaSnapshot(account:["credit_breakdown":malformed]); fatalError("Must reject missing denominator") } catch QuotaError.schema {}
        for bad: Any in ["unknown", true, -1, Double.nan, Double.infinity] {
            do { _ = try parse(["available_cents":bad]); fatalError("Must reject malformed data") } catch QuotaError.schema {}
        }
        precondition(Balance(remaining: 1,total:10000).percentText == "<1%")
        precondition(Balance(remaining: 0,total:10000).percentText == "0%")
        precondition(Balance(remaining: 100,total:0).percent == nil)
        print("PASS: weekly / plan / wallet, zero, reset, missing data, invalid numbers and low balance.")
    }
}
