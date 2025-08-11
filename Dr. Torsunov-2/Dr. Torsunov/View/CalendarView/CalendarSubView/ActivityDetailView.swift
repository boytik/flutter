
import SwiftUI
import UIKit

@inline(__always) private func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct ActivityDetailView: View {
    let activity: Activity
    let role: PersonalViewModel.Role

    @State private var comment = ""
    @State private var beforeImage: UIImage?
    @State private var afterImage: UIImage?
    @State private var showBeforePicker = false
    @State private var showAfterPicker = false
    @State private var isSubmitting = false
    @State private var submissionSuccess: Bool?

    private let repository: ActivityRepository = ActivityRepositoryImpl()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection

                if role == .user {
                    photosSection
                    commentSection
                    submitButton
                } else {
                    Text("\(L("comment_label")): \(activity.description ?? "-")")
                        .foregroundColor(.white)
                        .padding(.horizontal)
                }

                if let success = submissionSuccess {
                    Text(success ? L("submit_success") : L("submit_error"))
                        .foregroundColor(success ? .green : .red)
                        .padding()
                }
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showBeforePicker) {
            ImagePicker(image: $beforeImage)
        }
        .sheet(isPresented: $showAfterPicker) {
            ImagePicker(image: $afterImage)
        }
        .onAppear {
            comment = activity.description ?? ""
        }
        .navigationTitle("") // оставим пустой, как было
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header
    private var headerSection: some View {
        HStack {
            Text("✅")
                .font(.title)
                .frame(width: 44, height: 44)
                .background(Color.green.opacity(0.2))
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(activity.name)
                    .font(.headline)
                    .foregroundColor(.white)

                if let description = activity.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                if let date = activity.createdAt {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()
        }
    }

    // MARK: Photos
    private var photosSection: some View {
        VStack(spacing: 20) {
            uploadSection(title: L("photo_before"), image: $beforeImage, showPicker: $showBeforePicker)
            uploadSection(title: L("photo_after"), image: $afterImage, showPicker: $showAfterPicker)
        }
    }

    private func uploadSection(title: String, image: Binding<UIImage?>, showPicker: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundColor(.white)
                .font(.subheadline)

            Button(action: { showPicker.wrappedValue = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.2))
                        .frame(height: 150)

                    if let img = image.wrappedValue {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    // MARK: Comment
    private var commentSection: some View {
        VStack(alignment: .leading) {
            Text(L("comment_label"))
                .foregroundColor(.white)
                .font(.subheadline)

            TextField(L("enter_comment_placeholder"), text: $comment, axis: .vertical)
                .lineLimit(3...6)
                .padding()
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }

    // MARK: Submit
    private var submitButton: some View {
        Button(action: submitData) {
            if isSubmitting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Text(L("submit"))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background((beforeImage != nil && afterImage != nil) ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .disabled(beforeImage == nil || afterImage == nil || isSubmitting)
    }

    // MARK: - Actions
    private func submitData() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionSuccess = nil

        Task {
            do {
                try await repository.submit(
                    activityId: activity.id,
                    comment: comment.isEmpty ? nil : comment,
                    beforeImage: beforeImage,
                    afterImage: afterImage
                )
                await MainActor.run {
                    isSubmitting = false
                    submissionSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionSuccess = false
                }
            }
        }
    }
}


