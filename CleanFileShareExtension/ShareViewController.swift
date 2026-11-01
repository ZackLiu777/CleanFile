// 分享扩展的入口控制器。
//
// 宿主应用通过 NSItemProvider 提供临时文件；扩展将支持的图片和视频复制到
// 共享收件箱，并以清单记录同一批次的顺序。主应用随后读取清单并继续导入流程。
// 单个附件失败不会阻止其他附件导入；界面会在无法打开主应用时保留处理结果。
// 此文件负责扩展界面和导入协调，收件箱路径及清单格式由 ShareImportInbox 定义。

import UIKit
import UniformTypeIdentifiers

/// 展示分享导入进度，并将可用附件交给主应用继续处理。
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let doneButton = UIButton(type: .system)

    /// 建立进度界面并在扩展加载后启动本次附件导入。
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

    /// 分批复制附件、保存清单，并尝试打开主应用。
    ///
    /// 同时最多处理三个附件以限制资源占用；任务完成顺序可能不同于分享顺序，
    /// 因此写入清单前按原始索引排序。没有成功项时清理批次目录，部分失败则
    /// 保留成功项并告知用户；只有清单写入完成后才通知主应用。
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

    /// 将一个支持的附件复制到批次目录，并返回清单条目。
    /// 复制失败时清理可能产生的不完整文件，调用方可继续处理其余附件。
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

    /// 从提供者声明的类型中选择受支持的图片或视频表示。
    /// 仅接受这里列出的扩展名，避免为主应用生成不能识别的清单项。
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

    /// 在提供者的回调内完成文件复制，并将异步回调转换为可抛错操作。
    /// 临时 URL 的生命周期仅覆盖回调，不能将复制推迟到回调返回之后。
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

    /// 结束扩展请求；适用于导入完成后用户手动关闭扩展的路径。
    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
