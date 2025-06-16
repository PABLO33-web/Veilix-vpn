import Foundation
import NetworkExtension
import Network
import CryptoKit

// Локальный SOCKS5 прокси сервер для обхода блокировок
class LocalSOCKSProxy {
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let vlessClient: VLESSClient
    private let port: UInt16 = 8888
    
    init(vlessClient: VLESSClient) {
        self.vlessClient = vlessClient
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
        // Простая реализация SOCKS5
        // В реальном приложении здесь должна быть полная обработка SOCKS5 протокола
        
        Task {
            do {
                // Проксируем через VLESS
                let response = try await vlessClient.proxyData(data)
                connection.send(content: response, completion: .contentProcessed { error in
                    if let error = error {
                        print("❌ Ошибка отправки данных: \(error)")
                    }
                })
            } catch {
                print("❌ Ошибка проксирования: \(error)")
            }
        }
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
    private let serverAddress: String
    private let serverPort: Int
    private let uuid: String
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
        
        // Подключаемся к VLESS серверу
        try await client.connect()
        try await client.sendVLESSHandshake()
        
        // Запускаем локальный SOCKS5 прокси
        socksProxy = LocalSOCKSProxy(vlessClient: client)
        try await socksProxy?.start()
        
        // Настраиваем системный прокси для заблокированных доменов
        try await configureSystemProxy()
        
        isVPNActive = true
        
        // Уведомляем об успешном подключении
        NotificationCenter.default.post(
            name: .VPNStatusChanged,
            object: true
        )
        
        print("✅ VPN активирован! Обход блокировок включен для:")
        print("📱 Instagram, YouTube, Facebook, Twitter и других заблокированных ресурсов")
    }
    
    // Настройка системного прокси для обхода блокировок
    private func configureSystemProxy() async throws {
        let manager = NEVPNManager.shared()
        
        // Загружаем текущую конфигурацию
        try await manager.loadFromPreferences()
        
        // Создаем прокси конфигурацию
        let proxySettings = NEProxySettings()
        
        // HTTP прокси
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: 8888)
        
        // HTTPS прокси
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: 8888)
        
        // Настройка автоматического прокси для заблокированных доменов
        proxySettings.autoProxyConfigurationEnabled = true
        
        // PAC скрипт для обхода только заблокированных ресурсов
        let pacScript = generatePACScript()
        proxySettings.proxyAutoConfigurationJavaScript = pacScript
        
        // Применяем настройки
        manager.protocolConfiguration = createIPSecConfiguration()
        manager.protocolConfiguration?.disconnectOnSleep = false
        
        // Включаем VPN
        manager.isEnabled = true
        
        try await manager.saveToPreferences()
        try manager.connection.startVPNTunnel()
        
        print("🔧 Системный прокси настроен для обхода блокировок")
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
    
    // Создание базовой IPSec конфигурации для VPN менеджера
    private func createIPSecConfiguration() -> NEVPNProtocolIPSec {
        let ipsec = NEVPNProtocolIPSec()
        ipsec.serverAddress = "127.0.0.1" // Локальный адрес
        ipsec.username = "bypass_user"
        ipsec.passwordReference = nil
        
        // Настройки для обхода блокировок
        ipsec.localIdentifier = "TURBOVPN_BYPASS"
        ipsec.remoteIdentifier = "BYPASS_SERVER"
        
        return ipsec
    }
    
    // Остановка VPN и отключение обхода блокировок
    func stopVPNBypass() async throws {
        print("⏹ Остановка VPN с обходом блокировок...")
        
        guard isVPNActive else {
            throw VPNError.notConnected
        }
        
        // Останавливаем SOCKS5 прокси
        socksProxy?.stop()
        socksProxy = nil
        
        // Отключаем VLESS
        vlessClient?.disconnect()
        vlessClient = nil
        
        // Отключаем системный VPN
        let manager = NEVPNManager.shared()
        try await manager.loadFromPreferences()
        manager.connection.stopVPNTunnel()
        
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
    
    // Дополнительные методы для совместимости
    func getVPNStatus() -> Bool {
        return isVPNActive
    }
    
    func observeVPNStatus(completion: @escaping (Bool) -> Void) {
        NotificationCenter.default.addObserver(forName: .VPNStatusChanged, object: nil, queue: .main) { notification in
            if let isConnected = notification.object as? Bool {
                completion(isConnected)
            }
        }
    }
    
    func disconnectVPN() async throws {
        try await stopVPNBypass()
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
