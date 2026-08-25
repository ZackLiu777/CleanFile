//
//  FileTree.swift
//  CleanMyIPhone
//

import Foundation

struct FileNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let byteCount: Int64
    let children: [FileNode]
    let category: FileCategory?
    let isDirectory: Bool
    let isAggregate: Bool

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

struct FileTreeBuilder: Sendable {
    private struct NodeAccumulator: Sendable {
        let id: String
        let name: String
        var byteCount: Int64
        var childIDs: Set<String>
        var category: FileCategory?
        let isDirectory: Bool
    }

    nonisolated static func build(rootURL: URL, files: [ScannedFile]) -> FileNode {
        let rootID = "."
        let rootName = rootURL.lastPathComponent.isEmpty
            ? String(localized: "Selected Folder")
            : rootURL.lastPathComponent

        var nodes = [
            rootID: NodeAccumulator(
                id: rootID,
                name: rootName,
                byteCount: 0,
                childIDs: [],
                category: nil,
                isDirectory: true
            )
        ]

        for file in files {
            let components = file.relativePathComponents
            guard !components.isEmpty else { continue }

            var parentID = rootID
            nodes[parentID]?.byteCount += file.hasKnownByteCount ? file.byteCount : 0

            for (index, component) in components.enumerated() {
                let isLeaf = index == components.count - 1
                let nodeID = parentID == rootID ? component : "\(parentID)/\(component)"

                if nodes[nodeID] == nil {
                    nodes[nodeID] = NodeAccumulator(
                        id: nodeID,
                        name: component,
                        byteCount: 0,
                        childIDs: [],
                        category: isLeaf ? file.category : nil,
                        isDirectory: !isLeaf
                    )
                }

                nodes[parentID]?.childIDs.insert(nodeID)

                if isLeaf {
                    nodes[nodeID]?.byteCount = file.hasKnownByteCount ? file.byteCount : 0
                    nodes[nodeID]?.category = file.category
                } else {
                    nodes[nodeID]?.byteCount += file.hasKnownByteCount ? file.byteCount : 0
                }

                parentID = nodeID
            }
        }

        return makeNode(id: rootID, nodes: nodes)
    }

    private nonisolated static func makeNode(
        id: String,
        nodes: [String: NodeAccumulator]
    ) -> FileNode {
        guard let value = nodes[id] else {
            return FileNode(
                id: id,
                name: id,
                byteCount: 0,
                children: [],
                category: .other,
                isDirectory: false
            )
        }

        let children = value.childIDs
            .map { makeNode(id: $0, nodes: nodes) }
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

enum FileTreeDiagnostics: Sendable {
    nonisolated static func maximumDepth(of root: FileNode) -> Int {
        func depth(of node: FileNode) -> Int {
            guard !node.children.isEmpty else { return 1 }
            return 1 + (node.children.map { depth(of: $0) }.max() ?? 0)
        }

        guard !root.children.isEmpty else { return 0 }
        return root.children.map { depth(of: $0) }.max() ?? 0
    }

    nonisolated static func debugDescription(
        of root: FileNode,
        maximumPrintedDepth: Int = 4
    ) -> String {
        var lines = [
            "Folder Map Tree Diagnostics",
            "\(root.name) children = \(root.children.count)",
            "Tree maximum depth = \(maximumDepth(of: root))"
        ]

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

    nonisolated static func log(_ root: FileNode) {
        debugPrint(debugDescription(of: root))
    }
}
