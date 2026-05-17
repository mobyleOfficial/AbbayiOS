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
    var onImport: ([URL]) async -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types = [UTType.audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImport: onImport)
    }
}

extension DocumentPickerView {
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onImport: ([URL]) async -> Void

        init(onImport: @escaping ([URL]) async -> Void) {
            self.onImport = onImport
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            Task { @MainActor in
                await onImport(urls)
            }
        }
    }
}

struct DocumentPickerView_Previews: PreviewProvider {
    static var previews: some View {
        DocumentPickerView(onImport: { _ in })
    }
}
