import SwiftUI

struct InstructionStep: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.body, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color("NeonCyan"))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(.body))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

struct VPNStatusView: View {
    @EnvironmentObject var viewModel: SubscriptionViewModel
    @State private var showInstructions = false
    @State private var isVPNConnected = false
    @State private var isConnecting = false
    
    var body: some View {
        VStack(spacing: 12) {
            if let stats = viewModel.userStats {
                VStack(spacing: 16) {
                    Text(stats.isExpired ? "Подписка истекла" : "Подписка активна")
                        .font(.headline)
                        .foregroundColor(stats.isExpired ? .red : .white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Статус:")
                                .foregroundColor(Color(.systemGray2))
                            Spacer()
                            Text(stats.timeRemaining)
                                .foregroundColor(stats.isExpired ? .red : .white)
                        }
                        
                        HStack {
                            Text("Трафик:")
                                .foregroundColor(Color(.systemGray2))
                            Spacer()
                            Text(stats.trafficFormatted)
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Text("Сервер:")
                                .foregroundColor(Color(.systemGray2))
                            Spacer()
                            Text("Нидерланды")
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                }
            }
            
            // Главная кнопка VPN
            if let vpnConfig = viewModel.vpnConfig {
                VStack(spacing: 16) {
                    // Большая кнопка включения/выключения VPN
                    Button(action: {
                        Task {
                            if isVPNConnected {
                                await disconnectVPN()
                            } else {
                                await connectVPN(config: vpnConfig)
                            }
                        }
                    }) {
                        VStack(spacing: 12) {
                            // Анимированная иконка подключения
                            ZStack {
                                Circle()
                                    .fill(isVPNConnected ? Color.green : Color("NeonCyan"))
                                    .frame(width: 80, height: 80)
                                    .scaleEffect(isConnecting ? 1.1 : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isConnecting)
                                
                                Image(systemName: isVPNConnected ? "checkmark.shield.fill" : "shield.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.black)
                            }
                            
                            VStack(spacing: 4) {
                                Text(isConnecting ? "Подключение..." : (isVPNConnected ? "VPN ВКЛЮЧЕН" : "VPN ВЫКЛЮЧЕН"))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                if isVPNConnected {
                                    Text("🚀 Обход блокировок активен")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("Нажмите для включения VPN")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(isVPNConnected ? Color.green : Color("NeonCyan"), lineWidth: 2)
                                )
                        )
                    }
                    .disabled(isConnecting)
                    
                    // Информация о заблокированных ресурсах
                    if isVPNConnected {
                        VStack(spacing: 8) {
                            Text("🔓 Разблокированные ресурсы:")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(["Instagram", "YouTube", "Facebook", "Twitter", "Discord", "LinkedIn"], id: \.self) { service in
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text(service)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                    }
                    
                    // Дополнительные опции
                    HStack(spacing: 12) {
                        Button(action: {
                            showInstructions = true
                        }) {
                            VStack {
                                Image(systemName: "questionmark.circle")
                                    .font(.title3)
                                Text("Инструкция")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray2))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            viewModel.copyConfig()
                        }) {
                            VStack {
                                Image(systemName: "doc.on.doc")
                                    .font(.title3)
                                Text("Копировать")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color("NeonCyan"))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.top)
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 1)
        )
        .onAppear {
            // Слушаем изменения статуса VPN подключения
            NotificationCenter.default.addObserver(
                forName: .VPNStatusChanged,
                object: nil,
                queue: .main
            ) { notification in
                if let isConnected = notification.object as? Bool {
                    isVPNConnected = isConnected
                    isConnecting = false
                }
            }
            
            // Проверяем текущий статус VPN
            isVPNConnected = VPNConnectionManager.shared.vpnStatus
        }
        .sheet(isPresented: $showInstructions) {
            TabView {
                NavigationView {
                    VStack(spacing: 16) {
                        Text("Инструкция по подключению")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            InstructionStep(number: 1, text: "Скопируйте конфигурацию")
                            InstructionStep(number: 2, text: "Установите приложение Shadowrocket из App Store")
                            InstructionStep(number: 3, text: "Откройте Shadowrocket")
                            InstructionStep(number: 4, text: "Нажмите + в правом верхнем углу")
                            InstructionStep(number: 5, text: "Вставьте скопированную конфигурацию")
                            InstructionStep(number: 6, text: "Нажмите 'Сохранить' и включите VPN")
                        }
                        .padding()
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                        
                        Button(action: {
                            viewModel.copyConfig()
                        }) {
                            HStack {
                                Image(systemName: "doc.on.doc")
                                Text("Копировать конфигурацию")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray2))
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        
                        Link("Скачать Shadowrocket",
                             destination: URL(string: "https://apps.apple.com/app/shadowrocket/id932747118")!)
                            .font(.footnote)
                            .foregroundColor(Color("NeonCyan"))
                    }
                    .padding()
                    .background(Color.black.edgesIgnoringSafeArea(.all))
                    .navigationTitle("Инструкция")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
        }
    }
    
    // Функция для подключения VPN с обходом блокировок
    private func connectVPN(config: String) async {
        isConnecting = true
        
        do {
            try await VPNConnectionManager.shared.startVPNWithBypass(from: config)
            await MainActor.run {
                viewModel.showTemporaryToast("🚀 VPN подключен! Обход блокировок активен")
                isVPNConnected = true
                isConnecting = false
            }
        } catch {
            await MainActor.run {
                viewModel.showTemporaryToast("❌ Ошибка подключения: \(error.localizedDescription)")
                isConnecting = false
            }
        }
    }
    
    // Функция для отключения VPN
    private func disconnectVPN() async {
        isConnecting = true
        
        do {
            try await VPNConnectionManager.shared.stopVPNBypass()
            await MainActor.run {
                viewModel.showTemporaryToast("🔌 VPN отключен")
                isVPNConnected = false
                isConnecting = false
            }
        } catch {
            await MainActor.run {
                viewModel.showTemporaryToast("❌ Ошибка отключения: \(error.localizedDescription)")
                isConnecting = false
            }
        }
    }
} 