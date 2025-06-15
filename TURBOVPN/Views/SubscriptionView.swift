import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {
    }
}

struct SubscriptionView: View {
    @StateObject private var viewModel = SubscriptionViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // ... existing subscription options ...
                }
                .padding()
            }
            .navigationTitle("Подписка")
            .navigationBarItems(trailing: Button("Закрыть") {
                presentationMode.wrappedValue.dismiss()
            })
            .overlay(
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black.opacity(0.2))
                    }
                }
            )
            .overlay(
                Group {
                    if viewModel.showToast {
                        Text(viewModel.toastMessage)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                            .padding(.bottom, 20)
                    }
                }
                .animation(.easeInOut, value: viewModel.showToast),
                alignment: .bottom
            )
            .sheet(isPresented: $viewModel.showSafariView) {
                if let url = viewModel.safariURL {
                    SafariView(url: url)
                }
            }
        }
    }
} 