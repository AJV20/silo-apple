#if os(iOS)
import SwiftUI

struct MetadataEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: ItemDetail
    let onSave: (UpdateItemMetadataRequest) async throws -> Void

    @State private var draft: MetadataEditDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        item: ItemDetail,
        onSave: @escaping (UpdateItemMetadataRequest) async throws -> Void
    ) {
        self.item = item
        self.onSave = onSave
        _draft = State(initialValue: MetadataEditDraft(item: MetadataEditableItem(
            type: item.type,
            title: item.title,
            sortTitle: item.sortTitle,
            originalTitle: item.originalTitle,
            overview: item.overview,
            tagline: item.tagline,
            contentRating: item.contentRating,
            year: item.year,
            runtime: item.runtime,
            genres: item.genres ?? [],
            studios: item.studios ?? [],
            networks: item.networks ?? [],
            countries: item.countries ?? [],
            lockedFields: item.lockedFields ?? [],
            tracksLocks: item.type == "movie" || item.type == "series"
        )))
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection

                if item.type == "movie" || item.type == "series" {
                    discoverySection
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Metadata save failed. \(errorMessage)")
                    }
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .accessibilityLabel("Saving metadata")
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving || !draft.hasChanges)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var generalSection: some View {
        Section("General") {
            TextField("Title", text: $draft.title)
                .textInputAutocapitalization(.words)

            if item.type == "movie" || item.type == "series" {
                TextField("Sort Title", text: $draft.sortTitle)
                    .textInputAutocapitalization(.words)
                TextField("Original Title", text: $draft.originalTitle)
                    .textInputAutocapitalization(.words)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Overview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.overview)
                    .frame(minHeight: 120)
                    .accessibilityLabel("Overview")
            }

            if item.type == "movie" || item.type == "series" {
                TextField("Tagline", text: $draft.tagline, axis: .vertical)
            }

            if item.type != "season" {
                TextField("Content Rating", text: $draft.contentRating)
                    .textInputAutocapitalization(.characters)
            }

            if item.type == "movie" || item.type == "series" {
                TextField("Year", text: $draft.year)
                    .keyboardType(.numberPad)
            }

            if item.type == "movie" || item.type == "episode" {
                TextField("Runtime (minutes)", text: $draft.runtime)
                    .keyboardType(.numberPad)
            }
        }
    }

    private var discoverySection: some View {
        Section {
            TextField("Genres", text: $draft.genres, axis: .vertical)
            TextField("Studios", text: $draft.studios, axis: .vertical)
            if item.type == "series" {
                TextField("Networks", text: $draft.networks, axis: .vertical)
            }
            TextField("Countries", text: $draft.countries, axis: .vertical)
        } header: {
            Text("Discovery")
        } footer: {
            Text("Separate multiple values with commas. Manual changes are protected from automatic provider refreshes.")
        }
    }

    @MainActor
    private func save() async {
        errorMessage = nil

        do {
            guard let request = try draft.makeUpdateRequest() else {
                dismiss()
                return
            }
            isSaving = true
            defer { isSaving = false }
            try await onSave(request)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
#endif
