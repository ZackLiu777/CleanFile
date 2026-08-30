//
//  FileTree.swift
//  CleanMyIPhone
//

//
//  文件职责：集中定义 FileTree 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import Foundation

/// 定义 `FileNode` 的值语义数据与相关行为。
struct FileNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let byteCount: Int64
    let children: [FileNode]
    let category: FileCategory?
    let isDirectory: Bool
    let isAggregate: Bool

    /// 创建当前类型实例，并保存后续流程所需的依赖与初始状态。
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

/// 定义 `FileTreeBuilder` 的值语义数据与相关行为。
struct FileTreeBuilder: Sendable {
    /// 创建 `build` 所需的值或资源，统一封装构造细节。
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

    init(rootURL: URL) {
        let rootName = rootURL.lastPathComponent.isEmpty
            ? String(localized: "Selected Folder")
            : rootURL.lastPathComponent

        root = MutableNode(
            id: ".",
            name: rootName,
            category: nil,
            isDirectory: true
        )
    }

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

    func makeTree() -> FileNode {
        Self.makeNode(root)
    }

    /// 创建 `makeNode` 所需的值或资源，统一封装构造细节。
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

/// 定义 `FileTreeDiagnostics` 使用的有限状态或选项集合。
enum FileTreeDiagnostics: Sendable {
    /// 封装 `maximumDepth` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated static func maximumDepth(of root: FileNode) -> Int {
        /// 封装 `depth` 对应的局部行为，供当前类型在统一入口下复用。
        func depth(of node: FileNode) -> Int {
            guard !node.children.isEmpty else { return 1 }
            return 1 + (node.children.map { depth(of: $0) }.max() ?? 0)
        }

        guard !root.children.isEmpty else { return 0 }
        return root.children.map { depth(of: $0) }.max() ?? 0
    }

    /// 封装 `debugDescription` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated static func debugDescription(
        of root: FileNode,
        maximumPrintedDepth: Int = 4
    ) -> String {
        var lines = [
            "Folder Map Tree Diagnostics",
            "\(root.name) children = \(root.children.count)",
            "Tree maximum depth = \(maximumDepth(of: root))"
        ]

        /// 记录 `appendChildren` 产生的结果，并通知依赖该状态的调用方。
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

    /// 封装 `log` 对应的局部行为，供当前类型在统一入口下复用。
    nonisolated static func log(_ root: FileNode) {
        debugPrint(debugDescription(of: root))
    }
}
