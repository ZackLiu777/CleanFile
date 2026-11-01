//
//  文件树构建
//
//  将扫描得到的相对路径和大小累积为供展示使用的目录树。
//  构建过程复用可变节点，最终生成值类型树；诊断仅用于检查树结构。
//

//
//  FileTree.swift
//  CleanMyIPhone
//

//
//  文件职责：集中定义 FileTree 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 展示用不可变树节点，目录汇总子节点大小，文件节点携带自身分类。
struct FileNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let byteCount: Int64
    let children: [FileNode]
    let category: FileCategory?
    let isDirectory: Bool
    let isAggregate: Bool

    /// 保存节点的展示信息；`isAggregate` 用于区分由多个节点汇总的展示项。
    nonisolated init(
        id: String,
        name: String,
        byteCount: Int64,
        children: [FileNode],
        category: FileCategory?,
        isDirectory: Bool,
        isAggregate: Bool = false
    ) {
        self.id = id
        self.name = name
        self.byteCount = byteCount
        self.children = children
        self.category = category
        self.isDirectory = isDirectory
        self.isAggregate = isAggregate
    }
}

/// 将已有扫描文件列表转换为展示树的便利入口。
struct FileTreeBuilder: Sendable {
    /// 逐项累积相对路径并生成最终树；不访问文件内容。
    nonisolated static func build(rootURL: URL, files: [ScannedFile]) -> FileNode {
        var accumulator = FileTreeAccumulator(rootURL: rootURL)
        for file in files {
            accumulator.append(file)
        }
        return accumulator.makeTree()
    }
}

/// Builds the hierarchy as files are discovered instead of performing a
/// second full pass when enumeration has already finished.
/// 扫描期间逐项维护可变树，避免枚举结束后重新遍历文件列表。
/// 内部引用节点仅供单个扫描工作者使用，最终结果是独立的值类型。
nonisolated struct FileTreeAccumulator: @unchecked Sendable {
    /// The accumulator is confined to a single scan worker. Reference semantics
    /// avoid copying a Set and a dictionary value for every path component.
    private final class MutableNode {
        let id: String
        let name: String
        var byteCount: Int64
        var childrenByName: [String: MutableNode]
        var category: FileCategory?
        let isDirectory: Bool

        /// 创建一个尚无子节点的可变树节点；目录和文件共用该构建期表示。
        init(
            id: String,
            name: String,
            byteCount: Int64 = 0,
            category: FileCategory?,
            isDirectory: Bool
        ) {
            self.id = id
            self.name = name
            self.byteCount = byteCount
            childrenByName = [:]
            self.category = category
            self.isDirectory = isDirectory
        }
    }

    private let root: MutableNode

    /// 根据所选 URL 创建树根；根名称缺失时使用本地化的默认名称。
    init(rootURL: URL) {
        let rootName = rootURL.lastPathComponent.isEmpty
            ? AppL10n.string("Selected Folder")
            : rootURL.lastPathComponent

        root = MutableNode(
            id: ".",
            name: rootName,
            category: nil,
            isDirectory: true
        )
    }

    /// 按相对路径创建或复用节点并累加已知大小；未知大小按零参与展示汇总。
    mutating func append(_ file: ScannedFile) {
        let components = file.relativePathComponents
        guard !components.isEmpty else { return }

        let byteCount = file.hasKnownByteCount ? file.byteCount : 0
        var parent = root
        parent.byteCount += byteCount

        for (index, component) in components.enumerated() {
            let isLeaf = index == components.count - 1
            let child: MutableNode

            if let existingChild = parent.childrenByName[component] {
                child = existingChild
            } else {
                let nodeID = parent.id == "." ? component : "\(parent.id)/\(component)"
                let newChild = MutableNode(
                    id: nodeID,
                    name: component,
                    category: isLeaf ? file.category : nil,
                    isDirectory: !isLeaf
                )
                parent.childrenByName[component] = newChild
                child = newChild
            }

            if isLeaf {
                child.byteCount = byteCount
                child.category = file.category
            } else {
                child.byteCount += byteCount
            }

            parent = child
        }
    }

    /// 从当前累积状态构造不可变树，保留累积器以供继续使用。
    func makeTree() -> FileNode {
        Self.makeNode(root)
    }

    /// Candidate consuming finalization: release mutable subtrees as immutable output is built.
    /// The accumulator is empty afterward and must not be used for further appends.
    /// 构造不可变树的同时释放可变子树；调用后不得继续向该累积器添加文件。
    mutating func makeTreeReleasingStorage() -> FileNode {
        Self.consumeNode(root)
    }

    /// 递归取出并释放子节点，按大小及名称排序并计算目录的主导类别。
    private static func consumeNode(_ value: MutableNode) -> FileNode {
        var children: [FileNode] = []
        children.reserveCapacity(value.childrenByName.count)
        // Preserve traversal order before removing dictionary entries.
        let names = Array(value.childrenByName.keys)
        for name in names {
            if let child = value.childrenByName.removeValue(forKey: name) {
                children.append(consumeNode(child))
            }
        }
        children.sort {
            if $0.byteCount == $1.byteCount {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.byteCount > $1.byteCount
        }
        let dominantCategory = children.max(by: { $0.byteCount < $1.byteCount })?.category
        return FileNode(id: value.id, name: value.name, byteCount: value.byteCount,
                        children: children, category: value.category ?? dominantCategory,
                        isDirectory: value.isDirectory)
    }

    /// 递归复制节点并按大小、名称稳定排序；目录类别取占用最大的子节点类别。
    private static func makeNode(_ value: MutableNode) -> FileNode {
        let children = value.childrenByName.values
            .map(makeNode)
            .sorted {
                if $0.byteCount == $1.byteCount {
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return $0.byteCount > $1.byteCount
            }
        let dominantCategory = children.max(by: { $0.byteCount < $1.byteCount })?.category

        return FileNode(
            id: value.id,
            name: value.name,
            byteCount: value.byteCount,
            children: children,
            category: value.category ?? dominantCategory,
            isDirectory: value.isDirectory
        )
    }
}

/// 计算及输出文件树的层级诊断信息，供开发期间检查扫描结果。
enum FileTreeDiagnostics: Sendable {
    /// 计算根节点以下的最大层数；空根返回零。
    nonisolated static func maximumDepth(of root: FileNode) -> Int {
        /// 从当前节点开始递归计数，叶节点深度为一。
        func depth(of node: FileNode) -> Int {
            guard !node.children.isEmpty else { return 1 }
            return 1 + (node.children.map { depth(of: $0) }.max() ?? 0)
        }

        guard !root.children.isEmpty else { return 0 }
        return root.children.map { depth(of: $0) }.max() ?? 0
    }

    /// 按指定深度生成树结构诊断文本，供开发时检查层级。
    nonisolated static func debugDescription(
        of root: FileNode,
        maximumPrintedDepth: Int = 4
    ) -> String {
        var lines = [
            "Folder Map Tree Diagnostics",
            "\(root.name) children = \(root.children.count)",
            "Tree maximum depth = \(maximumDepth(of: root))"
        ]

        /// 在允许的打印深度内递归追加子节点，按深度缩进。
        func appendChildren(of node: FileNode, depth: Int) {
            guard depth <= maximumPrintedDepth else { return }

            for child in node.children {
                lines.append("\(String(repeating: "  ", count: depth))\(child.name) children = \(child.children.count)")
                appendChildren(of: child, depth: depth + 1)
            }
        }

        appendChildren(of: root, depth: 1)
        return lines.joined(separator: "\n")
    }

    /// 将格式化后的树结构写入调试输出；文本包含节点名称。
    nonisolated static func log(_ root: FileNode) {
        debugPrint(debugDescription(of: root))
    }
}
