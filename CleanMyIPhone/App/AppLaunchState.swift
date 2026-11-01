// 开屏动画与目标页面准备状态之间的协调模型。
// 动画和目标可按任意顺序完成；内容显示后不会因后续刷新重新盖住。
// AppOpeningContainer 向该值类型报告动画结束和目标状态变化，再据此决定遮罩。
// 目标可能先于或晚于动画完成；恢复阶段只有目标就绪后才能进入内容。

/// Coordinates the existing opening animation with the destination's readiness.
/// Once revealed, content is never covered again by a foreground refresh.
nonisolated struct AppLaunchState: Equatable {
    /// 启动目标是否已准备好，或需要展示恢复界面。
    enum Destination: Equatable {
        case preparing, ready, recovery
    }

    /// 区分动画、等待、已显示内容和恢复阶段。
    enum Phase: Equatable {
        case animating, waitingForDestination, content, recovery
    }

    private(set) var phase: Phase
    private var destination: Destination

    /// 以当前目标建立启动状态；跳过动画时直接显示内容。
    init(destination: Destination, skipsAnimation: Bool = false) {
        self.destination = destination 
        phase = skipsAnimation ? .content : .animating
    }

    var showsOpening: Bool {
        phase == .animating || phase == .waitingForDestination
    }

    /// 动画完成后等待目标就绪；若目标已就绪则立即揭示内容。
    mutating func animationFinished() {
        guard phase == .animating else { return }
        phase = .waitingForDestination
        revealDestinationIfPossible()
    }

    /// 记录最新启动目标，并在等待或恢复阶段尝试推进状态。
    mutating func destinationChanged(to destination: Destination) {
        self.destination = destination
        revealDestinationIfPossible()
    }

    /// 仅允许等待阶段进入内容或恢复界面，避免前台刷新重新遮住已显示内容。
    private mutating func revealDestinationIfPossible() {
        switch (phase, destination) {
        case (.waitingForDestination, .ready), (.recovery, .ready):
            phase = .content
        case (.waitingForDestination, .recovery):
            phase = .recovery
        default:
            break
        }
    }
}
