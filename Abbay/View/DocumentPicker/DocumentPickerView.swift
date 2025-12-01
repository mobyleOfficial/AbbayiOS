//
//  DocumentPickerView.swift
//  Abbay
//
//  Created by Edson Yudi Toma on 19/06/23.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPickerView: UIViewControllerRepresentable {
    // MARK: - Properties
    @Binding
    var selectedFiles: [AudioModel]
    var fileLoader: FileLoaderProtocol

    // MARK: - UIViewControllerRepresentable
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType.audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        /* empty */
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, fileLoader: fileLoader)
    }
}

// MARK: - Coordinator
extension DocumentPickerView {
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        // MARK: - Properties
        private var view: DocumentPickerView
        private var fileLoader: FileLoaderProtocol

        // MARK: Init
        init(_ view: DocumentPickerView, fileLoader: FileLoaderProtocol) {
            self.view = view
            self.fileLoader = fileLoader
        }

        // MARK: - UIDocumentPickerDelegate
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Task {
                let newFiles = await fileLoader.load(urls: urls)
                for file in newFiles {
                    if view.selectedFiles.contains(where: { $0.url == file.url }) {
                        continue
                    }
                    view.selectedFiles.append(file)
                }
            }
        }
    }
}

// MARK: - Preview
struct DocumentPickerView_Previews: PreviewProvider {
    static var previews: some View {
        DocumentPickerView(selectedFiles: .constant([]), fileLoader: FileLoader())
    }
}
