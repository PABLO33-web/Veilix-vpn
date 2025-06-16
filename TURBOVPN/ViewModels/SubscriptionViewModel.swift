import Foundation
import SwiftUI
import NetworkExtension
import SafariServices
import Security

// KeychainService встроен в SubscriptionViewModel
private class KeychainService {
    static let shared = KeychainService()
    
    private let trialKey = "com.veilix.vpn.trialUsed"
    
    private init() {}
    
    func saveTrialUsage() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: trialKey,
            kSecValueData as String: "true".data(using: .utf8)!
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("Error saving trial usage to Keychain: \(status)")
            return
        }
    }
    
    func hasUsedTrial() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: trialKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return false
        }
        
        return value == "true"
    }
}

class SubscriptionViewModel: ObservableObject {
    private let paymentService = PaymentService()
    private let vpnService = VPNService()
    
    @Published var isLoading = false
    @Published var paymentURL: PaymentURL?
    @Published var vpnConfig: String?
    @Published var vpnStatus: NEVPNStatus = .disconnected
    @Published var userStats: UserStats?
    @Published var showToast = false
    @Published var toastMessage = ""
    @Published var showSafariView = false
    @Published var safariURL: URL?
    @Published var currentOrderId: String? = nil
    @Published var currentSubscriptionDurationInDays: Int? = nil
    @Published var currentUserIdForPayment: String? = nil
    @Published var currentEmailForPayment: String? = nil
    
    // Добавляем ключ для хранения информации об использовании пробного периода
    private let userIdKey = "userId"
    
    var hasUsedTrial: Bool {
        get {
            KeychainService.shared.hasUsedTrial()
        }
        set {
            if newValue {
                KeychainService.shared.saveTrialUsage()
            }
        }
    }
    
    // Добавляем функцию проверки существующей подписки
    func checkExistingSubscription(userId: String) async throws -> String? {
        if let (config, _, _) = try await vpnService.checkSubscription(userId: userId) {
            return config
        }
        return nil
    }
    
    private func showTemporaryToast(_ message: String) {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.8)) {
                self.toastMessage = message
                self.showToast = true
            }
            
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды ожидания
            
            withAnimation(.easeInOut(duration: 0.8)) {
                self.showToast = false
            }
        }
    }
    
    func purchaseSubscription(_ subscription: Subscription) {
        Task {
            do {
                print("[SubscriptionViewModel] Starting subscription purchase for: \(subscription.name)")
                isLoading = true
                var userId = UserDefaults.standard.string(forKey: userIdKey)
                if userId == nil || userId == "" {
                    userId = UUID().uuidString
                    UserDefaults.standard.set(userId, forKey: userIdKey)
                    print("[SubscriptionViewModel] Generated and saved new userId: \(userId!)")
                }
                let email = "user_\(userId!)"
                if subscription.isTrial {
                    print("[SubscriptionViewModel] Trial subscription flow")
                    print("[SubscriptionViewModel] Trial userId: \(userId!)")
                    let config = try await vpnService.activateSubscription(
                        userId: userId!,
                        subscriptionId: UUID().uuidString,
                        isTrialPeriod: true,
                        durationInDays: subscription.durationInDays,
                        email: email
                    )
                    hasUsedTrial = true
                    await MainActor.run {
                        self.vpnConfig = config
                        print("📋 [SubscriptionViewModel] Получена конфигурация при покупке пробной подписки: \(config)")
                        self.isLoading = false
                        self.showTemporaryToast("Пробная подписка активирована!")
                    }
                } else {
                    // Для платных подписок сохраняем длительность
                    self.currentSubscriptionDurationInDays = subscription.durationInDays
                    print("[SubscriptionViewModel] Paid subscription flow, durationInDays: \(String(describing: subscription.durationInDays))")
                    let paymentUrl = try await paymentService.createPayment(for: subscription)
                    print("[SubscriptionViewModel] Got payment URL: \(paymentUrl)")
                    if let orderId = Self.extractOrderId(from: paymentUrl) {
                        self.currentOrderId = orderId
                        print("[SubscriptionViewModel] Extracted orderId: \(orderId)")
                    } else {
                        self.currentOrderId = nil
                        print("[SubscriptionViewModel] Failed to extract orderId from payment URL")
                    }
                    // Сохраняем userId для дальнейшей активации
                    self.currentUserIdForPayment = userId!
                    self.currentEmailForPayment = email
                    await MainActor.run {
                        if let url = URL(string: paymentUrl) {
                            print("[SubscriptionViewModel] Opening payment URL in Safari View Controller...")
                            self.safariURL = url
                            self.showSafariView = true
                        } else {
                            print("[SubscriptionViewModel] ❌ Invalid payment URL: \(paymentUrl)")
                            self.showTemporaryToast("Ошибка при создании платежа")
                        }
                        self.isLoading = false
                    }
                }
                self.refreshSubscriptionStatus()
            } catch {
                print("❌ [SubscriptionViewModel] Error in purchaseSubscription: \(error)")
                await MainActor.run {
                    isLoading = false
                    showTemporaryToast("Ошибка при покупке подписки")
                }
            }
        }
    }
    
    // Вспомогательная функция для извлечения orderId из ссылки
    static func extractOrderId(from url: String) -> String? {
        guard let url = URL(string: url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        for item in components.queryItems ?? [] {
            if item.name.lowercased() == "orderid" {
                return item.value
            }
        }
        // Иногда orderId может быть в path
        if let orderId = url.pathComponents.last, orderId.count > 10 {
            return orderId
        }
        return nil
    }
    
    private var paymentStatusTimer: Timer?
    private var paymentStatusCheckCount = 0
    private let maxPaymentStatusChecks = 12 // 2 минуты (12*10сек)
    
    func checkPaymentStatusAndActivate() {
        guard let orderId = currentOrderId else { print("[SubscriptionViewModel] No orderId for payment status check"); return }
        paymentStatusCheckCount = 0
        paymentStatusTimer?.invalidate()
        print("[SubscriptionViewModel] Starting periodic payment status check for orderId: \(orderId)")
        paymentStatusTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            self.paymentStatusCheckCount += 1
            Task {
                do {
                    print("[SubscriptionViewModel] Checking payment status for orderId: \(orderId) [attempt \(self.paymentStatusCheckCount)]")
                    let isSuccess = try await self.paymentService.checkPaymentStatus(orderId: orderId)
                    print("[SubscriptionViewModel] Payment status for orderId \(orderId): \(isSuccess ? "succeeded" : "not paid")")
                    if isSuccess {
                        print("[SubscriptionViewModel] Payment succeeded, activating subscription!")
                        let userId = self.currentUserIdForPayment ?? (UserDefaults.standard.string(forKey: self.userIdKey) ?? "")
                        print("[SubscriptionViewModel] Activating paid subscription for userId: \(userId), durationInDays: \(String(describing: self.currentSubscriptionDurationInDays))")
                        self.handlePaymentCallback(success: true, paymentId: userId)
                        await MainActor.run {
                            self.showTemporaryToast("Оплата прошла успешно! Подписка выдана.")
                        }
                        timer.invalidate()
                        self.paymentStatusTimer = nil
                    } else if self.paymentStatusCheckCount >= self.maxPaymentStatusChecks {
                        print("[SubscriptionViewModel] Payment not completed after max attempts for orderId: \(orderId)")
                        await MainActor.run {
                            self.showTemporaryToast("Платёж не завершён или отменён")
                        }
                        timer.invalidate()
                        self.paymentStatusTimer = nil
                    }
                } catch {
                    print("[SubscriptionViewModel] Error checking payment status: \(error)")
                    await MainActor.run {
                        self.showTemporaryToast("Ошибка при проверке платежа")
                    }
                    timer.invalidate()
                    self.paymentStatusTimer = nil
                }
            }
        }
    }
    
    func handlePaymentCallback(success: Bool, paymentId: String) {
        print("[SubscriptionViewModel] handlePaymentCallback called: success=\(success), paymentId=\(paymentId)")
        guard success else {
            print("[SubscriptionViewModel] Payment not successful, skipping activation")
            return
        }
        Task {
            do {
                isLoading = true
                let durationInDays = self.currentSubscriptionDurationInDays ?? 30
                let email = self.currentEmailForPayment ?? "user_\(paymentId)"
                print("[SubscriptionViewModel] Calling vpnService.activateSubscription with userId: \(paymentId), email: \(email), durationInDays: \(durationInDays)")
                let config = try await vpnService.activateSubscription(
                    userId: paymentId,
                    subscriptionId: UUID().uuidString,
                    isTrialPeriod: false,
                    durationInDays: durationInDays,
                    email: email
                )
                await MainActor.run {
                    vpnConfig = config
                    print("📋 [SubscriptionViewModel] Получена конфигурация при успешной оплате: \(config)")
                    isLoading = false
                    self.showTemporaryToast("Оплата прошла успешно! Подписка выдана.")
                    self.refreshSubscriptionStatus()
                }
            } catch {
                print("[SubscriptionViewModel] Error in vpnService.activateSubscription: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    func copyConfig() {
        if let config = vpnConfig {
            print("📋 [SubscriptionViewModel] Копируемая конфигурация: \(config)")
            UIPasteboard.general.string = config
            showTemporaryToast("Конфигурация скопирована")
        }
    }
    
    func updateUserStats() {
        if let email = UserDefaults.standard.string(forKey: userIdKey) {
            // Получаем дату создания подписки (текущую дату для новой подписки)
            let subscriptionStartDate = Date()
            let expiryDate = subscriptionStartDate.addingTimeInterval(3 * 24 * 60 * 60) // Точно 3 дня
            
            let stats = UserStats(
                email: email,
                trafficUsed: 0, // Начинаем с 0 для новой подписки
                trafficLimit: 0, // Assuming a default trafficLimit
                startDate: subscriptionStartDate,
                expiryDate: expiryDate
            )
            
            Task { @MainActor in
                self.userStats = stats
            }
        }
    }
    
    struct UserStats {
        let email: String
        let trafficUsed: Int64
        let trafficLimit: Int64
        let startDate: Date
        let expiryDate: Date
        
        var isExpired: Bool {
            return Date() > expiryDate
        }
        
        var timeRemaining: String {
            if isExpired {
                return "Время пользования подпиской вышло"
            }
            
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day, .hour, .minute], from: Date(), to: expiryDate)
            
            if let days = components.day, days > 0 {
                return "\(days) дн. \(components.hour ?? 0) ч."
            } else if let hours = components.hour, hours > 0 {
                return "\(hours) ч. \(components.minute ?? 0) мин."
            } else if let minutes = components.minute, minutes > 0 {
                return "\(minutes) мин."
            } else {
                return "Менее часа"
            }
        }
        
        var trafficFormatted: String {
            let usedGB = Double(trafficUsed) / 1_000_000_000.0
            let limitGB = Double(trafficLimit) / 1_000_000_000.0
            return String(format: "%.1f ГБ из %.1f ГБ", usedGB, limitGB)
        }
    }
    
    func resetTrialStatus() {
        UserDefaults.standard.removeObject(forKey: userIdKey)
        hasUsedTrial = false
    }
    
    // Добавим функцию для проверки и обновления статуса подписки
    func refreshSubscriptionStatus() {
        Task {
            do {
                print("Refreshing subscription status")
                let userId = UserDefaults.standard.string(forKey: userIdKey) ?? ""
                if !userId.isEmpty {
                    print("Checking subscription for userId: \(userId)")
                    if let (config, expiryDate, trafficUsed) = try await vpnService.checkSubscription(userId: userId) {
                        print("📋 [SubscriptionViewModel] Получена конфигурация при обновлении статуса: \(config)")
                        print("Found subscription: config=\(config), expiry=\(expiryDate), traffic=\(trafficUsed)")
                        
                        // Проверяем, не истекла ли подписка
                        if Date() > expiryDate {
                            print("Subscription has expired")
                            await MainActor.run {
                                self.vpnConfig = nil
                                self.userStats = UserStats(
                                    email: userId,
                                    trafficUsed: trafficUsed,
                                    trafficLimit: 0,
                                    startDate: expiryDate.addingTimeInterval(-3 * 24 * 60 * 60),
                                    expiryDate: expiryDate
                                )
                                self.showTemporaryToast("Время пользования подпиской вышло")
                            }
                            return
                        }
                        
                        await MainActor.run {
                            self.vpnConfig = config
                            self.hasUsedTrial = true
                            self.userStats = UserStats(
                                email: userId,
                                trafficUsed: trafficUsed,
                                trafficLimit: 0,
                                startDate: expiryDate.addingTimeInterval(-3 * 24 * 60 * 60),
                                expiryDate: expiryDate
                            )
                            print("Updated UI with new subscription data")
                        }
                    } else {
                        print("No active subscription found")
                        await MainActor.run {
                            self.vpnConfig = nil
                            self.userStats = nil
                        }
                    }
                } else {
                    print("No userId found")
                }
            } catch {
                print("Failed to refresh subscription status: \(error)")
            }
        }
    }
    
    func resetAllSubscriptions() {
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("subscription_") }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: userIdKey)
        hasUsedTrial = false
        vpnConfig = nil
        userStats = nil
    }
    
    func resetAllSubscriptionsFull() async {
        // Удалить всех клиентов пользователя из панели
        let userId = UserDefaults.standard.string(forKey: userIdKey) ?? ""
        if !userId.isEmpty {
            do {
                try await vpnService.deleteAllUserClients(userId: userId)
            } catch {
                print("[Reset] Не удалось удалить клиентов из панели: \(error)")
            }
        }
        // Локальный сброс
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("subscription_") }
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: userIdKey)
        hasUsedTrial = false
        vpnConfig = nil
        userStats = nil
    }
    
    // Метод для очистки всех подписок (только для тестирования)
    func clearAllSubscriptions() async {
        do {
            isLoading = true
            let userId = UserDefaults.standard.string(forKey: userIdKey) ?? ""
            if !userId.isEmpty {
                try await vpnService.deleteAllUserClients(userId: userId)
                // Очищаем локальные данные
                UserDefaults.standard.removeObject(forKey: userIdKey)
                UserDefaults.standard.set(false, forKey: userIdKey)
                await MainActor.run {
                    self.vpnConfig = nil
                    self.userStats = nil
                    self.showTemporaryToast("Все подписки очищены")
                }
            }
        } catch {
            print("Failed to clear subscriptions: \(error)")
            await MainActor.run {
                self.showTemporaryToast("Ошибка при очистке подписок")
            }
        }
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    init() {
        VPNConnectionManager.shared.observeVPNStatus { [weak self] status in
            DispatchQueue.main.async {
                self?.vpnStatus = status
            }
        }
        // Проверяем статус подписки при запуске и каждые 5 минут
        refreshSubscriptionStatus()
        
        // Добавляем периодическое обновление
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshSubscriptionStatus()
        }
    }
} 
