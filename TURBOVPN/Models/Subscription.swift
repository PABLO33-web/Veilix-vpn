import Foundation

struct Subscription: Identifiable {
    let id: String
    let name: String
    let duration: String
    let price: Double // Цена в рублях
    let oldPrice: Double // Старая цена в рублях
    let isTrial: Bool
    let discount: Int // Процент скидки
    let durationInDays: Int?
    let features: [String]
    let isPopular: Bool
}

// Пример данных
extension Subscription {
    static let samples: [Subscription] = [
        // Пробная подписка
        Subscription(
            id: "trial",
            name: "Пробная",
            duration: "1 день",
            price: 0,
            oldPrice: 0,
            isTrial: true,
            discount: 0,
            durationInDays: 1,
            features: [
                "1 день бесплатно",
                "Базовая скорость",
                "Сервер main1.veilix.online",
                "1 устройство"
            ],
            isPopular: false
        ),
        // 1 месяц
        Subscription(
            id: "1_month",
            name: "1 месяц",
            duration: "1 месяц",
            price: 100,
            oldPrice: 120,
            isTrial: false,
            discount: 17,
            durationInDays: 30,
            features: [
                "Максимальная скорость",
                "Сервер main1.veilix.online",
                "1 устройство",
                "Базовая поддержка"
            ],
            isPopular: true
        ),
        // 3 месяца
        Subscription(
            id: "3_months",
            name: "3 месяца",
            duration: "3 месяца",
            price: 250,
            oldPrice: 294,
            isTrial: false,
            discount: 15,
            durationInDays: 90,
            features: [
                "Максимальная скорость",
                "Сервер main1.veilix.online",
                "2 устройства",
                "Поддержка 24/7"
            ],
            isPopular: false
        ),
        // 6 месяцев
        Subscription(
            id: "6_months",
            name: "6 месяцев",
            duration: "6 месяцев",
            price: 500,
            oldPrice: 588,
            isTrial: false,
            discount: 16,
            durationInDays: 180,
            features: [
                "Максимальная скорость",
                "Сервер main1.veilix.online",
                "3 устройства",
                "Приоритетная поддержка"
            ],
            isPopular: true
        ),
        // 12 месяцев
        Subscription(
            id: "12_months",
            name: "12 месяцев",
            duration: "12 месяцев",
            price: 1000,
            oldPrice: 1200,
            isTrial: false,
            discount: 17,
            durationInDays: 365,
            features: [
                "Максимальная скорость",
                "Сервер main1.veilix.online",
                "5 устройств",
                "VIP поддержка"
            ],
            isPopular: false
        )
    ]
} 