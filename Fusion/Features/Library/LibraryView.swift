import SwiftUI

/// Library of 3D scans and models with search, batch operations, and direct access to 3D Studio
struct LibraryView: View {
    @Environment(ScanStorage.self) private var storage

    @State private var isSelecting = false
    @State private var selection = Set<UUID>()
    @State private var isConfirmingBulkDelete = false
    @State private var searchText = ""
    @State private var selectedRecordForStudio: ScanRecord?

    private var filteredScans: [ScanRecord] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storage.scans
        }
        return storage.scans.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.engine.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if storage.scans.isEmpty {
                ContentUnavailableView(
                    "Sin escaneos 3D todavía",
                    systemImage: "cube.transparent",
                    description: Text("Inicia tu primer escaneo desde la pestaña Escanear.")
                )
            } else {
                List {
                    ForEach(filteredScans) { record in
                        row(for: record)
                    }
                    .onDelete { offsets in
                        delete(filteredScans.enumerated().filter { offsets.contains($0.offset) }.map(\.element))
                    }
                }
                .searchable(text: $searchText, prompt: "Buscar modelos 3D...")
            }
        }
        .navigationTitle(selectionTitle)
        .toolbar {
            if !storage.scans.isEmpty {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) { selectAllButton }
                    ToolbarItem(placement: .topBarTrailing) { deleteSelectedButton }
                }
                ToolbarItem(placement: .topBarTrailing) { selectModeButton }
            }
        }
        .fullScreenCover(item: $selectedRecordForStudio) { record in
            ModelStudioView(record: record)
        }
        .confirmationDialog(
            "¿Eliminar \(selection.count) modelo(s)?",
            isPresented: $isConfirmingBulkDelete,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) { deleteSelected() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los modelos 3D y sus imágenes de origen se eliminarán permanentemente.")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for record: ScanRecord) -> some View {
        let content = ScanRow(record: record, modelURL: storage.modelURL(for: record))

        if isSelecting {
            Button {
                if selection.contains(record.id) {
                    selection.remove(record.id)
                } else {
                    selection.insert(record.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selection.contains(record.id) ? Color.yellow : Color.secondary)
                    content
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedRecordForStudio = record
                HapticFeedback.light()
            } label: {
                content
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Toolbar Controls

    private var selectionTitle: String {
        guard isSelecting else { return "Biblioteca 3D" }
        return selection.isEmpty ? "Seleccionar" : "\(selection.count) seleccionados"
    }

    private var selectModeButton: some View {
        Button(isSelecting ? "Listo" : "Seleccionar") {
            isSelecting.toggle()
            if !isSelecting { selection.removeAll() }
        }
    }

    private var selectAllButton: some View {
        Button(selection.count == storage.scans.count ? "Deseleccionar" : "Seleccionar Todo") {
            if selection.count == storage.scans.count {
                selection.removeAll()
            } else {
                selection = Set(storage.scans.map(\.id))
            }
        }
    }

    private var deleteSelectedButton: some View {
        Button {
            isConfirmingBulkDelete = true
        } label: {
            Label("Eliminar", systemImage: "trash")
        }
        .tint(.red)
        .disabled(selection.isEmpty)
    }

    // MARK: - Actions

    private func deleteSelected() {
        delete(storage.scans.filter { selection.contains($0.id) })
        selection.removeAll()
        isSelecting = false
    }

    private func delete(_ records: [ScanRecord]) {
        for record in records {
            ThumbnailStore.shared.invalidate(storage.modelURL(for: record))
            storage.delete(record)
        }
    }
}

// MARK: - Row View

private struct ScanRow: View {
    let record: ScanRecord
    let modelURL: URL

    var body: some View {
        HStack(spacing: 14) {
            if record.isPreviewable {
                ModelThumbnailView(url: modelURL, side: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill")
                            .foregroundStyle(.yellow)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if record.isEdited == true {
                        Text("EDITADO")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2), in: Capsule())
                            .foregroundStyle(.yellow)
                    }
                }

                HStack(spacing: 6) {
                    Label(record.engine.displayName, systemImage: record.engine.symbolName)
                    if let summary = record.summary {
                        Text("·")
                        Text(summary)
                    }
                    if let tris = record.triangleCount {
                        Text("·")
                        Text("\(tris.formatted()) tris")
                    } else if let pts = record.pointCount {
                        Text("·")
                        Text("\(pts.formatted()) pts")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: 6) {
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let dims = record.dimensionsMillimetres, dims.count == 3 {
                        Text("·")
                        Text("\(dims[0])×\(dims[1])×\(dims[2]) mm")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
