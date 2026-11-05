import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProfileIdentityHeader: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AccountAuth.self) private var auth
    var body: some View {
        HStack(spacing: 16) {
            // Keep the reference's generous photo inside the existing card bounds.
            Color.clear.frame(width: 64, height: 64)
                .overlay {
                    ProfileAvatar(size: 92)
                        .frame(width: 96).clipped().allowsHitTesting(false)
                }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.ledger.profileName ?? auth.profile?.displayName ?? "Your profile")
                    .font(.system(.title2, design: .serif).weight(.semibold)).foregroundStyle(Ink.green)
                    .lineLimit(2).accessibilityIdentifier("profile-display-name")
                if let date = auth.profile?.memberSince {
                    Text("Member since \(date.formatted(.dateTime.year()))").font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile-member-since")
                } else {
                    Text(auth.profileLoading ? "Member since …" : "Member since unavailable")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .accessibilityElement(children: .contain).accessibilityIdentifier("profile-identity-frame")
    }
}

struct ProfileSettingsView: View {
    @Environment(AccountAuth.self) private var auth
    var body: some View {
        Form {
            Section { ProfileIdentityHeader().listRowInsets(EdgeInsets()) }
            Section {
                NavigationLink { ProfilePhotoView() } label: { Label("Change Profile Photo", systemImage: "person.crop.square") }
                    .accessibilityIdentifier("change-profile-photo")
                NavigationLink { ProfileNameView() } label: { Label("Edit Name", systemImage: "pencil") }
                    .accessibilityIdentifier("edit-profile-name")
            }
        }.paperForm().navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
            .task { await auth.loadProfileIfNeeded() }
    }
}

private struct ProfileNameView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AccountAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name).textContentType(.name).textInputAutocapitalization(.words)
                    .submitLabel(.done).accessibilityIdentifier("profile-name-field")
            } footer: { Text("The name shown on your Tender profile.") }
        }.paperForm().navigationTitle("Edit name").navigationBarTitleDisplayMode(.inline)
            .onAppear { name = store.ledger.profileName ?? auth.profile?.displayName ?? "" }
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if store.update({ $0.profileName = cleaned }) { dismiss() } }
                    .disabled(cleaned.isEmpty || cleaned.count > 80 || cleaned.rangeOfCharacter(from: .controlCharacters) != nil)
                    .accessibilityIdentifier("save-profile-name")
            } }
    }
}

struct ProfileAvatar: View {
    @Environment(LedgerStore.self) private var store
    var size: CGFloat = 30
    var outline: Color? = nil
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size)
                    .mask { Image(systemName: "seal.fill").resizable().scaledToFit() }
                    .overlay { Image(systemName: "seal").resizable().scaledToFit().foregroundStyle(outline ?? Ink.green) }
            } else { Image(systemName: "seal").resizable().scaledToFit().foregroundStyle(outline ?? Ink.green).frame(width: size, height: size) }
        }.frame(width: size, height: size).accessibilityHidden(true)
            .task(id: store.ledger.profilePhoto?.croppedImage) {
                image = store.ledger.profilePhoto.flatMap { UIImage(contentsOfFile: store.attachmentURL($0.croppedImage).path) }
            }
    }
}

private struct ProfilePhotoDraft: Identifiable {
    let id = UUID()
    var image: UIImage
    var crop: ProfilePhotoCrop = ProfilePhotoCrop()
    var originalAttachment: String?
}

struct ProfilePhotoView: View {
    @Environment(LedgerStore.self) private var store
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var draft: ProfilePhotoDraft?
    @State private var camera = false
    @State private var cameraData: Data?
    @State private var importing = false
    @State private var removing = false
    @State private var message: String?
    @State private var loading = false
    var body: some View {
        Form {
            Section {
                HStack { Spacer(); ProfileAvatar(size: 128); Spacer() }.padding(.vertical, 16)
                Text("Your photo fits inside the tender logo. Zoom and drag to choose what appears.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                    .disabled(loading).accessibilityIdentifier("profile-choose-photo")
                if CameraPicker.isAvailable {
                    Button("Take Photo", systemImage: "camera") { camera = true }.accessibilityIdentifier("profile-take-photo")
                }
                Button("Choose Image File", systemImage: "folder") { importing = true }.disabled(loading)
                if loading { Label("Opening photo…", systemImage: "photo").foregroundStyle(.secondary) }
            }
            if store.ledger.profilePhoto != nil {
                Section {
                    Button("Adjust Photo", systemImage: "crop") { editSavedPhoto() }.accessibilityIdentifier("profile-adjust-photo")
                    Button("Remove Photo", systemImage: "trash", role: .destructive) { removing = true }.accessibilityIdentifier("profile-remove-photo")
                }
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--profile-photo-test") {
                Section {
                    Button("Use synthetic test photo") {
                        let format = UIGraphicsImageRendererFormat(); format.scale = 1
                        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format).image { context in
                            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
                            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 450, y: 0, width: 450, height: 600))
                            UIColor.white.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 330, y: 180, width: 240, height: 240))
                        }
                        draft = ProfilePhotoDraft(image: image)
                    }.accessibilityIdentifier("profile-test-photo")
                }
            }
            #endif
        }.paperForm().navigationTitle("Profile photo").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $draft) { draft in
                NavigationStack {
                    ProfilePhotoCropEditor(image: draft.image, crop: draft.crop) { image, crop, rotated in
                        let saved = store.saveProfilePhoto(image, crop: crop, reusingOriginal: rotated ? nil : draft.originalAttachment)
                        if saved { return nil }
                        let reason = store.error ?? "Your photo couldn’t be saved. Check available storage and try again."
                        store.error = nil
                        return reason
                    }
                }
            }
            .sheet(isPresented: $camera, onDismiss: {
                if let data = cameraData { cameraData = nil; open(data) }
            }) { CameraPicker { data in cameraData = data } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw ProfilePhotoProcessing.PhotoError.unreadable }
                    open(try Data(contentsOf: url))
                } catch { message = error.localizedDescription }
            }
            .task(id: selectedPhoto) {
                guard let selectedPhoto else { return }
                loading = true; defer { loading = false }
                do {
                    guard let data = try await selectedPhoto.loadTransferable(type: Data.self), !Task.isCancelled else { return }
                    open(data)
                } catch { message = "This photo couldn’t be opened. Choose another image." }
                self.selectedPhoto = nil
            }
            .confirmationDialog("Remove your profile photo?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove Photo", role: .destructive) { _ = store.update { $0.profilePhoto = nil } }.accessibilityIdentifier("confirm-remove-profile-photo")
                Button("Cancel", role: .cancel) {}
            } message: { Text("The original tender logo will appear again.") }
            .alert("Profile photo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
    }
    private func open(_ data: Data) {
        do { draft = ProfilePhotoDraft(image: try ProfilePhotoProcessing.prepare(data)) }
        catch { message = error.localizedDescription }
    }
    private func editSavedPhoto() {
        guard let photo = store.ledger.profilePhoto else { return }
        do {
            draft = ProfilePhotoDraft(image: try ProfilePhotoProcessing.prepare(Data(contentsOf: store.attachmentURL(photo.originalImage))),
                                      crop: photo.crop, originalAttachment: photo.originalImage)
        } catch { message = "The original photo isn’t available. Choose the photo again to adjust it." }
    }
}

private struct ProfilePhotoCropEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage
    @State private var crop: ProfilePhotoCrop
    @State private var dragOrigin: ProfilePhotoCrop?
    @State private var zoomOrigin: Double?
    @State private var rotated = false
    @State private var saveMessage: String?
    let onSave: (UIImage, ProfilePhotoCrop, Bool) -> String?
    init(image: UIImage, crop: ProfilePhotoCrop, onSave: @escaping (UIImage, ProfilePhotoCrop, Bool) -> String?) {
        _image = State(initialValue: image); _crop = State(initialValue: crop.constrained(width: image.size.width, height: image.size.height))
        self.onSave = onSave
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Drag to reposition. Pinch or use the slider to zoom.").font(.subheadline).multilineTextAlignment(.center)
                GeometryReader { geometry in preview(side: geometry.size.width) }
                    .aspectRatio(1, contentMode: .fit).frame(maxWidth: 360)
                    .accessibilityIdentifier("profile-crop-preview")
                HStack(spacing: 12) {
                    Button { setZoom(crop.zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44) }
                        .accessibilityLabel("Zoom out").accessibilityIdentifier("profile-zoom-out")
                    Slider(value: Binding(get: { crop.zoom }, set: { setZoom($0) }), in: 1...5)
                        .accessibilityLabel("Photo zoom").accessibilityValue("\(Int(crop.zoom * 100)) percent")
                    Button { setZoom(crop.zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44) }
                        .accessibilityLabel("Zoom in").accessibilityIdentifier("profile-zoom-in")
                }
                Text("\(Int(crop.zoom * 100))% zoom").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("profile-zoom-value")
                HStack(spacing: 16) {
                    Button("Rotate", systemImage: "rotate.right") {
                        image = ProfilePhotoProcessing.rotateClockwise(image); crop = ProfilePhotoCrop(); rotated = true
                        dragOrigin = nil; zoomOrigin = nil
                    }.frame(minHeight: 44).accessibilityIdentifier("profile-rotate")
                    Button("Reset crop", systemImage: "arrow.counterclockwise") { crop = ProfilePhotoCrop(); dragOrigin = nil; zoomOrigin = nil }
                        .frame(minHeight: 44).accessibilityIdentifier("profile-reset-crop")
                }.buttonStyle(.bordered)
                Text("Only the area inside the logo will be visible.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 500).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden).background(Ink.paper).navigationTitle("Adjust photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    if let error = onSave(image, crop, rotated) { saveMessage = error } else { dismiss() }
                }.accessibilityIdentifier("profile-save-crop") }
            }
            .alert("Photo couldn’t be saved", isPresented: Binding(get: { saveMessage != nil }, set: { if !$0 { saveMessage = nil } })) {
                Button("OK", role: .cancel) { saveMessage = nil }
            } message: { Text(saveMessage ?? "") }
    }
    private func preview(side: CGFloat) -> some View {
        let factor = side / min(image.size.width, image.size.height) * crop.zoom
        let width = image.size.width * factor, height = image.size.height * factor
        let photo = Image(uiImage: image).resizable().frame(width: width, height: height)
            .offset(x: (0.5 - crop.centerX) * width, y: (0.5 - crop.centerY) * height)
            .frame(width: side, height: side).clipped()
        return ZStack {
            Color.black
            photo.opacity(0.25)
            photo.mask { Image(systemName: "seal.fill").resizable().scaledToFit() }
            ZStack {
                Image(systemName: "seal.fill").resizable().scaledToFit().foregroundStyle(.white)
                Image(systemName: "seal.fill").resizable().scaledToFit().padding(1.5).blendMode(.destinationOut)
            }.compositingGroup().allowsHitTesting(false)
        }.clipShape(RoundedRectangle(cornerRadius: 24)).contentShape(Rectangle())
            .gesture(DragGesture().onChanged { value in
                if dragOrigin == nil { dragOrigin = crop }
                guard let origin = dragOrigin else { return }
                crop.centerX = origin.centerX - value.translation.width / width
                crop.centerY = origin.centerY - value.translation.height / height
                crop = crop.constrained(width: image.size.width, height: image.size.height)
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(MagnifyGesture().onChanged { value in
                if zoomOrigin == nil { zoomOrigin = crop.zoom }
                setZoom((zoomOrigin ?? 1) * value.magnification)
            }.onEnded { _ in zoomOrigin = nil })
            .accessibilityElement(children: .ignore).accessibilityLabel("Crop preview")
            .accessibilityHint("Use Photo zoom to change size, or photo movement actions to reposition.")
            .accessibilityAction(named: "Move photo left") { move(x: 0.05, y: 0) }
            .accessibilityAction(named: "Move photo right") { move(x: -0.05, y: 0) }
            .accessibilityAction(named: "Move photo up") { move(x: 0, y: 0.05) }
            .accessibilityAction(named: "Move photo down") { move(x: 0, y: -0.05) }
    }
    private func setZoom(_ zoom: Double) {
        crop.zoom = zoom; crop = crop.constrained(width: image.size.width, height: image.size.height)
    }
    private func move(x: Double, y: Double) {
        crop.centerX += x; crop.centerY += y
        crop = crop.constrained(width: image.size.width, height: image.size.height)
    }
}
