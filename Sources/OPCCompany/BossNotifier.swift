#if canImport(UserNotifications)
// v0.16.0 "the office calls" — the thin macOS delivery shell. The CORE
// owns every decision worth testing (what to say: CompanyStore+Alerts;
// what was already said: BossAlertDeduper); this file only carries the
// words to the system notification center, behind guards, and goes
// silently to work when the boss declines permission — notifications
// are an enhancement, never a dependency. Nothing here can move a
// single company byte.

import UserNotifications
import OPCCompanyCore

@MainActor
final class BossNotifier {
    private let store: CompanyStore
    private let deduper: BossAlertDeduper
    private var timer: Timer?
    /// production: UserDefaults.standard; tests inject their own
    private static var center: UNUserNotificationCenter? {
        UNUserNotificationCenter.current()
    }

    init(store: CompanyStore, defaults: UserDefaults) {
        self.store = store
        self.deduper = BossAlertDeduper(defaults: defaults)
    }

    /// Called once from the app scene. Polls the alert door every
    /// minute; the system gates delivery behind its own authorization
    /// prompt, and a denial just means this loop keeps quietly doing
    /// nothing.
    func start() {
        guard timer == nil else { return }
        requestAuthorizationOnce()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private var authorizationAsked = false
    private func requestAuthorizationOnce() {
        guard !authorizationAsked else { return }
        authorizationAsked = true
        Self.center?.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // the boss decides; granted or not, the poll loop stays honest
        }
    }

    /// One poll: door → deduper → deliver. Testable without UserNotifications
    /// by calling the pieces; kept total so production stays trivial.
    func poll() {
        let alerts = store.bossAlerts()
        // handled causes leave the doors — prune the stored ids so the
        // deduper's set cannot grow forever
        deduper.prune(keeping: Set(alerts.map(\.id)))
        let fresh = deduper.partition(alerts)
        deliver(fresh)
    }

    private func deliver(_ alerts: [CompanyStore.BossAlert]) {
        guard !alerts.isEmpty else { return }
        let center = Self.center
        for a in alerts {
            let content = UNMutableNotificationContent()
            content.title = a.title
            content.body = a.body
            let request = UNNotificationRequest(
                identifier: "opc.bossAlert.\(a.id)", content: content, trigger: nil)
            center?.add(request)
        }
    }
}
#endif
