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
        // Добавляем эмодзи флага Нидерландов и название страны к email
        let countryLabel = "%F0%9F%87%B3%F0%9F%87%B1%20%D0%9D%D0%B8%D0%B4%D0%B5%D1%80%D0%BB%D0%B0%D0%BD%D0%B4%D1%8B-\(email)"
        return "vless://\(id)@\(serverAddress):\(port)/?type=\(network)&security=\(security)&pbk=\(publicKey)&fp=\(fingerprint)&sni=\(serverName)&sid=\(shortId)&spx=\(spiderX)#\(countryLabel)"
    }
} 