import SwiftUI

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct PersonalView: View {
    @ObservedObject var viewModel: PersonalViewModel
    @EnvironmentObject var auth: AppAuthState

    private let cardBackground = Color(red: 28/255, green: 28/255, blue: 30/255)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: L("personal_data"))

            PersonalInfoCard(
                email: viewModel.email,
                name: viewModel.name,
                roleTitle: viewModel.role.rawValue,
                onEditEmail: { viewModel.editingField = .email },
                onEditName: { viewModel.editingField = .name },
                onShowPhysical: { viewModel.showPhysicalDataSheet = true },
                onPickRole: { viewModel.showRolePicker = true }
            )
            .background(cardBackground)
            .cornerRadius(12)
            .padding(.horizontal)

            SectionHeader(title: L("account_actions"))

            AccountActionsCard(
                onLogoutTap: { viewModel.showLogoutAlert = true },
                onOtherTap: { viewModel.showOtherActions = true }
            )
            .background(cardBackground)
            .cornerRadius(12)
            .padding(.horizontal)

            Spacer()
        }
        .refreshable { await viewModel.loadUser() }
        .background(Color.black.ignoresSafeArea())
        .background(
            PersonalViewModals(viewModel: viewModel)
                .environmentObject(auth)
        )
        .task { await viewModel.loadUser() }
    }
}

// MARK: - Под-вью: заголовок секции
private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal)
    }
}

// MARK: - Под-вью: карточка личных данных
private struct PersonalInfoCard: View {
    let email: String
    let name: String
    let roleTitle: String
    let onEditEmail: () -> Void
    let onEditName: () -> Void
    let onShowPhysical: () -> Void
    let onPickRole: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(
                icon: "person.crop.circle.badge.checkmark",
                iconColor: .green,
                title: L("email"),
                subtitle: email,
                action: onEditEmail
            )

            DividerRow()

            InfoRow(
                icon: "person.fill",
                iconColor: .green,
                title: L("name"),
                subtitle: name,
                action: onEditName
            )

            DividerRow()

            InfoRow(
                icon: "heart.text.square",
                iconColor: .green,
                title: L("my_physical_data"),
                subtitle: nil,
                action: onShowPhysical
            )

            DividerRow()

            InfoRow(
                icon: "person.badge.key",
                iconColor: .green,
                title: L("role"),
                subtitle: roleTitle,
                action: onPickRole
            )
        }
    }
}

// MARK: - Под-вью: карточка действий с аккаунтом
private struct AccountActionsCard: View {
    let onLogoutTap: () -> Void
    let onOtherTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            InfoRow(
                icon: "rectangle.portrait.and.arrow.right",
                iconColor: .red,
                title: L("logout"),
                subtitle: nil,
                action: onLogoutTap
            )

            DividerRow()

            InfoRow(
                icon: "ellipsis.circle",
                iconColor: .gray,
                title: L("other_actions"),
                subtitle: nil,
                action: onOtherTap
            )
        }
    }
}

// MARK: - Универсальные элементы
private struct DividerRow: View {
    var body: some View {
        Divider()
            .background(Color.gray.opacity(0.3))
            .padding(.leading, 44)
    }
}

private struct InfoRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 12)
        .padding(.horizontal)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }
}

// MARK: - Модалки/алерты вынесены отдельно
private struct PersonalViewModals: View {
    @ObservedObject var viewModel: PersonalViewModel
    @EnvironmentObject var auth: AppAuthState
    private let authRepo = AuthenticationRepositoryImpl()

    var body: some View {
        EmptyView()
            // Редактирование полей
            .sheet(item: $viewModel.editingField) { field in
                switch field {
                case .name:
                    EditFieldSheet(
                        title: L("change_name"),
                        text: .constant(viewModel.name),
                        placeholder: L("name_placeholder")
                    ) { newValue in
                        Task { await viewModel.saveChanges(for: .name, with: newValue) }
                    }

                case .email:
                    EditFieldSheet(
                        title: L("change_email"),
                        text: .constant(viewModel.email),
                        placeholder: L("email_placeholder")
                    ) { newValue in
                        Task { await viewModel.saveChanges(for: .email, with: newValue) }
                    }
                }
            }
            // Физические данные
            .sheet(isPresented: $viewModel.showPhysicalDataSheet) {
                PhysicalDataView(viewModel: viewModel.physicalDataVM)
            }
            // Пикер изображения (аватар)
            .sheet(isPresented: $viewModel.showImagePicker) {
                ImagePicker(image: $viewModel.selectedImage)
            }
            // Выбор роли
            .confirmationDialog(
                L("change_role"),
                isPresented: $viewModel.showRolePicker,
                titleVisibility: .visible
            ) {
                ForEach(PersonalViewModel.Role.allCases, id: \.self) { role in
                    Button(role.rawValue) {
                        Task { await viewModel.updateRole(to: role) }
                    }
                }
                Button(L("cancel"), role: .cancel) {}
            }
            // Логаут
            .alert(L("logout_title"), isPresented: $viewModel.showLogoutAlert) {
                Button(L("cancel"), role: .cancel) {}
                Button(L("logout_button"), role: .destructive) {
                    Task {
                        await authRepo.logout()
                        await MainActor.run { auth.logout() }
                    }
                }
            } message: {
                Text(viewModel.email)
            }
            // Другие действия
            .confirmationDialog(
                L("actions_title"),
                isPresented: $viewModel.showOtherActions,
                titleVisibility: .hidden
            ) {
                Button(L("delete_account"), role: .destructive) {
                    viewModel.showDeleteConfirmAlert = true
                }
                Button(L("cancel"), role: .cancel) {}
            }
            .alert(L("delete_account_title"), isPresented: $viewModel.showDeleteConfirmAlert) {
                Button(L("cancel"), role: .cancel) {}
                Button(L("delete_account"), role: .destructive) {
                    viewModel.logout()
                }
            } message: {
                Text(L("delete_account_message"))
            }
    }
}
