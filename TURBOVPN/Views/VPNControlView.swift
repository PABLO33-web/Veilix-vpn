import SwiftUI
import NetworkExtension

struct VPNControlView: View {
    @EnvironmentObject var viewModel: SubscriptionViewModel
    @State private var isConnecting = false
    @State private var vpnStatus: NEVPNStatus = .disconnected
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Text("hitray")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "bell.fill")
                    .foregroundColor(.white)
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white)
            }
            .padding(.top, 16)
            .padding(.horizontal)

            Spacer()

            Text("Нажмите на кнопку, чтобы включить VPN")
                .foregroundColor(.white)
                .font(.body)
                .padding(.bottom, 8)

            Button(action: {
                handleVPNButton()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 160, height: 160)
                    Image(systemName: "power")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.black)
                }
            }
            .disabled(isConnecting || (viewModel.vpnConfig == nil) || (viewModel.userStats?.isExpired ?? true))
            .opacity((viewModel.vpnConfig == nil || (viewModel.userStats?.isExpired ?? true)) ? 0.5 : 1)
            .padding(.bottom, 8)

            Text(vpnStatus == .connected ? "VPN включен" : "VPN отключен")
                .foregroundColor(.white)
                .font(.headline)
                .padding(.bottom, 16)

            HStack {
                VStack {
                    Text("Передано")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Text("-")
                        .foregroundColor(.white)
                        .font(.body)
                }
                Spacer()
                VStack {
                    Text("Получено")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                    Text("-")
                        .foregroundColor(.white)
                        .font(.body)
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 8)

            if let stats = viewModel.userStats {
                Text("Ваш ID: " + stats.email)
                    .foregroundColor(.white)
                    .font(.footnote)
            }

            Spacer()

            HStack {
                Spacer()
                Text("Версия: 1.5")
                    .foregroundColor(.gray)
                    .font(.footnote)
                    .padding(.trailing, 16)
            }
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            vpnStatus = VPNConnectionManager.shared.getVPNStatus()
            VPNConnectionManager.shared.observeVPNStatus { status in
                self.vpnStatus = status
            }
        }
    }
    
    private func handleVPNButton() {
        guard let config = viewModel.vpnConfig else { return }
        isConnecting = true
        Task {
            do {
                if vpnStatus == .connected || vpnStatus == .connecting {
                    try await VPNConnectionManager.shared.disconnectVPN()
                } else {
                    try await VPNConnectionManager.shared.installVPNConfiguration(from: config)
                }
            } catch {
                // Можно добавить отображение ошибки
            }
            isConnecting = false
        }
    }
} 