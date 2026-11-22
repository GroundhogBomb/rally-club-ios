import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CreatePostView: View {
    let store: ClubFeedStore

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var images: [PostMedia] = []
    @State private var gif: PostMedia?
    @State private var isLoadingMedia = false
    @State private var mediaSelectionFailure: MediaSelectionFailure?

    private var copy: AppCopy { AppCopy() }
    private var canPublish: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty || gif != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .warmCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(String(localized: "Share a match highlight, a training tip, or a question for the club…"))
                                .foregroundStyle(Color.mutedBrown.opacity(0.7))
                                .padding(.horizontal, 17)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                            }
                        }
                        .accessibilityIdentifier("post-text-editor")

                    if !images.isEmpty || gif != nil {
                        FeedMediaGallery(images: images, gif: gif)
                        Button(role: .destructive) {
                            images = []
                            gif = nil
                            selectedItems = []
                        } label: {
                            Label(String(localized: "Remove media"), systemImage: "trash")
                        }
                        .font(.footnote.weight(.semibold))
                    }

                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 4,
                        matching: .images
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(String(localized: "Add images or a GIF"))
                            Spacer()
                            if isLoadingMedia {
                                ProgressView()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.olive)
                        .padding(16)
                        .warmCanvas()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isLoadingMedia)
                    .accessibilityIdentifier("add-media-button")

                    Text(String(localized: "Choose up to 4 items and 1 GIF. Each file can be up to 8 MB."))
                    .font(.caption)
                    .foregroundStyle(Color.mutedBrown)
                }
                .padding(20)
            }
            .background { CommunityBackdrop() }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "New post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Publish")) {
                        store.publish(text: text, images: images, gif: gif)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canPublish || isLoadingMedia || store.isSubmitting)
                    .accessibilityIdentifier("publish-post-button")
                }
            }
            .onChange(of: selectedItems) { _, newItems in
                Task { await loadMedia(from: newItems) }
            }
            .alert(item: $mediaSelectionFailure) { failure in
                Alert(
                    title: Text(failure.title(copy: copy)),
                    message: Text(failure.message(copy: copy)),
                    dismissButton: .default(Text(copy.dismissTitle))
                )
            }
        }
    }

    @MainActor
    private func loadMedia(from items: [PhotosPickerItem]) async {
        isLoadingMedia = true
        var loadedImages: [PostMedia] = []
        var loadedGIF: PostMedia?

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                mediaSelectionFailure = .unsupportedFormat
                continue
            }
            let isGIF = item.supportedContentTypes.contains { $0.conforms(to: .gif) }
            if isGIF {
                guard loadedGIF == nil else {
                    mediaSelectionFailure = .tooManyGIFs
                    continue
                }
                guard data.count <= CommunityMediaStorage.maximumFileSize else {
                    mediaSelectionFailure = .fileTooLarge
                    continue
                }
                guard data.starts(with: Data("GIF".utf8)) else {
                    mediaSelectionFailure = .unsupportedFormat
                    continue
                }
                loadedGIF = PostMedia(data: data, mimeType: "image/gif")
            } else if let image = UIImage(data: data),
                      let normalizedData = image.jpegData(compressionQuality: 0.86) {
                guard normalizedData.count <= CommunityMediaStorage.maximumFileSize else {
                    mediaSelectionFailure = .fileTooLarge
                    continue
                }
                loadedImages.append(
                    PostMedia(data: normalizedData, mimeType: "image/jpeg")
                )
            } else {
                mediaSelectionFailure = .unsupportedFormat
            }
        }

        images = loadedImages
        gif = loadedGIF
        isLoadingMedia = false
    }
}

private enum MediaSelectionFailure: String, Identifiable {
    case fileTooLarge
    case unsupportedFormat
    case tooManyGIFs

    var id: String { rawValue }

    func title(copy: AppCopy) -> String {
        switch self {
        case .fileTooLarge:
            String(localized: "File too large")
        case .unsupportedFormat:
            String(localized: "Unsupported format")
        case .tooManyGIFs:
            String(localized: "Too many GIFs")
        }
    }

    func message(copy: AppCopy) -> String {
        switch self {
        case .fileTooLarge:
            String(localized: "Each image or GIF must be 8 MB or smaller. Choose a smaller file.")
        case .unsupportedFormat:
            String(localized: "Only standard images and GIFs are supported. Choose another file.")
        case .tooManyGIFs:
            String(localized: "Each post can include up to 1 GIF.")
        }
    }
}
