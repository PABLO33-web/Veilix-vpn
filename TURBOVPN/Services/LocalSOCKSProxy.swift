import Foundation
@preconcurrency import Network
import CryptoKit

class LocalSOCKSProxy {
    private var listener: NWListener?
    private var isRunning = false
    private let vlessClient: VLESSClient
    private let blockedDomains: [String]
    
    init(vlessClient: VLESSClient, blockedDomains: [String]) {
        self.vlessClient = vlessClient
        self.blockedDomains = blockedDomains
    }
    
    func start() async throws {
        guard !isRunning else { return }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: 8888)
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }
        
        listener?.start(queue: .global())
        isRunning = true
        
        print("🎯 SOCKS5 прокси запущен на порту 8888")
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("⏹ SOCKS5 прокси остановлен")
    }
    
    private func handleConnection(_ connection: NWConnection) async {
        connection.start(queue: .global())
        
        // Простая реализация SOCKS5
        // В реальном приложении здесь была бы полная реализация SOCKS5 протокола
        print("📱 Новое SOCKS5 подключение")
        
        // Проксируем трафик через VLESS
        // Здесь должна быть логика обработки SOCKS5 запросов
    }
    
    private func shouldProxyDomain(_ domain: String) -> Bool {
        return blockedDomains.contains { pattern in
            if pattern.hasPrefix("*.") {
                let suffix = String(pattern.dropFirst(2))
                return domain.hasSuffix(suffix)
            }
            return domain == pattern
        }
    }
} 