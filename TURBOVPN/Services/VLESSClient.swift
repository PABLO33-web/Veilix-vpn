import Foundation
@preconcurrency import Network
import CryptoKit

class VLESSClient {
    let serverAddress: String
    let serverPort: Int
    let uuid: String
    
    private var connection: NWConnection?
    private var isConnected = false
    
    init(serverAddress: String, serverPort: Int, uuid: String) {
        self.serverAddress = serverAddress
        self.serverPort = serverPort
        self.uuid = uuid
    }
    
    // Метод для парсинга VLESS URL
    static func parseVLESSURL(_ url: String) -> VLESSClient? {
        // Пример VLESS URL: vless://uuid@server:port?type=tcp#name
        guard url.hasPrefix("vless://") else { return nil }
        
        let urlString = String(url.dropFirst(8))
        let components = urlString.components(separatedBy: "@")
        guard components.count >= 2 else { return nil }
        
        let uuid = components[0]
        let serverPart = components[1].components(separatedBy: "?")[0]
        let serverComponents = serverPart.components(separatedBy: ":")
        
        guard serverComponents.count == 2,
              let port = Int(serverComponents[1]) else { return nil }
        
        let server = serverComponents[0]
        
        return VLESSClient(serverAddress: server, serverPort: port, uuid: uuid)
    }
    
    func connect() async throws {
        guard !isConnected else { return }
        
        let host = NWEndpoint.Host(serverAddress)
        let port = NWEndpoint.Port(integerLiteral: UInt16(serverPort))
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        
        connection = NWConnection(to: endpoint, using: .tcp)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.isConnected = true
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            
            connection?.start(queue: .global())
        }
    }
    
    func sendVLESSHandshake() async throws {
        guard isConnected else {
            throw VLESSError.notConnected
        }
        
        // Создаем VLESS handshake
        let handshake = createVLESSHandshake()
        
        return try await withCheckedThrowingContinuation { continuation in
            connection?.send(content: handshake, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
    
    private func createVLESSHandshake() -> Data {
        // Упрощенная версия VLESS handshake
        var handshake = Data()
        
        // Version (1 byte)
        handshake.append(0x00)
        
        // UUID (16 bytes)
        if let uuidData = UUID(uuidString: uuid)?.uuid {
            handshake.append(contentsOf: [
                uuidData.0, uuidData.1, uuidData.2, uuidData.3,
                uuidData.4, uuidData.5, uuidData.6, uuidData.7,
                uuidData.8, uuidData.9, uuidData.10, uuidData.11,
                uuidData.12, uuidData.13, uuidData.14, uuidData.15
            ])
        } else {
            // Fallback UUID если парсинг не удался
            handshake.append(contentsOf: Array(repeating: UInt8(0), count: 16))
        }
        
        // Additional options length (1 byte)
        handshake.append(0x00)
        
        // Command (1 byte) - TCP = 0x01
        handshake.append(0x01)
        
        // Port (2 bytes, big endian)
        handshake.append(UInt8(443 >> 8))
        handshake.append(UInt8(443 & 0xFF))
        
        // Address type (1 byte) - Domain = 0x02
        handshake.append(0x02)
        
        // Domain length and domain
        let domain = "example.com"
        handshake.append(UInt8(domain.count))
        handshake.append(contentsOf: domain.utf8)
        
        return handshake
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }
    
    // Метод для проксирования данных
    func proxyData(_ data: Data) async throws -> Data {
        guard isConnected else {
            throw VLESSError.notConnected
        }
        
        // Отправляем данные через VLESS туннель
        return try await withCheckedThrowingContinuation { continuation in
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    // В реальной реализации здесь нужно получить ответ
                    continuation.resume(returning: Data())
                }
            })
        }
    }
}

enum VLESSError: Error {
    case invalidURL
    case notConnected
    case handshakeFailed
} 