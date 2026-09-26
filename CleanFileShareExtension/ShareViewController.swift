import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = NSLocalizedString("Import to Filevra", comment: "Share extension title")
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textAlignment = .center
        detailLabel.text = NSLocalizedString("Preparing files…", comment: "Share import progress")
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
        detailLabel.textAlignment = .center
        doneButton.setTitle(NSLocalizedString("Done", comment: "Close share extension"), for: .normal)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [titleLabel, spinner, detailLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82)
        ])
        spinner.startAnimating()
        Task { await importAttachments() }
    }

    private func importAttachments() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let batchID = UUID()
        do {
            let directory = try ShareImportInbox.directory(for: batchID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var completedEntries: [(Int, ShareImportInbox.Entry)] = []
            var failures = 0
            await withTaskGroup(of: (Int, ShareImportInbox.Entry?).self) { group in
                let concurrencyLimit = min(3, providers.count)
                var nextIndex = 0
                for _ in 0..<concurrencyLimit {
                    let index = nextIndex
                    group.addTask {
                        (index, await Self.importAttachment(providers[index], into: directory))
                    }
                    nextIndex += 1
                }
                for await (index, entry) in group {
                    if let entry { completedEntries.append((index, entry)) }
                    else { failures += 1 }
                    detailLabel.text = String(
                        format: NSLocalizedString("Importing %d of %d…", comment: "Share import progress"),
                        completedEntries.count + failures, providers.count
                    )
                    if nextIndex < providers.count {
                        let index = nextIndex
                        group.addTask {
                            (index, await Self.importAttachment(providers[index], into: directory))
                        }
                        nextIndex += 1
                    }
                }
            }
            let entries = completedEntries.sorted { $0.0 < $1.0 }.map { $0.1 }
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: directory)
                detailLabel.text = NSLocalizedString("No supported photos or videos could be imported.",
                                                     comment: "Share import error")
            } else {
                let batch = ShareImportInbox.Batch(id: batchID, createdAt: Date(), entries: entries)
                try JSONEncoder().encode(batch).write(
                    to: directory.appendingPathComponent("manifest.json"), options: .atomic
                )
                if let url = URL(string: "cleanfile-zaneliao://import?batch=\(batchID.uuidString)"),
                   await extensionContext?.open(url) == true {
                    extensionContext?.completeRequest(returningItems: nil)
                    return
                }
                detailLabel.text = failures == 0
                    ? NSLocalizedString("Imported. Open Filevra to choose compression settings.",
                                        comment: "Share import complete")
                    : String(format: NSLocalizedString("Imported %d files; %d could not be imported. Open Filevra to continue.",
                                                      comment: "Partial share import"), entries.count, failures)
            }
        } catch {
            detailLabel.text = NSLocalizedString("Import failed. Check available storage and try again.",
                                                 comment: "Share import error")
        }
        spinner.stopAnimating()
        doneButton.isHidden = false
    }

    private static func importAttachment(_ provider: NSItemProvider, into directory: URL) async
        -> ShareImportInbox.Entry? {
        guard let representation = representation(for: provider) else { return nil }
        let entry = ShareImportInbox.Entry(
            id: UUID(), kind: representation.kind,
            fileName: "\(UUID().uuidString).\(representation.extensionName)"
        )
        let destination = directory.appendingPathComponent(entry.fileName)
        do {
            try await copy(provider, typeIdentifier: representation.typeIdentifier, to: destination)
            return entry
        } catch {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
    }

    private static func representation(for provider: NSItemProvider)
        -> (typeIdentifier: String, kind: ShareImportInbox.Kind, extensionName: String)? {
        for identifier in provider.registeredTypeIdentifiers {
            guard let type = UTType(identifier) else { continue }
            if type.conforms(to: .movie), let ext = type.preferredFilenameExtension?.lowercased(),
               ["mov", "mp4", "m4v"].contains(ext) {
                return (identifier, .video, ext)
            }
            if type.conforms(to: .image), let ext = type.preferredFilenameExtension?.lowercased(),
               ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"].contains(ext) {
                return (identifier, .image, ext)
            }
        }
        return nil
    }

    private static func copy(_ provider: NSItemProvider, typeIdentifier: String, to destination: URL)
        async throws {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { temporaryURL, error in
                do {
                    if let error { throw error }
                    guard let temporaryURL else { throw CocoaError(.fileReadUnknown) }
                    // The provider deletes this URL when the callback returns.
                    try FileManager.default.copyItem(at: temporaryURL, to: destination)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
