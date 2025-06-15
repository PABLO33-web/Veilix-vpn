import Foundation
import NetworkExtension

class VPNConnectionManager {
    static let shared = VPNConnectionManager()
    private let appGroup = "group.com.yourcompany.turbovpn"
    
    func installVPNConfiguration(from vlessURL: String) async throws {
        guard let url = URL(string: vlessURL),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw VPNError.configurationError("Invalid VLESS URL")
        }
        
        let manager = NEVPNManager.shared()
        try await manager.loadFromPreferences()
        
        // Создаем конфигурацию IKEv2
        let config = NEVPNProtocolIKEv2()
        config.serverAddress = components.host ?? ""
        config.remoteIdentifier = components.host
        config.useExtendedAuthentication = true
        config.authenticationMethod = .none
        
        // Добавляем дополнительные параметры из URL
        let queryItems = components.queryItems ?? []
        for item in queryItems {
            switch item.name {
            case "security":
                config.serverCertificateIssuerCommonName = item.value
            case "pbk":
                config.serverCertificateCommonName = item.value
            default:
                break
            }
        }
        
        manager.protocolConfiguration = config
        manager.localizedDescription = "VeilixVPN"
        manager.isEnabled = true
        manager.isOnDemandEnabled = false
        
        try await manager.saveToPreferences()
        try await manager.connection.startVPNTunnel()
    }
    
    func disconnectVPN() async throws {
        NEVPNManager.shared().connection.stopVPNTunnel()
    }
    
    func getVPNStatus() -> NEVPNStatus {
        return NEVPNManager.shared().connection.status
    }
    
    func observeVPNStatus(completion: @escaping (NEVPNStatus) -> Void) {
        NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { notification in
            guard let connection = notification.object as? NEVPNConnection else { return }
            completion(connection.status)
        }
    }
} 
 
