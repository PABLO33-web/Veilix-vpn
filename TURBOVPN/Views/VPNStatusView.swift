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
    
    var body: some View {
        VStack(spacing: 12) {
            if let stats = viewModel.userStats {
                VStack(spacing: 16) {
                    Text("Подписка активна")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Осталось:")
                                .foregroundColor(Color(.systemGray2))
                            Spacer()
                            Text(stats.timeRemaining)
                                .foregroundColor(.white)
                        }
                        
                        HStack {
                            Text("Трафик:")
                                .foregroundColor(Color(.systemGray2))
                            Spacer()
                            Text(stats.trafficFormatted)
                                .foregroundColor(.white)
                        }
                        
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
                    }
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 1)
        )
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
} 