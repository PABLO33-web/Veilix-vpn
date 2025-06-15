import Foundation

class SubscriptionManager {
    static let shared = SubscriptionManager()
    private let vpnService = VPNService()
    
    func startExpiryCheck() {
        // Проверяем каждые 15 минут
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task {
                await self?.checkExpiredSubscriptions()
            }
        }
        
        // Сразу запускаем первую проверку
        Task {
            await checkExpiredSubscriptions()
        }
    }
    
    private func checkExpiredSubscriptions() async {
        let defaults = UserDefaults.standard
        
        // Получаем все ключи, начинающиеся с "subscription_"
        let subscriptionKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("subscription_") }
        
        for key in subscriptionKeys {
            guard let subscriptionInfo = defaults.dictionary(forKey: key),
                  let expiryDate = subscriptionInfo["expiryDate"] as? Date,
                  let subscriptionId = subscriptionInfo["subscriptionId"] as? String,
                  let userId = subscriptionInfo["userId"] as? String else {
                continue
            }
            
            // Проверяем, истекла ли подписка
            if expiryDate < Date() {
                do {
                    // Деактивируем подписку
                    try await vpnService.deactivateSubscription(userId: userId, subscriptionId: subscriptionId)
                    
                    // Удаляем информацию о подписке
                    defaults.removeObject(forKey: key)
                } catch {
                    print("Failed to deactivate subscription: \(error)")
                }
            }
        }
    }
} 