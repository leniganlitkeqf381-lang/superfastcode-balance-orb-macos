import Foundation

enum Metric: String, CaseIterable {
    case weekly, plan, wallet
    var title: String {
        switch self { case .weekly: return "本周剩余"; case .plan: return "套餐剩余"; case .wallet: return "充值剩余" }
    }
}

struct Balance {
    let remaining: Double
    let total: Double?
    var percent: Double? {
        guard let total, total.isFinite, total > 0, remaining.isFinite else { return nil }
        return min(100, max(0, remaining / total * 100))
    }
    var percentText: String {
        guard let percent else { return "无额度" }
        if percent > 0 && percent < 1 { return "<1%" }
        return String(format: "%.0f%%", percent)
    }
    var credits: String { String(format: "%.2f", remaining / 100) }
}

struct QuotaSnapshot {
    let weekly: Balance
    let plan: Balance
    let wallet: Balance
    let available: Double
    let nextRelease: String?
    let expires: String?
    let fetchedAt: Date
    func balance(_ metric: Metric) -> Balance {
        switch metric { case .weekly: return weekly; case .plan: return plan; case .wallet: return wallet }
    }
    // Uses the production console's iy/ay/oy calculations, verified 2026-09-20.
    // A missing denominator stays unknown; it is never invented from current balance.
    init(account: [String: Any], now: Date = Date()) throws {
        guard let b = account["credit_breakdown"] as? [String: Any] else { throw QuotaError.schema }
        func number(_ name: String, required: Bool = true) throws -> Double? {
            guard let raw = b[name] else {
                if required { throw QuotaError.schema }; return nil
            }
            guard let n = raw as? NSNumber,
                  CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                  n.doubleValue >= 0 else { throw QuotaError.schema }
            return n.doubleValue
        }
        let available = try number("available_cents")!
        let total = try number("plan_total_cents")!
        let released = try number("plan_remaining_released_cents")!
        let pending = try number("plan_pending_cents")!
        let planLeft = min(total, try number("plan_remaining_cents", required: false) ?? (released + pending))
        let usable = min(released, planLeft)
        let weekRelease = try number("current_week_release_cents")!
        let weekLeft = weekRelease <= 0 ? usable : min(usable, weekRelease)
        let weekTotal = max(weekLeft, weekRelease, floor(total / 4))
        let walletLeft = min(available, try number("wallet_cents")!)
        let walletTotal = try number("wallet_total_cents", required: false)
        self.weekly = Balance(remaining: weekLeft, total: weekTotal)
        self.plan = Balance(remaining: planLeft, total: total)
        self.wallet = Balance(remaining: walletLeft, total: walletTotal.map { max($0, walletLeft) })
        self.available = available
        self.nextRelease = b["next_release_at"] as? String
        self.expires = account["subscription_expires_at"] as? String
        self.fetchedAt = now
    }
}
import CoreFoundation
enum QuotaError: Error { case schema }
