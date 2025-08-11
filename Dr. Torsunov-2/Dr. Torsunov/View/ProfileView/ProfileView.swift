
import SwiftUI


struct ProfileView: View {
    @StateObject var viewModel: ProfileViewModel
    @State private var showContent = false
    @State private var showPersonalView = false

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [.orange, .red],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer().frame(height: 130)

                VStack {
                    HStack {
                        if showPersonalView {
                            Button {
                                withAnimation {
                                    showPersonalView = false
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .foregroundColor(.white)
                                Text("Назад")
                                    .foregroundColor(.white)
                            }
                        } else {
                            Spacer().frame(width: 60)
                        }

                        Spacer()

                        Text(viewModel.personalVM.name)
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        Spacer().frame(width: 60)
                    }
                    .padding(.horizontal)
                    .padding(.top, 50)

                    // Контент
                    VStack(spacing: 0) {
                        Divider().background(Color.gray.opacity(0.5))

                        if showPersonalView {
                            PersonalView(viewModel: viewModel.personalVM)
                                .background(Color.black)
                                .transition(.move(edge: .trailing))
                        } else {
                            profileRow(icon: "person.fill", title: "Личные данные") {
                                withAnimation {
                                    showPersonalView = true
                                }
                            }
                            Divider().background(Color.gray.opacity(0.5))

                            profileRow(icon: "headphones", title: "Поддержка") {
                                openTelegramGroup()
                            }
                        }

                        Divider().background(Color.gray.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    Spacer()

                    Text(viewModel.appVersion)
                        .foregroundColor(.gray)
                        .font(.caption)
                        .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .offset(y: showContent ? 0 : UIScreen.main.bounds.height)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showContent)
            }

            // Фото с кнопкой редактирования
            VStack {
                Spacer().frame(height: 40)
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 100)

                    if let url = viewModel.photoURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image.resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            case .failure(_):
                                Image(systemName: "person.fill")
                                    .foregroundColor(.white)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundColor(.white)
                    }

                    // Кнопка редактирования
                    Button(action: {
                        viewModel.showPhotoPicker = true
                    }) {
                        Image(systemName: "camera")
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .foregroundColor(.white)
                    }
                    .offset(x: 5, y: 5)
                }
            }
            .zIndex(1)
        }
        .onAppear {
            showContent = true
        }
        .sheet(isPresented: $viewModel.showPhotoPicker) {
            ImagePicker(image: Binding(
                get: { nil },
                set: { image in
                    if let image = image {
                        viewModel.setPhoto(image)
                    }
                }
            ))
        }
    }

    private func openTelegramGroup() {
        if let url = URL(string: "https://t.me/vash_Boytik") {
            UIApplication.shared.open(url)
        }
    }

    @ViewBuilder
    private func profileRow(icon: String, title: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.green)
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}

