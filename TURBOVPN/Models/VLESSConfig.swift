import Foundation

struct VLESSConfig {
    let id: String
    let email: String
    let protocolType: String = "vless"
    let port: Int
    let network: String
    let security: String
    let publicKey: String
    let fingerprint: String
    let serverName: String
    let shortId: String
    let serverAddress: String
    let spiderX: String
    
    var asString: String {
        return "vless://\(id)@\(serverAddress):\(port)?type=\(network)&security=\(security)&pbk=\(publicKey)&fp=\(fingerprint)&sni=\(serverName)&sid=\(shortId)&spx=\(spiderX)#\(email)"
    }
} 