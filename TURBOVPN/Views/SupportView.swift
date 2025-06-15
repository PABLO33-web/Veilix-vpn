import SwiftUI

struct SupportView: View {
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 24) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                        .padding(.top, 32)
                    
                    Text("Поддержка")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Наша команда поддержки готова помочь вам с любыми вопросами")
                        .font(.body)
                        .foregroundColor(Color(.systemGray2))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        // Кнопка для связи с поддержкой
                        Button(action: {
                            if let url = URL(string: "https://t.me/mukhtar41k") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Написать в Telegram")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray2))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // Кнопка для перехода в канал
                        Button(action: {
                            if let url = URL(string: "https://t.me/veilixvpn") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "megaphone.fill")
                                Text("Наш Telegram канал")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray2))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
} 