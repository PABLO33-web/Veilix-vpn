import SwiftUI

struct InstructionsView: View {
    @EnvironmentObject var viewModel: SubscriptionViewModel
    @State private var selectedPlatform: Platform = .macos
    
    enum Platform: String, CaseIterable {
        case macos = "MacOS"
        case windows = "Windows"
        case linux = "Linux"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Переключатель платформ
                        HStack(spacing: 0) {
                            ForEach(Platform.allCases, id: \ .self) { platform in
                                Button(action: {
                                    withAnimation {
                                        selectedPlatform = platform
                                    }
                                }) {
                                    Text(platform.rawValue)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(selectedPlatform == platform ? .white : Color(.systemGray2))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedPlatform == platform ?
                                            Color("NeonCyan") :
                                            Color.black.opacity(0.3)
                                        )
                                }
                            }
                        }
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                        .padding(.horizontal)
                        
                        // Инструкции для выбранной платформы
                        switch selectedPlatform {
                        case .macos:
                            macOSInstructions
                        case .windows:
                            windowsInstructions
                        case .linux:
                            linuxInstructions
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Инструкция")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var macOSInstructions: some View {
        VStack(spacing: 16) {
            Link("Открыть подробную инструкцию",
                 destination: URL(string: "https://telegra.ph/Instrukciya-dlya-MacOS-01-11")!)
                .foregroundColor(Color("NeonCyan"))
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionStep(number: 1, text: "Скачайте V2rayU")
                InstructionStep(number: 2, text: "Откройте приложение")
                InstructionStep(number: 3, text: "Нажмите на значок в строке меню")
                InstructionStep(number: 4, text: "Выберите 'Import Config URL'")
                InstructionStep(number: 5, text: "Вставьте скопированную конфигурацию")
                InstructionStep(number: 6, text: "Включите VPN")
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
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }
    
    private var windowsInstructions: some View {
        VStack(spacing: 16) {
            Link("Открыть подробную инструкцию",
                 destination: URL(string: "https://telegra.ph/Instrukciya-dlya-Windows-01-11")!)
                .foregroundColor(Color("NeonCyan"))
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionStep(number: 1, text: "Скачайте v2rayN")
                InstructionStep(number: 2, text: "Распакуйте архив")
                InstructionStep(number: 3, text: "Запустите v2rayN.exe")
                InstructionStep(number: 4, text: "Нажмите правой кнопкой на значок в трее")
                InstructionStep(number: 5, text: "Выберите 'Import from clipboard'")
                InstructionStep(number: 6, text: "Включите VPN")
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
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }
    
    private var linuxInstructions: some View {
        VStack(spacing: 16) {
            Link("Открыть подробную инструкцию",
                 destination: URL(string: "https://telegra.ph/Instrukciya-dlya-Linux-Ubuntu-AppImage-01-11")!)
                .foregroundColor(Color("NeonCyan"))
            
            VStack(alignment: .leading, spacing: 8) {
                InstructionStep(number: 1, text: "Скачайте V2rayA AppImage")
                InstructionStep(number: 2, text: "Сделайте файл исполняемым")
                InstructionStep(number: 3, text: "Запустите приложение")
                InstructionStep(number: 4, text: "Откройте веб-интерфейс")
                InstructionStep(number: 5, text: "Импортируйте конфигурацию")
                InstructionStep(number: 6, text: "Включите VPN")
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
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
    }
} 