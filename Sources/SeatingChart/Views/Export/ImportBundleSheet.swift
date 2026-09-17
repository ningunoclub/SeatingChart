import SwiftUI

/// Shows what a file contains and how it will be merged, before anything on
/// this Mac is touched.
struct ImportBundleSheet: View {
    let pending: PendingImport

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var mode: ImportMode = .addCopies
    /// Cached: `preview` runs a full merge, and body reads it many times over.
    @State private var cached: MergePreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("transfer.import_title")).font(.headline)
                Text(pending.url.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isEmptyFile {
                    Text(L("transfer.summary_nothing")).font(.callout)
                } else {
                    Text(L("transfer.summary", preview.classCount, preview.roomCount,
                           preview.studentCount))
                    if preview.photoCount > 0 {
                        Text(L("transfer.summary_photos", preview.photoCount))
                            .foregroundStyle(.secondary)
                    }
                    if preview.chartCount > 0 {
                        Text(L("transfer.summary_charts", preview.chartCount))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(L("transfer.exported_on", Self.exportedFormatter.string(from: preview.exportedAt)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .font(.callout)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(L("transfer.mode")).font(.subheadline).fontWeight(.semibold)
                Picker("", selection: $mode) {
                    Text(L("transfer.mode.copies")).tag(ImportMode.addCopies)
                    Text(L("transfer.mode.replace")).tag(ImportMode.replaceMatching)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Text(mode == .addCopies ? L("transfer.mode.copies_help")
                                        : L("transfer.mode.replace_help"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Recomputed per mode: copies drop pins whose room is not in the
            // file, whereas a replace re-binds them by id.
            if preview.droppedSeatPins > 0 {
                warning(L("transfer.dropped_pins", preview.droppedSeatPins))
            }
            if mode == .replaceMatching,
               preview.replacedClassCount + preview.replacedRoomCount > 0 {
                warning(L("transfer.replace_warning", preview.replacedClassCount,
                          preview.replacedRoomCount))
            }

            HStack {
                Spacer()
                Button(L("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("transfer.import_button")) {
                    store.applyBundle(pending.bundle, mode: mode)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isEmptyFile)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear(perform: recompute)
        .onChange(of: mode) { _, _ in recompute() }
    }

    private var preview: MergePreview {
        cached ?? BundleTransfer.preview(pending.bundle, against: store.document, mode: mode)
    }

    private func recompute() {
        cached = BundleTransfer.preview(pending.bundle, against: store.document, mode: mode)
    }

    private var isEmptyFile: Bool {
        preview.classCount == 0 && preview.roomCount == 0
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static let exportedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
