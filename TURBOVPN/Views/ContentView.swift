import SwiftUI
import SafariServices

struct ContentView: View {
    private let subscriptions = Subscription.samples
    @EnvironmentObject var viewModel: SubscriptionViewModel
    
    var filteredSubscriptions: [Subscription] {
        return subscriptions.filter { subscription in
            if subscription.isTrial {
                return !viewModel.hasUsedTrial
            }
            return true
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                MainView()
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Главная")
                    }
                NavigationView {
                    ZStack {
                        Color.black.edgesIgnoringSafeArea(.all)
                        
                        ScrollView {
                            VStack(spacing: 24) {
                                VStack(spacing: 24) {
                                    Image("logo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 160, height: 160)
                                        .padding(.top, 8)
                                    
                                    Text("VeilixVPN")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Text("Безопасность на максимальной скорости")
                                        .font(.subheadline)
                                        .foregroundColor(Color(.systemGray2))
                                }
                                .padding(.top, 8)
                                
                                if viewModel.vpnConfig != nil {
                                    VPNStatusView()
                                        .transition(.opacity)
                                        .animation(.easeInOut(duration: 0.3), value: viewModel.vpnConfig != nil)
                                        .padding(.horizontal)
                                }
                                
                                VStack(spacing: 16) {
                                    ForEach(filteredSubscriptions) { subscription in
                                        SubscriptionCard(subscription: subscription)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.bottom, 90)
                        }
                    }
                    .navigationBarHidden(true)
                    .background(Color.black.edgesIgnoringSafeArea(.all))
                }
                .background(Color.black.edgesIgnoringSafeArea(.all))
                .tabItem {
                    Image(systemName: "creditcard.fill")
                    Text("Подписки")
                }
                
                InstructionsView()
                    .tabItem {
                        Image(systemName: "questionmark.circle.fill")
                        Text("Инструкция")
                    }
                
                SupportView()
                    .tabItem {
                        Image(systemName: "bubble.right.fill")
                        Text("Поддержка")
                    }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .tabViewStyle(DefaultTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .never))
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor.black
                
                appearance.shadowColor = nil
                appearance.shadowImage = nil
                
                let normalAttributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor(Color(.systemGray2).opacity(0.5)),
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium)
                ]
                let selectedAttributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: UIColor(Color(.systemGray2)),
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold)
                ]
                
                appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
                appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes
                appearance.stackedLayoutAppearance.normal.iconColor = UIColor(Color(.systemGray2).opacity(0.5))
                appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color(.systemGray2))
                
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
                
                UIView.setAnimationsEnabled(false)
            }
            
            if viewModel.showToast {
                ToastView(
                    message: viewModel.toastMessage,
                    isShowing: $viewModel.showToast
                )
                .padding(.horizontal)
                .offset(y: -4)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top),
                        removal: .move(edge: .top)
                    )
                )
                .zIndex(1)
            }
        }
        .sheet(isPresented: $viewModel.showSafariView, onDismiss: {
            print("[UI] SafariView dismissed, calling checkPaymentStatusAndActivate")
            viewModel.checkPaymentStatusAndActivate()
        }) {
            if let url = viewModel.safariURL {
                SafariView(url: url)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: viewModel.showToast)
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
}

struct SubscriptionCard: View {
    let subscription: Subscription
    @EnvironmentObject var viewModel: SubscriptionViewModel
    @State private var isHovered = false
    
    var isDisabled: Bool {
        viewModel.isLoading
    }
    
    var buttonText: String {
        if subscription.isTrial {
            if viewModel.vpnConfig != nil {
                return "Подписка активна"
            }
            return "Активировать пробный период"
        }
        return "Выбрать план"
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(subscription.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                if subscription.isPopular {
                    Text("Популярный")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray2))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                if subscription.isTrial {
                    Text("Пробный")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray2))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            
            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 4) {
                    if subscription.isTrial {
                        Text("Бесплатно")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color(.systemGray2))
                    } else {
                        Text("\(Int(subscription.price))₽")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color(.systemGray2))
                        
                        Text("/\(subscription.duration)")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(subscription.features, id: \.self) { feature in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(.systemGray2))
                        Text(feature)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
            }
            
            Button(action: {
                viewModel.purchaseSubscription(subscription)
            }) {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemGray2).opacity(0.8),
                                    Color(.systemGray2)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                } else {
                    Text(buttonText)
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(.systemGray2).opacity(isDisabled ? 0.3 : 0.8),
                                    Color(.systemGray2).opacity(isDisabled ? 0.3 : 1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
            }
            .disabled(isDisabled)
            .buttonStyle(ScaleButtonStyle())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 1)
        )
        .sheet(item: $viewModel.paymentURL) { paymentURL in
            SafariView(url: paymentURL.url)
        }
    }
}

// Добавим анимацию нажатия для кнопок
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SubscriptionViewModel())
    }
}

// Добавим модификатор для плавного перехода между табами
extension View {
    func smoothTabTransition() -> some View {
        self.transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: true)
    }
} 
