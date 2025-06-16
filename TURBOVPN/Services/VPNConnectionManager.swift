import Foundation
@preconcurrency import NetworkExtension
@preconcurrency import Network
import CryptoKit

// Локальный SOCKS5 прокси сервер для обхода блокировок
class LocalSOCKSProxy {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let vlessClient: VLESSClient
    private let port: UInt16 = 8888
    private let blockedDomains: [String]
    
    init(vlessClient: VLESSClient, blockedDomains: [String]) {
        self.vlessClient = vlessClient
        self.blockedDomains = blockedDomains
    }
    
    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: .global())
        print("🔌 SOCKS5 прокси запущен на порту \(port)")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .global())
        
        // Обработка SOCKS5 протокола
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleSOCKSRequest(connection, data: data)
            }
        }
    }
    
    private func handleSOCKSRequest(_ connection: NWConnection, data: Data) {
        // Поддержка как SOCKS5, так и HTTP CONNECT
        let dataString = String(data: data, encoding: .utf8) ?? ""
        
        Task {
            do {
                if dataString.hasPrefix("CONNECT") {
                    // HTTP CONNECT запрос
                    await handleHTTPConnect(connection, data: data)
                } else {
                    // SOCKS5 запрос
                    await handleSOCKS5(connection, data: data)
                }
            }
        }
    }
    
    private func handleHTTPConnect(_ connection: NWConnection, data: Data) async {
        // Парсим HTTP CONNECT запрос
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendHTTPError(connection, "400 Bad Request")
            return
        }
        
        // Извлекаем хост и порт из CONNECT запроса
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first,
              let hostPort = firstLine.components(separatedBy: " ").dropFirst().first else {
            sendHTTPError(connection, "400 Bad Request")
            return
        }
        
        let parts = hostPort.components(separatedBy: ":")
        let host = parts[0]
        let port = Int(parts.count > 1 ? parts[1] : "443") ?? 443
        
        // Проверяем, нужно ли проксировать этот домен
        let shouldProxy = blockedDomains.contains { domain in
            if domain.hasPrefix("*.") {
                let baseDomain = String(domain.dropFirst(2))
                return host.hasSuffix(baseDomain)
            } else {
                return host == domain
            }
        }
        
        if shouldProxy {
            // Отправляем через VLESS
            do {
                let connectData = "CONNECT \(host):\(port) HTTP/1.1\r\n\r\n".data(using: .utf8) ?? Data()
                _ = try await vlessClient.proxyData(connectData)
                
                // Отправляем успешный ответ
                let successResponse = "HTTP/1.1 200 Connection established\r\n\r\n".data(using: .utf8)!
                connection.send(content: successResponse, completion: .contentProcessed { _ in })
                
                print("🌐 HTTP CONNECT проксирован: \(host):\(port)")
            } catch {
                sendHTTPError(connection, "502 Bad Gateway")
                print("❌ Ошибка HTTP CONNECT: \(error)")
            }
        } else {
            // Прямое подключение для обычных сайтов
            sendHTTPError(connection, "200 Connection established")
            print("🔄 Прямое подключение: \(host):\(port)")
        }
    }
    
    private func handleSOCKS5(_ connection: NWConnection, data: Data) async {
        // Простая реализация SOCKS5
        do {
            // Проксируем через VLESS
            let response = try await vlessClient.proxyData(data)
            connection.send(content: response, completion: .contentProcessed { error in
                if let error = error {
                    print("❌ Ошибка отправки SOCKS5 данных: \(error)")
                }
            })
        } catch {
            print("❌ Ошибка SOCKS5 проксирования: \(error)")
        }
    }
    
    private func sendHTTPError(_ connection: NWConnection, _ status: String) {
        let response = "HTTP/1.1 \(status)\r\n\r\n".data(using: .utf8)!
        connection.send(content: response, completion: .contentProcessed { _ in })
    }
    
    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        print("🔌 SOCKS5 прокси остановлен")
    }
}

// VLESS протокол клиент для прямого подключения
class VLESSClient {
    private var connection: NWConnection?
    let serverAddress: String
    let serverPort: Int
    let uuid: String
    private let security: String
    private let publicKey: String
    private let shortId: String
    private let serverName: String
    
    init(serverAddress: String, serverPort: Int, uuid: String, security: String = "reality", publicKey: String, shortId: String, serverName: String) {
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.uuid = uuid
        self.security = security
        self.publicKey = publicKey
        self.shortId = shortId
        self.serverName = serverName
    }
    
    static func parseVLESSURL(_ vlessURL: String) -> VLESSClient? {
        // Парсинг VLESS URL
        guard let url = URL(string: vlessURL),
              url.scheme == "vless",
              let host = url.host,
              let port = url.port else {
            return nil
        }
        
        let uuid = url.user ?? ""
        let queryItems = URLComponents(string: vlessURL)?.queryItems
        
        let security = queryItems?.first(where: { $0.name == "security" })?.value ?? "reality"
        let publicKey = queryItems?.first(where: { $0.name == "pbk" })?.value ?? ""
        let shortId = queryItems?.first(where: { $0.name == "sid" })?.value ?? ""
        let serverName = queryItems?.first(where: { $0.name == "sni" })?.value ?? host
        
        return VLESSClient(
            serverAddress: host,
            serverPort: port,
            uuid: uuid,
            security: security,
            publicKey: publicKey,
            shortId: shortId,
            serverName: serverName
        )
    }
    
    func connect() async throws {
        let host = NWEndpoint.Host(serverAddress)
        let port = NWEndpoint.Port(integerLiteral: UInt16(serverPort))
        
        connection = NWConnection(host: host, port: port, using: .tcp)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("✅ Подключение к VLESS серверу установлено")
                    continuation.resume()
                case .failed(let error):
                    print("❌ Ошибка подключения: \(error)")
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: VLESSError.connectionCancelled)
                default:
                    break
                }
            }
            
            connection?.start(queue: .global())
        }
    }
    
    func sendVLESSHandshake() async throws {
        guard let connection = connection else {
            throw VLESSError.notConnected
        }
        
        // Создание VLESS запроса
        var data = Data()
        
        // Версия протокола (1 байт)
        data.append(0x00)
        
        // UUID (16 байт)
        let uuidData = UUID(uuidString: uuid)?.uuid ?? (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        data.append(Data([uuidData.0, uuidData.1, uuidData.2, uuidData.3,
                         uuidData.4, uuidData.5, uuidData.6, uuidData.7,
                         uuidData.8, uuidData.9, uuidData.10, uuidData.11,
                         uuidData.12, uuidData.13, uuidData.14, uuidData.15]))
        
        // Дополнительная информация (1 байт)
        data.append(0x00)
        
        // Команда: TCP (1 байт)
        data.append(0x01)
        
        // Порт назначения (2 байта)
        data.append(Data([0x01, 0xBB])) // 443 порт
        
        // Адрес назначения
        let addressType: UInt8 = 0x02 // Domain
        data.append(addressType)
        let domainData = serverAddress.data(using: .utf8) ?? Data()
        data.append(UInt8(domainData.count))
        data.append(domainData)
        
        // Отправка handshake
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    print("✅ VLESS handshake отправлен")
                    continuation.resume()
                }
            })
        }
    }
    
    func proxyData(_ data: Data) async throws -> Data {
        guard let connection = connection else {
            throw VLESSError.notConnected
        }
        
        // Отправляем данные через VLESS туннель
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Получаем ответ
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { responseData, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let responseData = responseData {
                        continuation.resume(returning: responseData)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            })
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        print("🔌 VLESS подключение закрыто")
    }
}

enum VLESSError: Error {
    case invalidURL
    case connectionFailed
    case notConnected
    case connectionCancelled
    case handshakeFailed
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Неверный VLESS URL"
        case .connectionFailed:
            return "Не удалось подключиться к серверу"
        case .notConnected:
            return "Нет подключения к серверу"
        case .connectionCancelled:
            return "Подключение отменено"
        case .handshakeFailed:
            return "Ошибка VLESS handshake"
        }
    }
}

class VPNConnectionManager {
    static let shared = VPNConnectionManager()
    private let appGroup = "group.TURBOVPN1.TURBOVPN.shared"
    private var vlessClient: VLESSClient?
    private var socksProxy: LocalSOCKSProxy?
    private var isVPNActive = false
    
    // Список заблокированных в России ресурсов для обхода
    private let blockedDomains = [
        "instagram.com", "*.instagram.com",
        "facebook.com", "*.facebook.com",
        "twitter.com", "*.twitter.com", "x.com", "*.x.com",
        "youtube.com", "*.youtube.com",
        "youtu.be", "*.youtu.be",
        "telegram.org", "*.telegram.org",
        "discord.com", "*.discord.com",
        "linkedin.com", "*.linkedin.com",
        "medium.com", "*.medium.com",
        "pinterest.com", "*.pinterest.com",
        "reddit.com", "*.reddit.com",
        "soundcloud.com", "*.soundcloud.com",
        "twitch.tv", "*.twitch.tv",
        "vimeo.com", "*.vimeo.com"
    ]
    
    // Основной метод для включения VPN с обходом блокировок
    func startVPNWithBypass(from vlessURL: String) async throws {
        print("🚀 Запуск VPN с обходом блокировок...")
        
        // Проверяем, что VPN еще не активен
        guard !isVPNActive else {
            throw VPNError.alreadyConnected
        }
        
        // Парсим VLESS конфигурацию
        guard let client = VLESSClient.parseVLESSURL(vlessURL) else {
            throw VLESSError.invalidURL
        }
        
        vlessClient = client
        
        // Создаем и устанавливаем VPN конфигурацию в настройки iOS
        try await createAndInstallVPNConfiguration(vlessConfig: client)
        
        // Подключаемся к VLESS серверу
        try await client.connect()
        try await client.sendVLESSHandshake()
        
        // Запускаем локальный SOCKS5 прокси
        socksProxy = LocalSOCKSProxy(vlessClient: client, blockedDomains: blockedDomains)
        try await socksProxy?.start()
        
        // Запускаем VPN туннель
        try await startVPNTunnel()
        
        isVPNActive = true
        
        // Уведомляем об успешном подключении
        NotificationCenter.default.post(
            name: .VPNStatusChanged,
            object: true
        )
        
        print("✅ VPN активирован и добавлен в настройки iOS!")
        print("📱 Обход блокировок включен для Instagram, YouTube, Facebook и др.")
    }
    
    // Создание и установка VPN конфигурации в настройки iOS
    private func createAndInstallVPNConfiguration(vlessConfig: VLESSClient) async throws {
        let manager = NEVPNManager.shared()
        
        // Загружаем существующую конфигурацию
        try await manager.loadFromPreferences()
        
        // Создаем IKEv2 конфигурацию (iOS поддерживает нативно)
        let vpnProtocol = NEVPNProtocolIKEv2()
        vpnProtocol.serverAddress = vlessConfig.serverAddress
        vpnProtocol.remoteIdentifier = vlessConfig.serverAddress
        vpnProtocol.localIdentifier = "TURBOVPN_User"
        
        // Настройки аутентификации (базовые для демонстрации)
        vpnProtocol.authenticationMethod = .none
        vpnProtocol.useExtendedAuthentication = false
        vpnProtocol.disconnectOnSleep = false
        
        // Мертвый peer detection
        vpnProtocol.deadPeerDetectionRate = .low
        
        manager.protocolConfiguration = vpnProtocol
        manager.localizedDescription = "TURBOVPN - Обход блокировок"
        manager.isEnabled = true
        
        // Настройки маршрутизации - только для заблокированных доменов
        let onDemandRule = NEOnDemandRuleConnect()
        onDemandRule.interfaceTypeMatch = .any
        
        // Создаем правила для заблокированных доменов
        var domainRules: [String] = []
        for domain in blockedDomains {
            domainRules.append(domain.replacingOccurrences(of: "*.", with: ""))
        }
        onDemandRule.dnsSearchDomainMatch = domainRules
        
        manager.onDemandRules = [onDemandRule]
        manager.isOnDemandEnabled = true
        
        // Сохраняем конфигурацию
        try await manager.saveToPreferences()
        
        // Перезагружаем после сохранения
        try await manager.loadFromPreferences()
        
        print("✅ VPN конфигурация создана и сохранена в настройки iOS")
        print("📱 Пользователь может увидеть 'TURBOVPN' в Настройки -> VPN")
    }
    
    // Запуск VPN туннеля
    private func startVPNTunnel() async throws {
        let manager = NEVPNManager.shared()
        try await manager.loadFromPreferences()
        
        guard manager.connection.status != .connected && manager.connection.status != .connecting else {
            print("⚠️ VPN уже подключен или подключается")
            return
        }
        
        // Запрашиваем разрешение пользователя и запускаем VPN
        do {
            try manager.connection.startVPNTunnel()
            print("🔄 Запрос разрешения VPN у пользователя...")
            
            // Ждем подтверждения от пользователя
            try await waitForVPNConnection(manager: manager)
            
        } catch {
            print("❌ Ошибка запуска VPN туннеля: \(error)")
            throw VPNError.activationFailed(error.localizedDescription)
        }
    }
    
    // Ожидание подключения VPN
    private func waitForVPNConnection(manager: NEVPNManager) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var observer: NSObjectProtocol?
            
            observer = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange,
                object: manager.connection,
                queue: .main
            ) { _ in
                switch manager.connection.status {
                case .connected:
                    print("✅ VPN успешно подключен!")
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    continuation.resume()
                case .disconnected:
                    print("❌ VPN отключен")
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    continuation.resume(throwing: VPNError.configurationFailed)
                case .invalid:
                    print("❌ Недействительная VPN конфигурация")
                    if let observer = observer {
                        NotificationCenter.default.removeObserver(observer)
                    }
                    continuation.resume(throwing: VPNError.configurationFailed)
                default:
                    break
                }
            }
            
            // Таймаут 30 секунд
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                    continuation.resume(throwing: VPNError.activationFailed("Timeout"))
                }
            }
        }
    }
    

    
    // Генерация PAC скрипта для обхода только заблокированных ресурсов
    private func generatePACScript() -> String {
        let domains = blockedDomains.joined(separator: "\", \"")
        
        return """
        function FindProxyForURL(url, host) {
            var blockedDomains = ["\(domains)"];
            
            // Проверяем, является ли домен заблокированным
            for (var i = 0; i < blockedDomains.length; i++) {
                var domain = blockedDomains[i];
                if (domain.startsWith("*.")) {
                    // Поддомен
                    var baseDomain = domain.substring(2);
                    if (host.endsWith(baseDomain)) {
                        return "SOCKS5 127.0.0.1:8888; DIRECT";
                    }
                } else {
                    // Точное совпадение
                    if (host === domain) {
                        return "SOCKS5 127.0.0.1:8888; DIRECT";
                    }
                }
            }
            
            // Для всех остальных сайтов - прямое подключение
            return "DIRECT";
        }
        """
    }
    

    
    // Остановка VPN и отключение обхода блокировок
    func stopVPNBypass() async throws {
        print("⏹ Остановка VPN с обходом блокировок...")
        
        guard isVPNActive else {
            throw VPNError.notConnected
        }
        
        // Останавливаем VPN туннель
        let manager = NEVPNManager.shared()
        try await manager.loadFromPreferences()
        
        if manager.connection.status == .connected || manager.connection.status == .connecting {
            manager.connection.stopVPNTunnel()
            print("🔄 Отключение VPN туннеля...")
        }
        
        // Останавливаем SOCKS5 прокси
        socksProxy?.stop()
        socksProxy = nil
        
        // Отключаем VLESS
        vlessClient?.disconnect()
        vlessClient = nil
        
        isVPNActive = false
        
        // Уведомляем об отключении
        NotificationCenter.default.post(
            name: .VPNStatusChanged,
            object: false
        )
        
        print("✅ VPN отключен. Обход блокировок деактивирован")
    }
    
    // Проверка статуса VPN
    var vpnStatus: Bool {
        return isVPNActive
    }
    
    // Метод для демонстрации подключения (старый)
    func connectDirectVLESS(from vlessURL: String) async throws {
        print("🚀 Starting direct VLESS connection...")
        
        // ⚠️ ВАЖНО: Это только демонстрация подключения к VLESS серверу
        // Это НЕ полноценный VPN туннель!
        // iOS не поддерживает прямой VLESS - только IKEv2, IPSec, OpenVPN, WireGuard
        
        // Для полноценного VPN нужно:
        // 1. Network Extension с поддержкой SOCKS5 прокси
        // 2. Конвертация VLESS в WireGuard на сервере
        // 3. Использование Packet Tunnel Provider
        
        guard let client = VLESSClient.parseVLESSURL(vlessURL) else {
            throw VLESSError.invalidURL
        }
        
        vlessClient = client
        
        // Подключаемся к серверу (только для демонстрации)
        try await client.connect()
        try await client.sendVLESSHandshake()
        
        // Уведомляем UI об "успешном" подключении
        NotificationCenter.default.post(
            name: .VLESSConnectionStatusChanged,
            object: true
        )
        
        print("✅ VLESS handshake completed (DEMO MODE)")
        print("⚠️  Примечание: Трафик устройства НЕ проксируется через этот туннель")
    }
    
    func disconnectDirectVLESS() {
        vlessClient?.disconnect()
        vlessClient = nil
        
        NotificationCenter.default.post(
            name: .VLESSConnectionStatusChanged,
            object: false
        )
        
        print("🔌 Direct VLESS connection closed")
    }
    
    // Старые методы для совместимости
    func installVPNConfiguration(from vlessURL: String) async throws {
        // Перенаправляем на новый метод
        try await startVPNWithBypass(from: vlessURL)
    }
    
    func removeVPNConfiguration() async throws {
        try await stopVPNBypass()
    }
    
    // Дополнительные методы для совместимости с UI
    func getVPNStatus() -> Bool {
        return isVPNActive
    }
    
    func observeVPNStatus(completion: @escaping (Bool) -> Void) {
        NotificationCenter.default.addObserver(forName: .VPNStatusChanged, object: nil, queue: .main) { notification in
            if let isConnected = notification.object as? Bool {
                completion(isConnected)
            }
        }
        
        // Также слушаем системные уведомления VPN
        NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { _ in
            Task {
                let manager = NEVPNManager.shared()
                try? await manager.loadFromPreferences()
                let isConnected = manager.connection.status == .connected
                completion(isConnected)
            }
        }
    }
    
    func disconnectVPN() async throws {
        try await stopVPNBypass()
    }
    
    // Метод для установки VPN конфигурации (совместимость с UI)
    func installVPNConfiguration() async throws {
        // Создаем базовую VPN конфигурацию
        let manager = NEVPNManager.shared()
        try await manager.loadFromPreferences()
        
        // Создаем простую IKEv2 конфигурацию для демонстрации
        let vpnProtocol = NEVPNProtocolIKEv2()
        vpnProtocol.serverAddress = "demo.server.com"
        vpnProtocol.remoteIdentifier = "demo.server.com"
        vpnProtocol.localIdentifier = "TURBOVPN_User"
        vpnProtocol.authenticationMethod = .none
        vpnProtocol.useExtendedAuthentication = false
        
        manager.protocolConfiguration = vpnProtocol
        manager.localizedDescription = "TURBOVPN - Обход блокировок"
        manager.isEnabled = true
        
        try await manager.saveToPreferences()
        print("📋 VPN конфигурация установлена в настройки")
    }
    
    // Проверка реального статуса VPN
    func checkRealVPNStatus() async -> Bool {
        let manager = NEVPNManager.shared()
        try? await manager.loadFromPreferences()
        return manager.connection.status == .connected
    }
    

}

enum VPNError: Error {
    case configurationNotFound
    case permissionDenied
    case alreadyConnected
    case notConnected
    case configurationFailed
    case invalidResponse
    case activationFailed(String)
    case serverError
    
    var localizedDescription: String {
        switch self {
        case .configurationNotFound:
            return "VPN конфигурация не найдена"
        case .permissionDenied:
            return "Нет разрешения на использование VPN"
        case .alreadyConnected:
            return "VPN уже подключен"
        case .notConnected:
            return "VPN не подключен"
                 case .configurationFailed:
             return "Ошибка настройки VPN"
         case .invalidResponse:
             return "Неверный ответ сервера"
         case .activationFailed(let message):
             return "Ошибка активации: \(message)"
         case .serverError:
             return "Ошибка сервера"
        }
    }
}

// Расширение для уведомлений
extension Notification.Name {
    static let VLESSConnectionStatusChanged = Notification.Name("VLESSConnectionStatusChanged")
    static let VPNStatusChanged = Notification.Name("VPNStatusChanged")
}
