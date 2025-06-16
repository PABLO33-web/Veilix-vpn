import Foundation

class VPNService {
    private let adminPanelURL = "https://eu1.veilix.online:2053/g6243vvgwyw6423" // Исправленный URL панели
    private let botToken = "YOUR_BOT_TOKEN"
    private let serverAddress = "eu1.veilix.online"
    
    private let xrayApiPath = "/panel/api/inbounds" // Путь для x-ui
    private let adminUsername = "admin" // Логин от панели
    private let adminPassword = "89282722205MrM" // Пароль от панели
    
    private func generateTrialEmail(userId: String) -> String {
        // Формат как в боте
        return "trial_\(Int(Date().timeIntervalSince1970))_\(userId)"
    }
    
    private func getPortForSubscriptionType(isTrialPeriod: Bool, isReferral: Bool = false) -> Int {
        return 443 // Всегда использовать 443
    }
    
    private func getAvailablePort() async throws -> Int {
        // Получаем сессию x-ui
        let sessionCookie = try await getXUISession()
        
        // Получаем список всех inbounds
        guard let url = URL(string: "\(adminPanelURL)/panel/api/inbounds/list") else {
            throw VPNError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = json["obj"] as? [[String: Any]] else {
            throw VPNError.invalidResponse
        }
        
        // Собираем все используемые порты
        let usedPorts = Set(inbounds.compactMap { $0["port"] as? Int })
        
        // Ищем свободный порт в диапазоне 3000-4000
        for port in 3000...4000 {
            if !usedPorts.contains(port) {
                return port
            }
        }
        
        throw VPNError.activationFailed("No available ports")
    }
    
    private func generateVLESSConfig(userId: String, isTrialPeriod: Bool = false, isReferral: Bool = false, email: String) async throws -> VLESSConfig {
        let id = UUID().uuidString
        let port = getPortForSubscriptionType(isTrialPeriod: isTrialPeriod, isReferral: isReferral)
        
        let config = VLESSConfig(
            id: id,
            email: email,
            port: port,
            network: "tcp",
            security: "reality",
            publicKey: "4kuB0fRlvS1tmM2bWc-J8l5BxUPmHN9ncWXld5Rnphg",
            fingerprint: "chrome",
            serverName: "Нидерланды",
            shortId: "f9f3",
            serverAddress: "eu1.veilix.online",
            spiderX: "%2F"
        )
        
        print("📋 [VPNService] Сгенерирована новая конфигурация: \(config.asString)")
        return config
    }
    
    // Метод для авторизации в x-ui
    private func getXUISession() async throws -> String {
        guard let url = URL(string: "\(adminPanelURL)/login") else {
            log("❌ Invalid login URL")
            throw VPNError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Формируем JSON для входа
        let loginData: [String: String] = [
            "username": adminUsername,
            "password": adminPassword
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: loginData)
        request.httpBody = jsonData
        
        log("🔑 Trying to login to x-ui panel")
        log("URL: \(url.absoluteString)")
        log("Username: \(adminUsername)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let responseString = String(data: data, encoding: .utf8) {
            log("📥 Login response: \(responseString)")
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            log("❌ Invalid response type")
            throw VPNError.invalidResponse
        }
        
        log("📡 Login status code: \(httpResponse.statusCode)")
        
        // Получаем все заголовки для отладки
        for (key, value) in httpResponse.allHeaderFields {
            log("🔑 Header: \(key) = \(value)")
        }
        
        // Проверяем все возможные варианты cookie
        if let cookies = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
            log("✅ Found Set-Cookie header")
            return cookies
        }
        
        if let cookies = httpResponse.value(forHTTPHeaderField: "Cookie") {
            log("✅ Found Cookie header")
            return cookies
        }
        
        // Если нет куки в заголовках, проверяем тело ответа
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            log("📦 Response JSON: \(json)")
            if let success = json["success"] as? Bool, success {
                log("✅ Login successful but no cookies found")
                return ""
            }
        }
        
        log("❌ No valid session cookie found")
        throw VPNError.invalidResponse
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[\(timestamp)] [VPNService] \(message)")
    }
    
    // Метод для добавления клиента в x-ui
    private func addClientToXUI(config: VLESSConfig, sessionCookie: String, durationInDays: Int?) async throws {
        log("➕ Adding or extending client with email: \(config.email), durationInDays: \(String(describing: durationInDays))")
        // Получаем список всех inbounds
        guard let listUrl = URL(string: "\(adminPanelURL)/panel/api/inbounds/list") else {
            log("❌ Invalid inbounds list URL")
            throw VPNError.invalidResponse
        }
        var listRequest = URLRequest(url: listUrl)
        listRequest.httpMethod = "GET"
        listRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        log("📡 Requesting inbounds list")
        let (listData, listResponse) = try await URLSession.shared.data(for: listRequest)
        if let responseString = String(data: listData, encoding: .utf8) {
            log("📥 Inbounds list response: \(responseString)")
        }
        guard let listHttpResponse = listResponse as? HTTPURLResponse else {
            log("❌ Invalid inbounds list response type")
            throw VPNError.invalidResponse
        }
        log("📡 Inbounds list status code: \(listHttpResponse.statusCode)")
        guard listHttpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let inbounds = json["obj"] as? [[String: Any]] else {
            log("❌ Failed to parse inbounds list")
            throw VPNError.invalidResponse
        }
        log("📊 Found \(inbounds.count) inbounds")
        if let existingInbound = inbounds.first(where: { ($0["port"] as? Int) == config.port }) {
            log("✅ Found existing inbound with port \(config.port)")
            guard let id = existingInbound["id"] as? Int,
                  let settings = existingInbound["settings"] as? String,
                  let settingsData = settings.data(using: .utf8),
                  var settingsJson = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
                  var clients = settingsJson["clients"] as? [[String: Any]] else {
                log("❌ Failed to parse inbound settings")
                throw VPNError.invalidResponse
            }
            let days = durationInDays ?? 3
            let now = Date()
            let addInterval = Double(days) * 24 * 60 * 60
            // Ищем клиента по email
            if let idx = clients.firstIndex(where: { ($0["email"] as? String) == config.email }) {
                // Продлеваем срок действия
                let oldExpiry = (clients[idx]["expiryTime"] as? Int) ?? Int(now.timeIntervalSince1970 * 1000)
                let oldExpiryDate = Date(timeIntervalSince1970: Double(oldExpiry) / 1000)
                let baseDate = max(now, oldExpiryDate)
                let newExpiry = Int(baseDate.addingTimeInterval(addInterval).timeIntervalSince1970 * 1000)
                clients[idx]["expiryTime"] = newExpiry
                log("🔄 [EXTEND] Extended client expiry for email: \(config.email) to: \(Date(timeIntervalSince1970: Double(newExpiry)/1000))")
            } else {
                // Добавляем нового клиента
                let expiryTime = Int(now.addingTimeInterval(addInterval).timeIntervalSince1970 * 1000)
                let newClient: [String: Any] = [
                    "id": config.id,
                    "email": config.email,
                    "flow": "",
                    "limitIp": 0,
                    "totalGB": 0,
                    "expiryTime": expiryTime,
                    "enable": true
                ]
                log("➕ [NEW] Adding new client: \(newClient)")
                clients.append(newClient)
            }
            settingsJson["clients"] = clients
            // Обновляем inbound
            guard let updateUrl = URL(string: "\(adminPanelURL)/panel/api/inbounds/update/\(id)") else {
                log("❌ Invalid update URL")
                throw VPNError.invalidResponse
            }
            var updateRequest = URLRequest(url: updateUrl)
            updateRequest.httpMethod = "POST"
            updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            updateRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            let updatedSettings = try JSONSerialization.data(withJSONObject: settingsJson)
            let settingsString = String(data: updatedSettings, encoding: .utf8) ?? ""
            var inboundData = existingInbound
            inboundData["settings"] = settingsString
            updateRequest.httpBody = try JSONSerialization.data(withJSONObject: inboundData)
            log("📡 Sending update request")
            let (updateData, updateResponse) = try await URLSession.shared.data(for: updateRequest)
            if let responseString = String(data: updateData, encoding: .utf8) {
                log("📥 Update response: \(responseString)")
            }
            guard let updateHttpResponse = updateResponse as? HTTPURLResponse else {
                log("❌ Update failed: invalid HTTPURLResponse")
                throw VPNError.activationFailed("Failed to update inbound")
            }
            if updateHttpResponse.statusCode != 200 {
                log("❌ Update failed with status code: \(updateHttpResponse.statusCode)")
                throw VPNError.activationFailed("Failed to update inbound")
            }
            log("✅ Successfully added or extended client in existing inbound")
            return
        }
        log("❌ No inbound found for port \(config.port)")
        throw VPNError.activationFailed("No inbound found for port \(config.port)")
    }
    
    // Обновленный метод активации подписки
    func activateSubscription(userId: String, subscriptionId: String, isTrialPeriod: Bool = false, isReferral: Bool = false, durationInDays: Int? = nil, email: String) async throws -> String {
        print("VPNService: Starting subscription activation")
        print("VPNService: User ID: \(userId)")
        print("VPNService: Subscription ID: \(subscriptionId)")
        print("VPNService: Is Trial: \(isTrialPeriod)")
        
        do {
            log("Starting subscription activation")
            log("User ID: \(userId)")
            log("Subscription ID: \(subscriptionId)")
            log("Is Trial: \(isTrialPeriod)")
            
            // Проверяем соединение
            log("Checking connection...")
            try await checkConnection()
            log("Connection check successful")
            
            log("Generating VLESS config...")
            let config = try await generateVLESSConfig(userId: userId, isTrialPeriod: isTrialPeriod, isReferral: isReferral, email: email)
            log("Generated config with email: \(config.email) and port: \(config.port)")
            print("📋 [VPNService] Активация подписки - полная конфигурация: \(config.asString)")
            
            log("Getting x-ui session...")
            let sessionCookie = try await getXUISession()
            log("Session cookie length: \(sessionCookie.count)")
            
            log("Adding client to x-ui...")
            try await addClientToXUI(config: config, sessionCookie: sessionCookie, durationInDays: durationInDays)
            log("Successfully added client")
            
            // Сохраняем информацию о подписке
            log("Saving subscription info...")
            try await saveSubscriptionInfo(
                userId: userId,
                subscriptionId: subscriptionId,
                config: config,
                durationInDays: durationInDays
            )
            log("Subscription info saved")
            
            log("Activation completed successfully")
            return config.asString
            
        } catch {
            log("❌ Activation failed with error: \(error.localizedDescription)")
            if let error = error as? URLError {
                log("URL Error code: \(error.code)")
                log("URL Error localizedDescription: \(error.localizedDescription)")
            }
            throw VPNError.activationFailed(error.localizedDescription)
        }
    }
    
    // Метод для сохранения информации о подписке
    private func saveSubscriptionInfo(userId: String, subscriptionId: String, config: VLESSConfig, durationInDays: Int?) async throws {
        let days = durationInDays ?? 3
        let subscriptionInfo: [String: Any] = [
            "userId": userId,
            "subscriptionId": subscriptionId,
            "email": config.email,
            "vlessId": config.id,
            "expiryDate": Date().addingTimeInterval(Double(days) * 24 * 60 * 60)
        ]
        UserDefaults.standard.set(subscriptionInfo, forKey: "subscription_\(subscriptionId)")
    }
    
    // Обновим метод деактивации подписки для работы с x-ui
    func deactivateSubscription(userId: String, subscriptionId: String) async throws {
        do {
            // Получаем сессию x-ui
            let sessionCookie = try await getXUISession()
            
            // Получаем список всех inbounds
            guard let url = URL(string: "\(adminPanelURL)/panel/api/inbounds/list") else {
                throw VPNError.invalidResponse
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let inbounds = json["obj"] as? [[String: Any]] else {
                throw VPNError.invalidResponse
            }
            
            // Ищем inbound с нужным email
            let email = "user_\(userId)_"
            for inbound in inbounds {
                if let remark = inbound["remark"] as? String,
                   remark.hasPrefix(email),
                   let id = inbound["id"] as? Int {
                    // Удаляем найденный inbound
                    let deleteURL = URL(string: "\(adminPanelURL)/panel/api/inbounds/del/\(id)")!
                    var deleteRequest = URLRequest(url: deleteURL)
                    deleteRequest.httpMethod = "POST"
                    deleteRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                    
                    let (_, deleteResponse) = try await URLSession.shared.data(for: deleteRequest)
                    guard let deleteHttpResponse = deleteResponse as? HTTPURLResponse,
                          deleteHttpResponse.statusCode == 200 else {
                        throw VPNError.activationFailed("Failed to delete inbound")
                    }
                    
                    return
                }
            }
            
            throw VPNError.activationFailed("Inbound not found")
            
        } catch {
            throw VPNError.configurationFailed
        }
    }
    
    // Метод для тестирования
    func testTrialSubscription() async {
        do {
            log("Starting trial subscription test")
            let userId = UUID().uuidString
            let subscriptionId = "trial_test_\(Int(Date().timeIntervalSince1970))"
            let email = "user_\(userId)"
            let config = try await activateSubscription(userId: userId, subscriptionId: subscriptionId, email: email)
            log("Successfully created trial subscription")
            log("Config: \(config)")
            // Ждем 5 секунд
            try await deactivateSubscription(userId: userId, subscriptionId: subscriptionId)
            log("Successfully deactivated trial subscription")
        } catch {
            log("Test failed: \(error)")
        }
    }
    
    private func checkConnection() async throws {
        guard let url = URL(string: "\(adminPanelURL)/xui/") else {
            throw VPNError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        
        do {
            log("Checking connection to \(url.absoluteString)")
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                log("Invalid response type")
                throw VPNError.invalidResponse
            }
            
            log("Connection check response code: \(httpResponse.statusCode)")
            
            // x-ui может вернуть 302 при редиректе на страницу логина
            if ![200, 302].contains(httpResponse.statusCode) {
                log("Unexpected status code")
                throw VPNError.invalidResponse
            }
            
            log("Connection check successful")
        } catch {
            log("Connection check failed: \(error.localizedDescription)")
            throw VPNError.invalidResponse
        }
    }
    
    func checkSubscription(userId: String) async throws -> (String, Date, Int64)? {
        print("Checking subscription for user: \(userId)")
        
        let sessionCookie = try await getXUISession()
        guard let url = URL(string: "\(adminPanelURL)/panel/api/inbounds/list") else {
            throw VPNError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = json["obj"] as? [[String: Any]] else {
            throw VPNError.invalidResponse
        }
        
        print("Found \(inbounds.count) inbounds")
        
        for (index, inbound) in inbounds.enumerated() {
            print("Checking inbound \(index + 1)")
            if let settings = inbound["settings"] as? String {
                print("Settings string: \(settings)")
                if let settingsData = settings.data(using: .utf8),
                   let settingsJson = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any] {
                    print("Parsed settings: \(settingsJson)")
                    if let clients = settingsJson["clients"] as? [[String: Any]] {
                        print("Found \(clients.count) clients in inbound \(index + 1)")
                        
                        for (clientIndex, client) in clients.enumerated() {
                            print("Client \(clientIndex + 1) data: \(client)")
                            if let email = client["email"] as? String {
                                print("Checking client \(clientIndex + 1) with email: \(email)")
                                if email == userId || email.contains(userId) {
                                    print("Found matching client!")
                                    print("Full client data: \(client)")
                                    
                                    // Получаем все необходимые данные
                                    let id = client["id"] as? String ?? UUID().uuidString
                                    let expiryTime = client["expiryTime"] as? Int ?? Int(Date().addingTimeInterval(3 * 24 * 60 * 60).timeIntervalSince1970 * 1000)
                                    let up = client["up"] as? Int64 ?? 0
                                    let down = client["down"] as? Int64 ?? 0
                                    let totalTraffic = up + down // теперь в байтах
                                    
                                    let expiryDate = Date(timeIntervalSince1970: TimeInterval(expiryTime / 1000))
                                    
                                    // Создаем полную VLESS конфигурацию
                                    let port = inbound["port"] as? Int ?? 443
                                    let vlessConfig = VLESSConfig(
                                        id: id,
                                        email: email,
                                        port: port,
                                        network: "tcp",
                                        security: "reality",
                                        publicKey: "4kuB0fRlvS1tmM2bWc-J8l5BxUPmHN9ncWXld5Rnphg",
                                        fingerprint: "chrome",
                                        serverName: "Нидерланды",
                                        shortId: "f9f3",
                                        serverAddress: "eu1.veilix.online",
                                        spiderX: "%2F"
                                    )
                                    
                                    let fullConfig = vlessConfig.asString
                                    
                                    print("📋 [VPNService] Проверка подписки - полная конфигурация: \(fullConfig)")
                                    print("Client details - ID: \(id), Expiry: \(expiryDate), Traffic: \(totalTraffic) bytes")
                                    return (fullConfig, expiryDate, totalTraffic)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        print("No matching client found for userId: \(userId)")
        return nil
    }
    
    func deleteAllUserClients(userId: String) async throws {
        let sessionCookie = try await getXUISession()
        guard let url = URL(string: "\(adminPanelURL)/panel/api/inbounds/list") else { throw VPNError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = json["obj"] as? [[String: Any]] else {
            throw VPNError.invalidResponse
        }
        for inbound in inbounds {
            guard let id = inbound["id"] as? Int,
                  let settings = inbound["settings"] as? String,
                  let settingsData = settings.data(using: .utf8),
                  let settingsJson = try? JSONSerialization.jsonObject(with: settingsData) as? [String: Any],
                  let clients = settingsJson["clients"] as? [[String: Any]] else { continue }
            var newClients = clients.filter { client in
                guard let email = client["email"] as? String else { return true }
                return !email.contains(userId)
            }
            if newClients.count != clients.count {
                var newSettingsJson = settingsJson
                newSettingsJson["clients"] = newClients
                let updatedSettings = try JSONSerialization.data(withJSONObject: newSettingsJson)
                let settingsString = String(data: updatedSettings, encoding: .utf8) ?? ""
                var inboundData = inbound
                inboundData["settings"] = settingsString
                guard let updateUrl = URL(string: "\(adminPanelURL)/panel/api/inbounds/update/\(id)") else { continue }
                var updateRequest = URLRequest(url: updateUrl)
                updateRequest.httpMethod = "POST"
                updateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                updateRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                updateRequest.httpBody = try JSONSerialization.data(withJSONObject: inboundData)
                _ = try await URLSession.shared.data(for: updateRequest)
            }
        }
    }
}

struct SubscriptionResponse: Codable {
    let config: String
} 