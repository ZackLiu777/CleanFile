/// Coordinates the existing opening animation with the destination's readiness.
/// Once revealed, content is never covered again by a foreground refresh.
nonisolated struct AppLaunchState: Equatable {
    enum Destination: Equatable {
        case preparing, ready, recovery
    }

    enum Phase: Equatable {
        case animating, waitingForDestination, content, recovery
    }

    private(set) var phase: Phase
    private var destination: Destination

    init(destination: Destination, skipsAnimation: Bool = false) {
        self.destination = destination 
        phase = skipsAnimation ? .content : .animating
    }

    var showsOpening: Bool {
        phase == .animating || phase == .waitingForDestination
    }

    mutating func animationFinished() {
        guard phase == .animating else { return }
        phase = .waitingForDestination
        revealDestinationIfPossible()
    }

    mutating func destinationChanged(to destination: Destination) {
        self.destination = destination
        revealDestinationIfPossible()
    }

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
