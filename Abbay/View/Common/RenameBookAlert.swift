//
//  RenameBookAlert.swift
//  Abbay
//

import SwiftUI

/// The *Rename book* box (#322): a text field with the book's name, Cancel and Save. An empty name
/// gives the book back its file's name, which the message says.
struct RenameBookAlert: ViewModifier {
    @Binding var book: AudioModel?
    let onSave: (AudioModel, String) -> Void

    @State private var name = String()

    func body(content: Content) -> some View {
        content
            .alert(
                Localizable.renameBook.localized,
                isPresented: Binding(get: { book != nil }, set: { if !$0 { book = nil } })
            ) {
                // No identifiers here: an alert's field and buttons don't carry them to XCUITest,
                // which finds the box by its title (`RenameBookUITests`).
                TextField(Localizable.bookNamePlaceholder.localized, text: $name)
                Button(Localizable.cancel.localized, role: .cancel) { book = nil }
                Button(Localizable.save.localized) {
                    if let book { onSave(book, name) }
                    book = nil
                }
            } message: {
                Text(Localizable.renameBookMessage.localized)
            }
            .onChange(of: book?.url, initial: true) {
                name = book?.title ?? String()
            }
    }
}

extension View {
    /// Presents *Rename book* while `book` is set; `onSave` gets the book and the name typed.
    func renameBookAlert(for book: Binding<AudioModel?>, onSave: @escaping (AudioModel, String) -> Void) -> some View {
        modifier(RenameBookAlert(book: book, onSave: onSave))
    }
}
