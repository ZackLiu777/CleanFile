import Combine
import SwiftUI

// MARK: - 1. 数据结构
struct DemoFileNode: Identifiable {
    let id = UUID()
    let name: String
    let byteCount: Int64
    var color: Color? = nil
    var children: [DemoFileNode]? = nil

    var totalByteCount: Int64 {
        if let children, !children.isEmpty {
            let childrenByteCount = children.reduce(Int64.zero) {
                $0 + $1.totalByteCount
            }
            return max(byteCount, childrenByteCount)
        }
        return byteCount
    }

    var proportionalSize: Double {
        Double(totalByteCount)
    }

    var maximumDepth: Int {
        guard let children, !children.isEmpty else { return 0 }
        return 1 + (children.map(\.maximumDepth).max() ?? 0)
    }
}

@MainActor
struct SunburstTreeAdapter {
    struct AdaptedTree {
        let rootNode: DemoFileNode
        let sourceNodes: [UUID: FileNode]
    }

    static func adapt(_ root: FileNode) -> AdaptedTree {
        var sourceNodes: [UUID: FileNode] = [:]
        let children = root.children.enumerated().map { index, child in
            let color = SunburstPalette.colors[index % SunburstPalette.colors.count]
            return adaptNode(child, color: color, sourceNodes: &sourceNodes)
        }
        let rootNode = DemoFileNode(
            name: root.name,
            byteCount: root.byteCount,
            children: children.isEmpty ? nil : children
        )
        sourceNodes[rootNode.id] = root

        return AdaptedTree(rootNode: rootNode, sourceNodes: sourceNodes)
    }

    private static func adaptNode(
        _ node: FileNode,
        color: Color,
        sourceNodes: inout [UUID: FileNode]
    ) -> DemoFileNode {
        let children = node.children.map { child in
            let childColor = color.饱和度调整(
                satFactor: stableValue(for: child.id, salt: 17, range: 0.7...1.2),
                brightFactor: stableValue(for: child.id, salt: 31, range: 0.8...1.2)
            )
            return adaptNode(child, color: childColor, sourceNodes: &sourceNodes)
        }
        let adaptedNode = DemoFileNode(
            name: node.name,
            byteCount: node.byteCount,
            color: color,
            children: children.isEmpty ? nil : children
        )
        sourceNodes[adaptedNode.id] = node
        return adaptedNode
    }

    private static func stableValue(
        for value: String,
        salt: UInt64,
        range: ClosedRange<Double>
    ) -> Double {
        var hash = UInt64(1_469_598_103_934_665_603) ^ salt
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        let fraction = Double(hash % 10_000) / 9_999
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

private enum SunburstPalette {
    static let colors: [Color] = [
        Color(red: 0.2, green: 0.9, blue: 0.95),
        Color(red: 0.65, green: 0.95, blue: 0.3),
        Color(red: 1.0, green: 0.7, blue: 0.35),
        Color(red: 1.0, green: 0.35, blue: 0.6),
        Color(red: 0.45, green: 0.4, blue: 0.95),
        Color(red: 0.95, green: 0.25, blue: 0.35),
        Color(red: 0.3, green: 0.8, blue: 0.5)
    ]
}

struct SunburstCapacityFormatter {
    static func text(for byteCount: Int64) -> (value: String, unit: String) {
        let byteCount = max(0, byteCount)
        if byteCount >= 1_000_000_000 {
            return (
                String(format: "%.2f", Double(byteCount) / 1_000_000_000),
                "GB"
            )
        }

        if byteCount >= 1_000_000 {
            return (
                String(format: "%.1f", Double(byteCount) / 1_000_000),
                "MB"
            )
        }

        if byteCount >= 1_000 {
            return (
                String(format: "%.1f", Double(byteCount) / 1_000),
                "KB"
            )
        }

        return ("\(byteCount)", "B")
    }
}

// MARK: - 2. 自适应绘图尺寸
struct SunburstChartGeometry {
    static let sectorGapDegrees = 0.2
    static let minimumChildSweepDegrees = 0.25

    private static let designCenterRadius: CGFloat = 45
    private static let designInnerRingWidth: CGFloat = 16
    private static let designOuterRingWidth: CGFloat = 8
    private static let designRingSpacing: CGFloat = 1.2
    private static let edgeInset: CGFloat = 2

    let centerRadius: CGFloat
    let innerRingWidth: CGFloat
    let outerRingWidth: CGFloat
    let ringSpacing: CGFloat
    let maximumDepth: Int

    init(size: CGSize, maximumDepth: Int) {
        self.maximumDepth = max(1, maximumDepth)
        let availableRadius = max(0, min(size.width, size.height) / 2 - Self.edgeInset)
        let designOuterRadius = Self.designRadii(at: self.maximumDepth).outer
        let scale = min(1, availableRadius / designOuterRadius)

        centerRadius = Self.designCenterRadius * scale
        innerRingWidth = Self.designInnerRingWidth * scale
        outerRingWidth = Self.designOuterRingWidth * scale
        ringSpacing = Self.designRingSpacing * scale
    }

    func radii(at depth: Int) -> (inner: CGFloat, outer: CGFloat) {
        var radius = centerRadius
        for currentDepth in 1..<depth {
            let width = currentDepth <= 5 ? innerRingWidth : outerRingWidth
            radius += width + ringSpacing
        }

        let width = depth <= 5 ? innerRingWidth : outerRingWidth
        return (radius, radius + width)
    }

    private static func designRadii(at depth: Int) -> (inner: CGFloat, outer: CGFloat) {
        var radius = designCenterRadius
        for currentDepth in 1..<depth {
            let width = currentDepth <= 5 ? designInnerRingWidth : designOuterRingWidth
            radius += width + designRingSpacing
        }

        let width = depth <= 5 ? designInnerRingWidth : designOuterRingWidth
        return (radius, radius + width)
    }
}

// MARK: - 3. 扇形 Shape
struct SunburstSectorShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        let angularSpan = max(0, endAngle.degrees - startAngle.degrees)
        let gapAngle = Angle(degrees: min(
            SunburstChartGeometry.sectorGapDegrees,
            angularSpan * 0.2
        ))
        let actualStart = startAngle + gapAngle
        let actualEnd = endAngle - gapAngle

        guard actualEnd.radians > actualStart.radians else { return path }

        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: actualStart,
            endAngle: actualEnd,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: actualEnd,
            endAngle: actualStart,
            clockwise: true
        )
        path.closeSubpath()

        return path
    }
}

/// Reveals one complete hierarchy ring at a time. The active ring opens
/// clockwise, so its individual file sectors appear progressively without
/// creating an animation task for every node in a large tree.
private struct SunburstLayeredRevealShape: Shape {
    var progress: Double
    let geometry: SunburstChartGeometry
    let visibleDepth: Int

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        guard clampedProgress > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maximumDepth = max(1, visibleDepth)
        let stage = clampedProgress * Double(maximumDepth)
        let completedDepth = min(Int(stage), maximumDepth)
        let activeDepth = min(completedDepth + 1, maximumDepth)
        let activeProgress = completedDepth < maximumDepth
            ? stage - Double(completedDepth)
            : 0
        var path = Path()

        if completedDepth > 0 {
            let completedOuterRadius = geometry.radii(at: completedDepth).outer
            path.addEllipse(in: CGRect(
                x: center.x - completedOuterRadius,
                y: center.y - completedOuterRadius,
                width: completedOuterRadius * 2,
                height: completedOuterRadius * 2
            ))
        }

        guard completedDepth < maximumDepth, activeProgress > 0 else { return path }

        let radii = geometry.radii(at: activeDepth)
        let startAngle = Angle.degrees(-90)
        let endAngle = Angle.degrees(-90 + 360 * activeProgress)
        var activeRingPath = Path()
        activeRingPath.addArc(
            center: center,
            radius: radii.inner,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        activeRingPath.addArc(
            center: center,
            radius: radii.outer,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        activeRingPath.closeSubpath()
        path.addPath(activeRingPath)
        return path
    }
}

// MARK: - 4. 递归节点 View
struct SunburstNodeView: View {
    let node: DemoFileNode
    let startAngle: Angle
    let endAngle: Angle
    let depth: Int
    let inheritedColor: Color
    let geometry: SunburstChartGeometry

    var body: some View {
        let radii = geometry.radii(at: depth)
        let nodeColor = node.color ?? inheritedColor
        let sector = SunburstSectorShape(
            startAngle: startAngle,
            endAngle: endAngle,
            innerRadius: radii.inner,
            outerRadius: radii.outer
        )

        ZStack {
            sector.fill(nodeColor)
            sector.stroke(Color.black.opacity(0.3), lineWidth: 0.3)

            if let children = node.children,
               !children.isEmpty {
                let slices = computeChildSlices(
                    children: children,
                    total: node.proportionalSize,
                    nodeColor: nodeColor
                )

                ForEach(slices, id: \.child.id) { slice in
                    SunburstNodeView(
                        node: slice.child,
                        startAngle: slice.startAngle,
                        endAngle: slice.endAngle,
                        depth: depth + 1,
                        inheritedColor: slice.color,
                        geometry: geometry
                    )
                }
            }
        }
    }

    private struct ChildSlice {
        let child: DemoFileNode
        let startAngle: Angle
        let endAngle: Angle
        let color: Color
    }

    private func computeChildSlices(
        children: [DemoFileNode],
        total: Double,
        nodeColor: Color
    ) -> [ChildSlice] {
        var slices: [ChildSlice] = []
        var currentStart = startAngle
        let totalSweep = endAngle.degrees - startAngle.degrees

        for child in children {
            let sweep = total > 0 ? totalSweep * (child.proportionalSize / total) : 0
            if sweep < SunburstChartGeometry.minimumChildSweepDegrees {
                currentStart = Angle(degrees: currentStart.degrees + sweep)
                continue
            }

            let childEnd = Angle(degrees: currentStart.degrees + sweep)
            slices.append(ChildSlice(
                child: child,
                startAngle: currentStart,
                endAngle: childEnd,
                color: child.color ?? nodeColor
            ))
            currentStart = childEnd
        }

        return slices
    }
}

// MARK: - 5. 颜色扩展
extension Color {
    func 饱和度调整(satFactor: Double, brightFactor: Double) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        let uiColor = UIColor(self)
        uiColor.getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )

        let newSaturation = min(max(saturation * CGFloat(satFactor), 0.15), 1)
        let newBrightness = min(max(brightness * CGFloat(brightFactor), 0.25), 1)

        return Color(
            hue: Double(hue),
            saturation: Double(newSaturation),
            brightness: Double(newBrightness),
            opacity: Double(alpha)
        )
    }
}

// MARK: - 6. 旭日图主 View
private struct SunburstChartCanvas: View {
    let rootNode: DemoFileNode
    let revealProgress: Double
    var onNodeTap: ((DemoFileNode) -> Void)?
    var onCenterTap: (() -> Void)?

    init(
        rootNode: DemoFileNode,
        revealProgress: Double = 1,
        onNodeTap: ((DemoFileNode) -> Void)? = nil,
        onCenterTap: (() -> Void)? = nil
    ) {
        self.rootNode = rootNode
        self.revealProgress = revealProgress
        self.onNodeTap = onNodeTap
        self.onCenterTap = onCenterTap
    }

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let geometry = SunburstChartGeometry(
                size: geo.size,
                maximumDepth: rootNode.maximumDepth
            )
            let slices = rootSlices()

            ZStack {
                ZStack {
                    ForEach(slices, id: \.child.id) { slice in
                        SunburstNodeView(
                            node: slice.child,
                            startAngle: slice.startAngle,
                            endAngle: slice.endAngle,
                            depth: 1,
                            inheritedColor: slice.color,
                            geometry: geometry
                        )
                    }
                }
                // The hierarchy is static while the reveal progresses. Flatten it
                // once so the GPU animates one texture and one mask instead of
                // recompositing every file sector on every frame.
                .drawingGroup(opaque: false, colorMode: .nonLinear)
                .mask(SunburstLayeredRevealShape(
                    progress: revealProgress,
                    geometry: geometry,
                    visibleDepth: rootNode.maximumDepth - 1
                ))

                Circle()
                    .fill(.clear)
                    .frame(width: geometry.centerRadius * 2, height: geometry.centerRadius * 2)
                    .overlay(
                        VStack(spacing: 2) {
                            Text(centerCapacity.value)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text(centerCapacity.unit)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    )
            }
            .position(center)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        guard revealProgress >= 0.999 else { return }
                        handleTap(value.location, size: geo.size, geometry: geometry)
                    }
            )
        }
    }

    private struct RootSlice {
        let child: DemoFileNode
        let startAngle: Angle
        let endAngle: Angle
        let color: Color
    }

    private var centerCapacity: (value: String, unit: String) {
        SunburstCapacityFormatter.text(for: rootNode.totalByteCount)
    }

    private func rootSlices() -> [RootSlice] {
        guard let children = rootNode.children, !children.isEmpty else { return [] }

        var slices: [RootSlice] = []
        var currentStart = -90.0

        for child in children {
            let sweep = rootNode.proportionalSize > 0
                ? 360 * child.proportionalSize / rootNode.proportionalSize
                : 0
            let childEnd = currentStart + sweep
            slices.append(RootSlice(
                child: child,
                startAngle: .degrees(currentStart),
                endAngle: .degrees(childEnd),
                color: child.color ?? .blue
            ))
            currentStart = childEnd
        }

        return slices
    }

    private func handleTap(
        _ location: CGPoint,
        size: CGSize,
        geometry: SunburstChartGeometry
    ) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = hypot(location.x - center.x, location.y - center.y)

        if radius <= geometry.centerRadius {
            onCenterTap?()
            return
        }

        if let node = SunburstChartHitTester.node(
            at: location,
            canvasSize: size,
            rootNode: rootNode,
            geometry: geometry
        ) {
            onNodeTap?(node)
        }
    }
}

private enum SunburstChartHitTester {
    static func node(
        at location: CGPoint,
        canvasSize: CGSize,
        rootNode: DemoFileNode,
        geometry: SunburstChartGeometry
    ) -> DemoFileNode? {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = hypot(location.x - center.x, location.y - center.y)
        var angle = Double(atan2(location.y - center.y, location.x - center.x))
            * 180 / Double.pi

        while angle < -90 {
            angle += 360
        }
        while angle >= 270 {
            angle -= 360
        }

        guard let children = rootNode.children, !children.isEmpty else { return nil }

        var currentStart = -90.0
        for child in children {
            let sweep = rootNode.proportionalSize > 0
                ? 360 * child.proportionalSize / rootNode.proportionalSize
                : 0
            let end = currentStart + sweep

            if let hit = node(
                child,
                startAngle: currentStart,
                endAngle: end,
                depth: 1,
                radius: radius,
                angle: angle,
                geometry: geometry
            ) {
                return hit
            }

            currentStart = end
        }

        return nil
    }

    private static func node(
        _ node: DemoFileNode,
        startAngle: Double,
        endAngle: Double,
        depth: Int,
        radius: CGFloat,
        angle: Double,
        geometry: SunburstChartGeometry
    ) -> DemoFileNode? {
        let actualStart = startAngle + SunburstChartGeometry.sectorGapDegrees
        let actualEnd = endAngle - SunburstChartGeometry.sectorGapDegrees
        guard actualEnd > actualStart, angle >= actualStart, angle <= actualEnd else {
            return nil
        }

        if let children = node.children,
           !children.isEmpty {
            var childStart = startAngle
            let totalSweep = endAngle - startAngle

            for child in children {
                let sweep = node.proportionalSize > 0
                    ? totalSweep * child.proportionalSize / node.proportionalSize
                    : 0
                let childEnd = childStart + sweep

                if sweep >= SunburstChartGeometry.minimumChildSweepDegrees,
                   let hit = self.node(
                    child,
                    startAngle: childStart,
                    endAngle: childEnd,
                    depth: depth + 1,
                    radius: radius,
                    angle: angle,
                    geometry: geometry
                   ) {
                    return hit
                }

                childStart = childEnd
            }
        }

        let radii = geometry.radii(at: depth)
        guard radius >= radii.inner, radius <= radii.outer else { return nil }
        return node
    }
}

// MARK: - 7. 生产数据与交互
@MainActor
private final class SunburstChartViewModel: ObservableObject {
    @Published private(set) var chartRoot: DemoFileNode

    private var currentRoot: FileNode
    private var sourceNodes: [UUID: FileNode]
    private var history: [FileNode] = []

    init(root: FileNode) {
        currentRoot = root
        let adaptedTree = SunburstTreeAdapter.adapt(root)
        chartRoot = adaptedTree.rootNode
        sourceNodes = adaptedTree.sourceNodes
    }

    func replaceRoot(_ root: FileNode) {
        guard root != currentRoot else { return }

        history = []
        apply(root)
    }

    func open(_ chartNode: DemoFileNode) {
        guard let sourceNode = sourceNodes[chartNode.id],
              sourceNode.isDirectory,
              !sourceNode.isAggregate,
              !sourceNode.children.isEmpty
        else {
            return
        }

        history.append(currentRoot)
        apply(sourceNode)
    }

    func navigateBack() {
        guard let parent = history.popLast() else { return }
        apply(parent)
    }

    private func apply(_ root: FileNode) {
        currentRoot = root
        let adaptedTree = SunburstTreeAdapter.adapt(root)
        chartRoot = adaptedTree.rootNode
        sourceNodes = adaptedTree.sourceNodes
    }
}

struct SunburstChartView: View {
    let root: FileNode
    let revealProgress: Double
    @StateObject private var viewModel: SunburstChartViewModel

    init(root: FileNode, revealProgress: Double = 1) {
        self.root = root
        self.revealProgress = revealProgress
        _viewModel = StateObject(wrappedValue: SunburstChartViewModel(root: root))
    }

    var body: some View {
        SunburstChartCanvas(
            rootNode: viewModel.chartRoot,
            revealProgress: revealProgress,
            onNodeTap: viewModel.open,
            onCenterTap: viewModel.navigateBack
        )
        .aspectRatio(1, contentMode: .fit)
        // The surrounding cards use leading-aligned stacks. Expand the chart
        // wrapper to the available width so the square canvas stays centered.
        .frame(maxWidth: .infinity, alignment: .center)
        .onChange(of: root) { _, newRoot in
            viewModel.replaceRoot(newRoot)
        }
    }
}

// MARK: - 8. Preview Mock 数据
extension DemoFileNode {
    static func createRandomTree(
        currentDepth: Int,
        maxDepth: Int,
        name: String,
        color: Color
    ) -> DemoFileNode {
        let stopProbability = Double(currentDepth) / Double(maxDepth)
        let isLeaf = currentDepth >= maxDepth
            || (currentDepth > 2 && Double.random(in: 0...1) < stopProbability * 0.65)

        if isLeaf {
            let isGiantFile = Double.random(in: 0...1) < 0.12
            let randomSize = isGiantFile
                ? Double.random(in: 10...35)
                : Double.random(in: 0.05...2)
            return DemoFileNode(
                name: name,
                byteCount: Int64(randomSize * 1_000_000_000),
                color: color
            )
        }

        let maximumChildCount = currentDepth > 5 ? 3 : 5
        let childCount = Int.random(in: 1...maximumChildCount)
        var children: [DemoFileNode] = []

        for index in 1...childCount {
            let childColor = color.饱和度调整(
                satFactor: Double.random(in: 0.7...1.2),
                brightFactor: Double.random(in: 0.8...1.2)
            )
            children.append(createRandomTree(
                currentDepth: currentDepth + 1,
                maxDepth: maxDepth,
                name: "\(name)-\(index)",
                color: childColor
            ))
        }

        return DemoFileNode(name: name, byteCount: 0, color: color, children: children)
    }

    static var sampleData: DemoFileNode {
        let topLevelCount = Int.random(in: 4...6)
        let shuffledColors = SunburstPalette.colors.shuffled()
        var topLevelNodes: [DemoFileNode] = []

        for index in 1...topLevelCount {
            let color = shuffledColors[(index - 1) % shuffledColors.count]
            topLevelNodes.append(createRandomTree(
                currentDepth: 1,
                maxDepth: Int.random(in: 5...8),
                name: "Section-\(index)",
                color: color
            ))
        }

        return DemoFileNode(name: "Root", byteCount: 0, children: topLevelNodes)
    }
}

#Preview("8-Layer Sunburst Chart") {
    SunburstChartCanvas(rootNode: DemoFileNode.sampleData)
        .frame(width: 520, height: 520)
        .preferredColorScheme(.dark)
}
