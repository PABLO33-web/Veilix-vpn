import SwiftUI
import NetworkExtension

struct MainView: View {
    @EnvironmentObject var viewModel: SubscriptionViewModel
    @State private var isConnecting = false
    @State private var vpnStatus: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Text("VeilixVPN")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal)

            Spacer()

            Text("Нажмите на картинку, чтобы включить VPN")
                .foregroundColor(.white)
                .font(.body)
                .padding(.bottom, 8)

            Button(action: {
                handleVPNButton()
            }) {
                Image(vpnStatus ? "vpn_on" : "vpn_off")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 240, height: 240)
            }
            .disabled(isConnecting || (viewModel.vpnConfig == nil) || (viewModel.userStats?.isExpired ?? true))
            .opacity((viewModel.vpnConfig == nil || (viewModel.userStats?.isExpired ?? true)) ? 0.5 : 1)
            .padding(.bottom, 8)

            Text(vpnStatus ? "VPN включен" : "VPN отключен")
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
                if vpnStatus {
                    try await VPNConnectionManager.shared.disconnectVPN()
                } else {
                    try await VPNConnectionManager.shared.startVPNWithBypass(from: config)
                }
            } catch {
                // Можно добавить отображение ошибки
            }
            isConnecting = false
        }
    }
} 