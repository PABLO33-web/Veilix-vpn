//
//  TURBOVPNApp.swift
//  TURBOVPN
//
//  Created by 1234 on 09.02.2025.
//

import SwiftUI

@main
struct TURBOVPNApp: App {
    @StateObject private var viewModel = SubscriptionViewModel()
    
    init() {
        // Запускаем проверку истекших подписок
        SubscriptionManager.shared.startExpiryCheck()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onOpenURL { url in
                    // Обработка возврата из оплаты
                    if url.scheme == "veilixvpn", url.host == "payment" {
                        // Пример: veilixvpn://payment?status=success&payment_id=...
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                        var paymentId: String? = nil
                        var status: String? = nil
                        components?.queryItems?.forEach { item in
                            if item.name == "payment_id" { paymentId = item.value }
                            if item.name == "status" { status = item.value }
                        }
                        if status == "success", let paymentId = paymentId {
                            viewModel.handlePaymentCallback(success: true, paymentId: paymentId)
                        } else {
                            viewModel.handlePaymentCallback(success: false, paymentId: paymentId ?? "")
                        }
                    }
                }
        }
    }
}
