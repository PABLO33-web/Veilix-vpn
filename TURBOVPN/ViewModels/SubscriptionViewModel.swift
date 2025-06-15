import Foundation
import SwiftUI
import NetworkExtension
import SafariServices

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
    private let hasUsedTrialKey = "hasUsedTrial"
    private let userIdKey = "userId"
    
    var hasUsedTrial: Bool {
        get {
            UserDefaults.standard.bool(forKey: hasUsedTrialKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasUsedTrialKey)
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
                // Гарантируем уникальный userId для любой подписки
                var userId = UserDefaults.standard.string(forKey: userIdKey)
                if userId == nil || userId == "" {
                    userId = UUID().uuidString
                    UserDefaults.standard.set(userId, forKey: userIdKey)
                    print("[SubscriptionViewModel] Generated and saved new userId: \(userId!)")
                }
                // Для trial и платных подписок используем один и тот же email: user_<userId>
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
                        self.isLoading = false
                        print("[SubscriptionViewModel] Trial subscription activated, config: \(String(describing: config))")
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
            } catch let error as PaymentError {
                print("[SubscriptionViewModel] ❌ Payment error: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                    self.showTemporaryToast(error.localizedDescription)
                }
            } catch {
                print("[SubscriptionViewModel] ❌ Error occurred: \(error)")
                print("[SubscriptionViewModel] Error details: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                    self.showTemporaryToast("Ошибка при покупке подписки")
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
                    userId: paymentId, // это userId
                    subscriptionId: UUID().uuidString,
                    isTrialPeriod: false,
                    durationInDays: durationInDays,
                    email: email
                )
                await MainActor.run {
                    vpnConfig = config
                    isLoading = false
                    self.showTemporaryToast("Оплата прошла успешно! Подписка выдана.")
                    print("[SubscriptionViewModel] Paid subscription activated, config: \(String(describing: config))")
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
            UIPasteboard.general.string = config
            // Показываем уведомление об успешном копировании
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
                expiryDate: expiryDate,
                subscriptionStartDate: subscriptionStartDate
            )
            
            Task { @MainActor in
                self.userStats = stats
            }
        }
    }
    
    struct UserStats {
        let email: String
        let trafficUsed: Double
        let expiryDate: Date
        let subscriptionStartDate: Date
        
        var trafficFormatted: String {
            if trafficUsed > 1024 {
                return String(format: "%.2f GB", trafficUsed / 1024)
            } else {
                return String(format: "%.2f MB", trafficUsed)
            }
        }
        
        var timeRemaining: String {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day, .hour], from: Date(), to: expiryDate)
            let days = components.day ?? 0
            let hours = components.hour ?? 0
            
            if days > 0 {
                if hours > 0 {
                    return "\(days) \(pluralForm(days, one: "день", few: "дня", many: "дней")) \(hours) \(pluralForm(hours, one: "час", few: "часа", many: "часов"))"
                } else {
                    return "\(days) \(pluralForm(days, one: "день", few: "дня", many: "дней"))"
                }
            } else if hours > 0 {
                return "\(hours) \(pluralForm(hours, one: "час", few: "часа", many: "часов"))"
            } else {
                return "менее часа"
            }
        }
        
        private func pluralForm(_ number: Int, one: String, few: String, many: String) -> String {
            let mod10 = number % 10
            let mod100 = number % 100
            
            if mod10 == 1 && mod100 != 11 {
                return one
            } else if (mod10 >= 2 && mod10 <= 4) && !(mod100 >= 12 && mod100 <= 14) {
                return few
            } else {
                return many
            }
        }
    }
    
    func resetTrialStatus() {
        UserDefaults.standard.removeObject(forKey: hasUsedTrialKey)
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
                        print("Found subscription: config=\(config), expiry=\(expiryDate), traffic=\(trafficUsed)")
                        await MainActor.run {
                            self.vpnConfig = config
                            self.hasUsedTrial = true // Обновляем статус триала
                            self.userStats = UserStats(
                                email: userId,
                                trafficUsed: trafficUsed,
                                expiryDate: expiryDate,
                                subscriptionStartDate: expiryDate.addingTimeInterval(-3 * 24 * 60 * 60)
                            )
                            print("Updated UI with new subscription data")
                        }
                    } else {
                        print("No active subscription found")
                        await MainActor.run {
                            // Если подписка не найдена, очищаем данные
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
        UserDefaults.standard.removeObject(forKey: hasUsedTrialKey)
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
        UserDefaults.standard.removeObject(forKey: hasUsedTrialKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        hasUsedTrial = false
        vpnConfig = nil
        userStats = nil
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