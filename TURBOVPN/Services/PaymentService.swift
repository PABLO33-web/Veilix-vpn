import Foundation

enum PaymentError: Error {
    case invalidURL
    case invalidResponse
    case paymentFailed(String)
    case networkError(String)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Неверный URL для оплаты"
        case .invalidResponse:
            return "Неверный ответ от сервера"
        case .paymentFailed(let reason):
            return "Ошибка оплаты: \(reason)"
        case .networkError(let error):
            return "Ошибка сети: \(error)"
        }
    }
}

class PaymentService {
    private let shopId = "1093180"
    private let apiKey = "live_AS5vLpM52omFu51SUxNo8TOpLmaJ0gNxo7v_UtBpkUE"
    private let apiURL = "https://api.yookassa.ru/v3/payments"
    
    func createPayment(for subscription: Subscription) async throws -> String {
        print("[PaymentService] Starting payment creation for subscription: \(subscription.name)")
        
        guard let url = URL(string: apiURL) else {
            print("[PaymentService] ❌ Invalid URL: \(apiURL)")
            throw PaymentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(Data("\(shopId):\(apiKey)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotence-Key")
        
        let paymentData: [String: Any] = [
            "amount": [
                "value": String(subscription.price),
                "currency": "RUB"
            ],
            "confirmation": [
                "type": "redirect",
                "return_url": "veilixvpn://payment"
            ],
            "capture": true,
            "description": "Подписка \(subscription.name) на \(subscription.durationInDays) дней",
            "metadata": [
                "subscription_id": subscription.id,
                "duration_days": subscription.durationInDays
            ],
            "receipt": [
                "customer": [
                    "email": "user@example.com"
                ],
                "items": [
                    [
                        "description": "Подписка \(subscription.name) на \(subscription.durationInDays) дней",
                        "quantity": "1",
                        "amount": [
                            "value": String(subscription.price),
                            "currency": "RUB"
                        ],
                        "vat_code": "1",
                        "payment_mode": "full_prepayment",
                        "payment_subject": "service"
                    ]
                ]
            ]
        ]
        
        print("[PaymentService] Payment data: \(paymentData)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: paymentData)
        } catch {
            print("[PaymentService] ❌ Failed to serialize payment data: \(error)")
            throw PaymentError.invalidResponse
        }
        
        do {
            print("[PaymentService] Sending request to YooKassa...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[PaymentService] ❌ Invalid HTTP response")
                throw PaymentError.invalidResponse
            }
            
            print("[PaymentService] Response status code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[PaymentService] ❌ Payment failed with status \(httpResponse.statusCode): \(errorMessage)")
                throw PaymentError.paymentFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[PaymentService] ❌ Failed to parse response JSON")
                throw PaymentError.invalidResponse
            }
            
            print("[PaymentService] Response JSON: \(json)")
            
            guard let confirmation = json["confirmation"] as? [String: Any],
                  let confirmationUrl = confirmation["confirmation_url"] as? String else {
                print("[PaymentService] ❌ No confirmation URL in response")
                throw PaymentError.invalidResponse
            }
            
            print("[PaymentService] ✅ Successfully created payment with URL: \(confirmationUrl)")
            return confirmationUrl
            
        } catch let error as PaymentError {
            print("[PaymentService] ❌ Payment error: \(error.localizedDescription)")
            throw error
        } catch {
            print("[PaymentService] ❌ Network error: \(error.localizedDescription)")
            throw PaymentError.networkError(error.localizedDescription)
        }
    }
    
    func checkPaymentStatus(orderId: String) async throws -> Bool {
        let urlString = "https://api.yookassa.ru/v3/payments/\(orderId)"
        guard let url = URL(string: urlString) else {
            throw PaymentError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Basic \(Data("\(shopId):\(apiKey)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PaymentError.invalidResponse
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaymentError.invalidResponse
        }
        if let status = json["status"] as? String {
            return status == "succeeded"
        }
        return false
    }
} 