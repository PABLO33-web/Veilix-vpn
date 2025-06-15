import SwiftUI

struct UserCabinetView: View {
    @EnvironmentObject var viewModel: SubscriptionViewModel
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 16) {
                            Text("Ваша подписка")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            // Кнопка обновления данных
                            Button(action: {
                                viewModel.refreshSubscriptionStatus()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Обновить данные")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray2))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white, lineWidth: 1)
                                )
                            }
                            
                            if let config = viewModel.vpnConfig {
                                VStack(spacing: 12) {
                                    if let stats = viewModel.userStats {
                                        HStack {
                                            Text("Email:")
                                                .foregroundColor(Color(.systemGray2))
                                            Spacer()
                                            Text(stats.email)
                                                .foregroundColor(.white)
                                        }
                                        
                                        HStack {
                                            Text("Трафик:")
                                                .foregroundColor(Color(.systemGray2))
                                            Spacer()
                                            Text(stats.trafficFormatted)
                                                .foregroundColor(.white)
                                        }
                                        
                                        HStack {
                                            Text("Статус:")
                                                .foregroundColor(Color(.systemGray2))
                                            Spacer()
                                            Text(stats.timeRemaining)
                                                .foregroundColor(stats.isExpired ? .red : .white)
                                        }
                                    }
                                    
                                    Divider()
                                        .background(Color.gray.opacity(0.3))
                                    
                                    // Кнопка копирования конфигурации
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
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                    }
                                    .disabled(viewModel.userStats?.isExpired ?? false)
                                    .opacity(viewModel.userStats?.isExpired ?? false ? 0.5 : 1)
                                }
                                .padding()
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(.systemGray2).opacity(0.5),
                                                    Color(.systemGray2).opacity(0.5)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            } else {
                                Text("У вас нет активной подписки")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .navigationTitle("Кабинет")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }
} 