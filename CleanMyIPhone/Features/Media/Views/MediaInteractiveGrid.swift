//
//  MediaInteractiveGrid.swift
//  CleanMyIPhone
//
//  媒体分类详情页的原生交互式网格。
//  使用 UICollectionViewTransitionLayout 让 2 / 5 / 8 列布局随捏合进度连续重排，
//  同时保留日期分组、预览入口、长按选择与滑动批量选择能力。
//

import Photos
import SwiftUI
import UIKit

// MARK: - MediaInteractiveGrid

/// 将支持交互式布局过渡的 UICollectionView 接入 SwiftUI 媒体详情页。
struct MediaInteractiveGrid: UIViewRepresentable {
    let sections: [MediaDateSection]
    @Binding var selectedIDs: Set<String>
    let isSelecting: Bool
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let accentColor: Color
    let onOpen: (String) -> Void
    let onBeginSelecting: (String) -> Void

    /// 创建负责 UIKit 数据源、布局过渡和手势协调的桥接对象。
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 创建集合视图，并一次性安装单元格、分区标题和手势识别器。
    func makeUIView(context: Context) -> UICollectionView {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: MediaDensityFlowLayout(density: .large)
        )
        // UIKit 默认可能将滚动容器视为不透明；显式关闭后才能透出 SwiftUI 的主题背景。
        collectionView.isOpaque = false
        collectionView.backgroundColor = .clear
        let transparentBackgroundView = UIView(frame: .zero)
        transparentBackgroundView.isOpaque = false
        transparentBackgroundView.backgroundColor = .clear
        collectionView.backgroundView = transparentBackgroundView
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.isDirectionalLockEnabled = true
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.register(
            UICollectionViewCell.self,
            forCellWithReuseIdentifier: Coordinator.cellReuseIdentifier
        )
        collectionView.register(
            MediaInteractiveGridHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: Coordinator.headerReuseIdentifier
        )

        context.coordinator.installGestures(on: collectionView)
        context.coordinator.collectionView = collectionView
        context.coordinator.sectionSignature = context.coordinator.makeSectionSignature(from: sections)
        return collectionView
    }

    /// 同步 SwiftUI 状态；资源结构改变时刷新数据，选择改变时只刷新可见单元格。
    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        let newSignature = context.coordinator.makeSectionSignature(from: sections)

        if newSignature != context.coordinator.sectionSignature {
            context.coordinator.cancelLayoutTransitionIfNeeded()
            context.coordinator.sectionSignature = newSignature
            collectionView.reloadData()
        } else {
            context.coordinator.refreshVisibleContent(in: collectionView)
        }
    }

    // MARK: - Coordinator

    /// 集合视图协调器，集中管理数据源、选择交互和捏合驱动的布局过渡。
    @MainActor
    final class Coordinator: NSObject,
        UICollectionViewDataSource,
        UICollectionViewDelegate,
        UIGestureRecognizerDelegate
    {
        static let cellReuseIdentifier = "MediaInteractiveGrid.Cell"
        static let headerReuseIdentifier = "MediaInteractiveGrid.Header"

        var parent: MediaInteractiveGrid
        weak var collectionView: UICollectionView?
        var sectionSignature = [String]()

        private var density = MediaGridDensity.large
        private var targetDensity: MediaGridDensity?
        private var transitionLayout: UICollectionViewTransitionLayout?
        private var transitionProgress: CGFloat = 0
        private var transitionDirection: MediaGridTransitionDirection?
        private var isCompletingTransition = false
        private var pinchAnchor: MediaPinchAnchor?

        private var batchSelectionStartIndexPath: IndexPath?
        private var batchSelectionStartLocation: CGPoint?
        private var batchSelectionLastLocation: CGPoint?
        private var batchSelectionDirection: MediaBatchSelectionDirection?
        private var isBatchSelectionActive = false
        private var isBatchSelectionRejected = false
        private var selectionFeedbackGenerator: UISelectionFeedbackGenerator?
        private weak var batchSelectionPanGesture: UIPanGestureRecognizer?

        /// 保存初始 SwiftUI 配置，后续由 updateUIView 持续替换为最新值。
        init(parent: MediaInteractiveGrid) {
            self.parent = parent
        }

        /// 安装捏合、长按和独立方向批选手势，避免批选依赖滚动手势的内部状态。
        func installGestures(on collectionView: UICollectionView) {
            let pinchGesture = UIPinchGestureRecognizer(
                target: self,
                action: #selector(handlePinch(_:))
            )
            pinchGesture.delegate = self
            pinchGesture.cancelsTouchesInView = false
            collectionView.addGestureRecognizer(pinchGesture)

            let longPressGesture = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            longPressGesture.minimumPressDuration = 0.45
            longPressGesture.delegate = self
            collectionView.addGestureRecognizer(longPressGesture)

            let batchSelectionPanGesture = UIPanGestureRecognizer(
                target: self,
                action: #selector(handleSelectionPan(_:))
            )
            batchSelectionPanGesture.maximumNumberOfTouches = 1
            batchSelectionPanGesture.delegate = self
            batchSelectionPanGesture.cancelsTouchesInView = true
            collectionView.addGestureRecognizer(batchSelectionPanGesture)

            // 滚动先等待批选手势判断方向：左右或向下时批选胜出，向上时交还浏览。
            collectionView.panGestureRecognizer.require(toFail: batchSelectionPanGesture)
            self.batchSelectionPanGesture = batchSelectionPanGesture
        }

        /// 生成只反映分区和资源顺序的签名，避免选择状态变化触发整表 reloadData。
        func makeSectionSignature(from sections: [MediaDateSection]) -> [String] {
            sections.flatMap { section in
                [section.id] + section.assetIDs
            }
        }

        /// 终止尚未完成的布局过渡，避免数据刷新落在临时 TransitionLayout 上。
        func cancelLayoutTransitionIfNeeded() {
            guard transitionLayout != nil, let collectionView else { return }
            collectionView.cancelInteractiveTransition()
            resetLayoutTransitionState()
        }

        /// 仅重建屏幕内单元格和标题内容，降低批量选择时的刷新成本。
        func refreshVisibleContent(in collectionView: UICollectionView) {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) else { continue }
                configure(cell, at: indexPath)
            }
            for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(
                ofKind: UICollectionView.elementKindSectionHeader
            ) {
                guard let header = collectionView.supplementaryView(
                    forElementKind: UICollectionView.elementKindSectionHeader,
                    at: indexPath
                ) else { continue }
                configure(header, forSection: indexPath.section)
            }
        }

        // MARK: UICollectionViewDataSource

        /// 返回日期分区数量。
        func numberOfSections(in collectionView: UICollectionView) -> Int {
            parent.sections.count
        }

        /// 返回指定日期分区中的资源数量。
        func collectionView(
            _ collectionView: UICollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            guard parent.sections.indices.contains(section) else { return 0 }
            return parent.sections[section].assetIDs.count
        }

        /// 复用并配置媒体缩略图单元格。
        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: Self.cellReuseIdentifier,
                for: indexPath
            )
            configure(cell, at: indexPath)
            return cell
        }

        /// 复用并配置日期标题，保持原页面的日期和项目数量语义。
        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: Self.headerReuseIdentifier,
                for: indexPath
            )
            configure(header, forSection: indexPath.section)
            return header
        }

        // MARK: UICollectionViewDelegate

        /// 普通模式打开预览；选择模式则切换当前资源的选中状态。
        func collectionView(
            _ collectionView: UICollectionView,
            didSelectItemAt indexPath: IndexPath
        ) {
            guard let assetID = assetID(at: indexPath) else { return }
            if parent.isSelecting {
                toggleSelection(assetID)
                refreshCell(for: assetID)
            } else {
                parent.onOpen(assetID)
            }
        }

        /// 允许集合视图滚动与捏合识别同时进行，避免手势切换时突然中断画面。
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer
                || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        /// 在手指落下时保存真正的起点；必须从缩略图内部起手才允许批选识别。
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard gestureRecognizer === batchSelectionPanGesture else { return true }
            guard parent.isSelecting, let collectionView else { return false }

            synchronizeDensityWithInstalledLayout(in: collectionView)
            guard
                !isCompletingTransition,
                !(collectionView.collectionViewLayout is UICollectionViewTransitionLayout)
            else { return false }
            resetBatchSelection()
            let location = touch.location(in: collectionView)
            beginBatchSelectionCandidate(at: location, in: collectionView)
            return batchSelectionStartIndexPath != nil
        }

        /// 仅允许明确横向或向下的一指拖动开始，向上和方向不明的手势直接失败。
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === batchSelectionPanGesture else { return true }
            guard
                let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
                batchSelectionStartIndexPath != nil
            else { return false }

            let velocity = panGesture.velocity(in: collectionView)
            if velocity.x > 0, velocity.x > abs(velocity.y) * 1.35 {
                batchSelectionDirection = .right
                return true
            }
            if velocity.x < 0, -velocity.x > abs(velocity.y) * 1.35 {
                batchSelectionDirection = .left
                return true
            }
            if velocity.y > 0, velocity.y > abs(velocity.x) * 1.35 {
                batchSelectionDirection = .down
                return true
            }
            return false
        }

        // MARK: Cell and header configuration

        /// 使用 UIHostingConfiguration 承载现有 SwiftUI 缩略图视图，避免复制图片加载链路。
        private func configure(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
            guard let assetID = assetID(at: indexPath) else {
                cell.contentConfiguration = nil
                return
            }
            let selected = parent.selectedIDs.contains(assetID)
            let currentDensity = displayedDensity
            cell.contentConfiguration = UIHostingConfiguration {
                MediaInteractiveGridCellContent(
                    assetID: assetID,
                    isSelecting: parent.isSelecting,
                    isSelected: selected,
                    density: currentDensity,
                    viewModel: parent.viewModel,
                    accentColor: parent.accentColor
                )
            }
            .margins(.all, 0)
            .background {
                Color.clear
            }
            // Cell、contentView 与 HostingConfiguration 必须同时透明，避免任一 UIKit 层回填系统背景。
            cell.isOpaque = false
            cell.backgroundColor = .clear
            cell.contentView.backgroundColor = .clear
            cell.backgroundView = nil
            cell.selectedBackgroundView = nil
            cell.clipsToBounds = true
            cell.accessibilityIdentifier = "media.asset.\(assetID)"
        }

        /// 配置分区标题；标题使用系统本地化日期格式，数量沿用当前页面文案。
        private func configure(_ header: UICollectionReusableView, forSection index: Int) {
            guard
                parent.sections.indices.contains(index),
                let header = header as? MediaInteractiveGridHeaderView
            else { return }
            let section = parent.sections[index]
            header.configure(
                title: dateTitle(section.day),
                itemCount: itemCount(section.assetIDs.count)
            )
        }

        /// 返回布局过渡正在指向的档位，使过渡末段出现的新单元格采用目标档视觉密度。
        private var displayedDensity: MediaGridDensity {
            guard transitionProgress >= 0.5, let targetDensity else { return density }
            return targetDensity
        }

        /// 从已经安装的稳定布局回读密度，防止布局完成回调与下一次手势到达顺序不同步。
        private func synchronizeDensityWithInstalledLayout(in collectionView: UICollectionView) {
            guard let layout = collectionView.collectionViewLayout as? MediaDensityFlowLayout else { return }
            density = layout.density
            // UIKit 已换回稳定布局即表示交互过渡结束；同步清除可能晚一拍的桥接状态，
            // 避免刚缩放完成时 isCompletingTransition 继续阻断新的单指选择手势。
            if transitionLayout != nil || isCompletingTransition {
                resetLayoutTransitionState()
            }
        }

        /// 安全读取指定 IndexPath 对应的资源标识。
        private func assetID(at indexPath: IndexPath) -> String? {
            guard parent.sections.indices.contains(indexPath.section) else { return nil }
            let identifiers = parent.sections[indexPath.section].assetIDs
            guard identifiers.indices.contains(indexPath.item) else { return nil }
            return identifiers[indexPath.item]
        }

        /// 根据资源标识查找当前 IndexPath，仅用于更新屏幕内受影响的单元格。
        private func indexPath(for assetID: String) -> IndexPath? {
            for (sectionIndex, section) in parent.sections.enumerated() {
                if let itemIndex = section.assetIDs.firstIndex(of: assetID) {
                    return IndexPath(item: itemIndex, section: sectionIndex)
                }
            }
            return nil
        }

        /// 重新配置单个可见单元格，使选择标记在手指滑过时即时响应。
        private func refreshCell(for assetID: String) {
            guard
                let collectionView,
                let indexPath = indexPath(for: assetID),
                let cell = collectionView.cellForItem(at: indexPath)
            else { return }
            configure(cell, at: indexPath)
        }

        /// 将日期转换为用户当前区域的 Today、Yesterday 或完整日期标题。
        private func dateTitle(_ day: Date?) -> String {
            guard let day else { return String(localized: "Unknown Date") }
            let calendar = Calendar.current
            if calendar.isDateInToday(day) {
                return String(localized: "Today")
            }
            if calendar.isDateInYesterday(day) {
                return String(localized: "Yesterday")
            }
            return day.formatted(.dateTime.year().month(.wide).day())
        }

        /// 使用项目既有本地化格式生成分区资源数量。
        private func itemCount(_ count: Int) -> String {
            String.localizedStringWithFormat(String(localized: "%lld items"), Int64(count))
        }

        // MARK: Interactive pinch transition

        /// 将捏合比例连续映射到 UICollectionViewTransitionLayout 的过渡进度。
        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let collectionView, !isCompletingTransition else { return }

            switch gesture.state {
            case .began, .changed:
                if transitionLayout == nil {
                    beginLayoutTransitionIfNeeded(for: gesture, in: collectionView)
                }
                updateLayoutTransition(for: gesture, in: collectionView)
            case .ended:
                completeLayoutTransition(using: gesture.velocity, in: collectionView)
            case .cancelled, .failed:
                cancelLayoutTransition(in: collectionView)
            default:
                break
            }
        }

        /// 根据首次明确的捏合方向选择相邻档位，并记录手指下方资源作为视觉锚点。
        private func beginLayoutTransitionIfNeeded(
            for gesture: UIPinchGestureRecognizer,
            in collectionView: UICollectionView
        ) {
            let direction: MediaGridTransitionDirection
            if gesture.scale < 0.985 {
                direction = .denser
            } else if gesture.scale > 1.015 {
                direction = .larger
            } else {
                return
            }

            guard let nextDensity = density.adjacent(in: direction) else { return }
            let touchLocation = gesture.location(in: collectionView)
            pinchAnchor = makePinchAnchor(at: touchLocation, in: collectionView)
            transitionDirection = direction
            targetDensity = nextDensity
            transitionProgress = 0

            let nextLayout = MediaDensityFlowLayout(density: nextDensity)
            transitionLayout = collectionView.startInteractiveTransition(
                to: nextLayout
            ) { [weak self] completed, finished in
                guard let self else { return }
                if completed, finished, let targetDensity = self.targetDensity {
                    self.density = targetDensity
                }
                self.resetLayoutTransitionState()
                self.refreshVisibleContent(in: collectionView)
            }
        }

        /// 更新插值进度并修正 contentOffset，使捏合中心的资源保持在手指下方。
        private func updateLayoutTransition(
            for gesture: UIPinchGestureRecognizer,
            in collectionView: UICollectionView
        ) {
            guard
                let transitionLayout,
                let transitionDirection
            else { return }

            let rawProgress: CGFloat
            switch transitionDirection {
            case .denser:
                rawProgress = (1 - gesture.scale) / 0.36
            case .larger:
                rawProgress = (gesture.scale - 1) / 0.46
            }
            let progress = min(max(rawProgress, 0), 1)
            transitionProgress = progress
            transitionLayout.transitionProgress = progress
            transitionLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            preservePinchAnchor(at: gesture.location(in: collectionView), in: collectionView)
        }

        /// 根据完成度和手势速度决定安装目标布局或回退原布局。
        private func completeLayoutTransition(
            using velocity: CGFloat,
            in collectionView: UICollectionView
        ) {
            guard let direction = transitionDirection, transitionLayout != nil else {
                resetLayoutTransitionState()
                return
            }
            let directionalVelocity: CGFloat = switch direction {
            case .denser: -velocity
            case .larger: velocity
            }
            let shouldFinish = transitionProgress >= 0.38
                || (transitionProgress >= 0.12 && directionalVelocity > 0.65)

            isCompletingTransition = true
            if shouldFinish {
                collectionView.finishInteractiveTransition()
            } else {
                collectionView.cancelInteractiveTransition()
            }
        }

        /// 在系统取消手势时恢复原布局，并清理临时过渡状态。
        private func cancelLayoutTransition(in collectionView: UICollectionView) {
            guard transitionLayout != nil else {
                resetLayoutTransitionState()
                return
            }
            isCompletingTransition = true
            collectionView.cancelInteractiveTransition()
        }

        /// 从手指位置构造归一化单元格锚点，用于布局尺寸变化后的视口补偿。
        private func makePinchAnchor(
            at location: CGPoint,
            in collectionView: UICollectionView
        ) -> MediaPinchAnchor? {
            let indexPath = collectionView.indexPathForItem(at: location)
                ?? nearestVisibleIndexPath(to: location, in: collectionView)
            guard
                let indexPath,
                let attributes = collectionView.layoutAttributesForItem(at: indexPath),
                attributes.bounds.width > 0,
                attributes.bounds.height > 0
            else { return nil }

            return MediaPinchAnchor(
                indexPath: indexPath,
                normalizedPoint: CGPoint(
                    x: (location.x - attributes.frame.minX) / attributes.frame.width,
                    y: (location.y - attributes.frame.minY) / attributes.frame.height
                )
            )
        }

        /// 寻找离捏合中心最近的可见资源，允许手指落在网格间隙或日期标题上。
        private func nearestVisibleIndexPath(
            to location: CGPoint,
            in collectionView: UICollectionView
        ) -> IndexPath? {
            collectionView.indexPathsForVisibleItems.min { lhs, rhs in
                let leftCenter = collectionView.layoutAttributesForItem(at: lhs)?.center ?? .zero
                let rightCenter = collectionView.layoutAttributesForItem(at: rhs)?.center ?? .zero
                return hypot(leftCenter.x - location.x, leftCenter.y - location.y)
                    < hypot(rightCenter.x - location.x, rightCenter.y - location.y)
            }
        }

        /// 根据过渡布局中的插值 frame 调整滚动偏移，减少网格重排时的纵向跳动。
        private func preservePinchAnchor(
            at touchLocation: CGPoint,
            in collectionView: UICollectionView
        ) {
            guard
                let pinchAnchor,
                let attributes = collectionView.collectionViewLayout.layoutAttributesForItem(
                    at: pinchAnchor.indexPath
                )
            else { return }

            let anchorContentPoint = CGPoint(
                x: attributes.frame.minX + attributes.frame.width * pinchAnchor.normalizedPoint.x,
                y: attributes.frame.minY + attributes.frame.height * pinchAnchor.normalizedPoint.y
            )
            // location(in:) 位于 collectionView 的内容坐标系；先扣除当前 offset，
            // 得到手指在可见视口内的位置，才能反推出新的绝对 contentOffset。
            let viewportPoint = CGPoint(
                x: touchLocation.x - collectionView.contentOffset.x,
                y: touchLocation.y - collectionView.contentOffset.y
            )
            var proposedOffset = CGPoint(
                x: anchorContentPoint.x - viewportPoint.x,
                y: anchorContentPoint.y - viewportPoint.y
            )
            let inset = collectionView.adjustedContentInset
            let minY = -inset.top
            let maxY = max(
                minY,
                collectionView.contentSize.height - collectionView.bounds.height + inset.bottom
            )
            proposedOffset.x = collectionView.contentOffset.x
            proposedOffset.y = min(max(proposedOffset.y, minY), maxY)
            collectionView.setContentOffset(proposedOffset, animated: false)
        }

        /// 清理一次过渡的临时引用，允许下一次随机时机捏合从稳定布局重新开始。
        private func resetLayoutTransitionState() {
            targetDensity = nil
            transitionLayout = nil
            transitionProgress = 0
            transitionDirection = nil
            isCompletingTransition = false
            pinchAnchor = nil
        }

        // MARK: Selection gestures

        /// 长按任意资源进入选择模式，并把当前资源作为第一个选中项。
        @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard
                gesture.state == .began,
                let collectionView
            else { return }
            synchronizeDensityWithInstalledLayout(in: collectionView)
            guard
                !isCompletingTransition,
                !(collectionView.collectionViewLayout is UICollectionViewTransitionLayout),
                let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)),
                let assetID = assetID(at: indexPath)
            else { return }

            parent.selectedIDs.insert(assetID)
            parent.onBeginSelecting(assetID)
            refreshCell(for: assetID)
        }

        /// 处理独立方向手势；方向竞争已在识别前完成，此处只负责更新批选范围。
        @objc private func handleSelectionPan(_ gesture: UIPanGestureRecognizer) {
            guard
                parent.isSelecting,
                !isCompletingTransition,
                let collectionView,
                !(collectionView.collectionViewLayout is UICollectionViewTransitionLayout)
            else {
                resetBatchSelection()
                return
            }
            let location = gesture.location(in: collectionView)

            switch gesture.state {
            case .began:
                synchronizeDensityWithInstalledLayout(in: collectionView)
                updateBatchSelection(
                    gesture: gesture,
                    at: location,
                    in: collectionView
                )
            case .changed:
                updateBatchSelection(
                    gesture: gesture,
                    at: location,
                    in: collectionView
                )
            case .ended, .cancelled, .failed:
                resetBatchSelection()
            default:
                break
            }
        }

        /// 记录手势起点；此时只准备触觉引擎，不改变任何资源的选择状态。
        private func beginBatchSelectionCandidate(
            at location: CGPoint,
            in collectionView: UICollectionView
        ) {
            guard let indexPath = collectionView.indexPathForItem(at: location) else {
                // 必须从缩略图内部起手；从标题或空白处开始的滚动不能中途变成批选。
                isBatchSelectionRejected = true
                return
            }
            batchSelectionStartIndexPath = indexPath
            batchSelectionStartLocation = location
            batchSelectionLastLocation = location
            batchSelectionDirection = nil
            isBatchSelectionActive = false
            isBatchSelectionRejected = false
            selectionFeedbackGenerator = UISelectionFeedbackGenerator(view: collectionView)
            selectionFeedbackGenerator?.prepare()
        }

        /// 使用平移量和速度建立初始门槛；激活后改由连续轨迹决定每一段的选择语义。
        private func updateBatchSelection(
            gesture: UIPanGestureRecognizer,
            at location: CGPoint,
            in collectionView: UICollectionView
        ) {
            guard
                let startIndexPath = batchSelectionStartIndexPath,
                let startLocation = batchSelectionStartLocation,
                !isBatchSelectionRejected
            else { return }

            let translation = gesture.translation(in: collectionView)
            let velocity = gesture.velocity(in: collectionView)
            let horizontalDistance = translation.x
            let verticalDistance = translation.y

            if !isBatchSelectionActive {
                guard let batchSelectionDirection else { return }
                let reachedActivationThreshold: Bool = switch batchSelectionDirection {
                case .right:
                    horizontalDistance >= 18
                        && horizontalDistance > abs(verticalDistance) * 1.45
                        && velocity.x > 0
                case .left:
                    horizontalDistance <= -18
                        && -horizontalDistance > abs(verticalDistance) * 1.45
                        && velocity.x < 0
                case .down:
                    verticalDistance >= 18
                        && verticalDistance > abs(horizontalDistance) * 1.45
                        && velocity.y > 0
                case .up:
                    false
                }
                guard reachedActivationThreshold else { return }

                isBatchSelectionActive = true
                batchSelectionLastLocation = startLocation
                applyBatchSelection(
                    to: [startIndexPath],
                    direction: batchSelectionDirection
                )
                selectionFeedbackGenerator?.selectionChanged()
                selectionFeedbackGenerator?.prepare()
            }

            guard
                isBatchSelectionActive,
                let previousLocation = batchSelectionLastLocation,
                let currentDirection = MediaBatchSelectionDirection.resolve(
                    from: previousLocation,
                    to: location
                )
            else { return }

            batchSelectionDirection = currentDirection
            let traversedIndexPaths = batchSelectionIndexPaths(
                from: previousLocation,
                to: location,
                limitedTo: startIndexPath.section,
                in: collectionView
            )
            batchSelectionLastLocation = location
            if applyBatchSelection(to: traversedIndexPaths, direction: currentDirection) {
                playBatchSelectionFeedback()
            }
        }

        /// 沿两次回调之间的真实触摸轨迹采样单元格，让右转下、左转上都保持同一次手势。
        private func batchSelectionIndexPaths(
            from startLocation: CGPoint,
            to endLocation: CGPoint,
            limitedTo section: Int,
            in collectionView: UICollectionView
        ) -> [IndexPath] {
            let deltaX = endLocation.x - startLocation.x
            let deltaY = endLocation.y - startLocation.y
            let distance = hypot(deltaX, deltaY)
            let itemSize = (collectionView.collectionViewLayout as? MediaDensityFlowLayout)?.itemSize
                ?? CGSize(width: 44, height: 44)
            let sampleStride = max(6, min(itemSize.width, itemSize.height) * 0.3)
            let sampleCount = max(1, Int(ceil(distance / sampleStride)))
            var result = [IndexPath]()

            for step in 0 ... sampleCount {
                let progress = CGFloat(step) / CGFloat(sampleCount)
                let point = CGPoint(
                    x: startLocation.x + deltaX * progress,
                    y: startLocation.y + deltaY * progress
                )
                guard
                    let indexPath = collectionView.indexPathForItem(at: point),
                    indexPath.section == section,
                    result.last != indexPath
                else { continue }
                result.append(indexPath)
            }
            return result
        }

        /// 把当前轨迹段统一设置为选择或取消；已处于目标状态的资源不会重复刷新。
        @discardableResult
        private func applyBatchSelection(
            to indexPaths: [IndexPath],
            direction: MediaBatchSelectionDirection
        ) -> Bool {
            var didChangeSelection = false
            for assetID in indexPaths.compactMap({ assetID(at: $0) }) {
                let changed = setSelection(direction.shouldSelect, for: assetID)
                guard changed else { continue }
                didChangeSelection = true
                refreshCell(for: assetID)
            }
            return didChangeSelection
        }

        /// 将单个资源设置为目标选择状态，并返回其状态是否真的发生变化。
        private func setSelection(_ shouldSelect: Bool, for assetID: String) -> Bool {
            if shouldSelect {
                return parent.selectedIDs.insert(assetID).inserted
            }
            return parent.selectedIDs.remove(assetID) != nil
        }

        /// 播放一次离散选择反馈，并立即重新准备触觉引擎供下一次范围扩展使用。
        private func playBatchSelectionFeedback() {
            selectionFeedbackGenerator?.selectionChanged()
            selectionFeedbackGenerator?.prepare()
        }

        /// 切换单个资源的选中状态。
        private func toggleSelection(_ assetID: String) {
            if parent.selectedIDs.contains(assetID) {
                parent.selectedIDs.remove(assetID)
            } else {
                parent.selectedIDs.insert(assetID)
            }
        }

        /// 结束批选并释放触觉对象，下一次手势重新判断横向或纵向意图。
        private func resetBatchSelection() {
            batchSelectionStartIndexPath = nil
            batchSelectionStartLocation = nil
            batchSelectionLastLocation = nil
            batchSelectionDirection = nil
            isBatchSelectionActive = false
            isBatchSelectionRejected = false
            selectionFeedbackGenerator = nil
        }
    }
}

// MARK: - MediaDensityFlowLayout

/// 根据当前集合视图宽度计算固定列数，作为交互式过渡的起点和终点布局。
private final class MediaDensityFlowLayout: UICollectionViewFlowLayout {
    let density: MediaGridDensity

    /// 保存目标密度，并设置各档位一致的基础间距和日期标题高度。
    init(density: MediaGridDensity) {
        self.density = density
        super.init()
        scrollDirection = .vertical
        minimumLineSpacing = density.spacing
        minimumInteritemSpacing = density.spacing
        sectionInset = .zero
        headerReferenceSize = CGSize(width: 1, height: 42)
    }

    /// 支持 UIKit 从归档恢复布局；程序化页面不会走到该入口。
    required init?(coder: NSCoder) {
        nil
    }

    /// 每次容器宽度变化时重新计算正方形单元格，兼容旋转和分屏尺寸变化。
    override func prepare() {
        guard let collectionView else {
            super.prepare()
            return
        }
        let spacingWidth = CGFloat(density.columnCount - 1) * density.spacing
        let availableWidth = max(collectionView.bounds.width - spacingWidth, 1)
        let side = floor(availableWidth / CGFloat(density.columnCount))
        itemSize = CGSize(width: side, height: side)
        headerReferenceSize = CGSize(width: collectionView.bounds.width, height: 42)
        super.prepare()
    }

    /// 只在集合视图宽度改变时使布局失效，滚动时避免重复计算全部单元格。
    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return abs(newBounds.width - collectionView.bounds.width) > 0.5
    }
}

// MARK: - SwiftUI cell content

/// 单个媒体缩略图内容；视觉层级沿用原页面，仅随网格密度隐藏不适合的小尺寸信息。
private struct MediaInteractiveGridCellContent: View {
    let assetID: String
    let isSelecting: Bool
    let isSelected: Bool
    let density: MediaGridDensity
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let accentColor: Color

    /// 组合缩略图、媒体类型标记、文件信息和选择状态。
    var body: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                MediaAssetThumbnailView(assetID: assetID, viewModel: viewModel)
            }
            .overlay(alignment: .topLeading) {
                if density.showsBadges {
                    mediaBadge
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    selectionIndicator
                }
            }
            .overlay(alignment: .bottom) {
                if density.showsMetadata {
                    assetInformation
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .accessibilityElement(children: .combine)
    }

    /// 显示 Live Photo 图标或视频时长；普通静态图片不添加额外装饰。
    @ViewBuilder
    private var mediaBadge: some View {
        if let asset = viewModel.asset(withIdentifier: assetID) {
            if asset.mediaSubtypes.contains(.photoLive) {
                Image(systemName: "livephoto")
                    .font(density.badgeFont.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(density.badgePadding)
                    .background(.black.opacity(0.48), in: Circle())
                    .padding(density.badgeOuterPadding)
                    .accessibilityLabel("Live Photo")
            } else if asset.mediaType == .video {
                Text(videoDurationText(asset.duration))
                    .font(density.durationFont.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, density.badgePadding)
                    .padding(.vertical, max(2, density.badgePadding - 2))
                    .background(.black.opacity(0.58), in: Capsule())
                    .padding(density.badgeOuterPadding)
            }
        }
    }

    /// 在 2 列模式显示文件名和估算体积，较密网格隐藏文字以保证缩略图可读性。
    private var assetInformation: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.displayName(for: assetID))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(
                ByteCountFormatter.string(
                    fromByteCount: viewModel.estimatedByteCount(for: assetID),
                    countStyle: .file
                )
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.76))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 26)
        .padding(.bottom, 9)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// 根据选中状态显示圆形标记，并随密度缩放以避免遮挡小缩略图。
    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(density.selectionIndicatorFont)
            .foregroundStyle(isSelected ? accentColor : .white)
            .shadow(radius: 2)
            .padding(density.selectionIndicatorPadding)
            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }

    /// 将视频秒数格式化为 m:ss 或 h:mm:ss。
    private func videoDurationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// 日期分区标题，使用原生标签避免补充视图复用时额外创建 SwiftUI 承载控制器。
private final class MediaInteractiveGridHeaderView: UICollectionReusableView {
    private let titleLabel = UILabel()
    private let itemCountLabel = UILabel()

    /// 创建日期标题的固定视图层级和约束。
    override init(frame: CGRect) {
        super.init(frame: frame)

        // UICollectionReusableView 没有 contentView；透明化 Header 自身即可避免吸顶时形成白色横层。
        isOpaque = false
        backgroundColor = .clear
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        itemCountLabel.font = .preferredFont(forTextStyle: .caption1)
        itemCountLabel.textColor = .secondaryLabel
        itemCountLabel.adjustsFontForContentSizeCategory = true
        itemCountLabel.setContentHuggingPriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [titleLabel, itemCountLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    /// 支持 UIKit 从归档恢复补充视图；本页面只使用程序化创建。
    required init?(coder: NSCoder) {
        nil
    }

    /// 更新复用标题中的日期和项目数量。
    func configure(title: String, itemCount: String) {
        titleLabel.text = title
        itemCountLabel.text = itemCount
    }
}

// MARK: - Supporting models

/// 描述连续批选轨迹当前一段的操作方向；右/下选择，左/上取消。
enum MediaBatchSelectionDirection: Equatable {
    case right
    case left
    case down
    case up

    /// 返回当前方向对应的目标选择状态。
    var shouldSelect: Bool {
        self == .right || self == .down
    }

    /// 从相邻触摸点解析主方向，小幅抖动不会改变上一段已经应用的选择结果。
    static func resolve(
        from start: CGPoint,
        to end: CGPoint,
        minimumDistance: CGFloat = 2.5
    ) -> MediaBatchSelectionDirection? {
        let horizontalDistance = end.x - start.x
        let verticalDistance = end.y - start.y
        guard hypot(horizontalDistance, verticalDistance) >= minimumDistance else { return nil }

        if abs(horizontalDistance) >= abs(verticalDistance) {
            return horizontalDistance >= 0 ? .right : .left
        }
        return verticalDistance >= 0 ? .down : .up
    }
}

/// 媒体相册的三档视觉密度：2 列、5 列和 8 列。
private enum MediaGridDensity: Int, CaseIterable {
    case large = 0
    case medium = 1
    case compact = 2

    /// 返回当前档位对应的固定列数。
    var columnCount: Int {
        switch self {
        case .large: 2
        case .medium: 5
        case .compact: 8
        }
    }

    /// 较密网格使用更小间距，保持连续的系统相册观感。
    var spacing: CGFloat {
        switch self {
        case .large: 3
        case .medium: 2
        case .compact: 1
        }
    }

    /// 文件名与体积只在最大缩略图档位显示。
    var showsMetadata: Bool { self == .large }

    /// 八列模式隐藏媒体标记，避免遮挡缩略图主体。
    var showsBadges: Bool { self != .compact }

    /// 返回当前方向的相邻档位；边界档位返回 nil，不创建无意义过渡。
    func adjacent(in direction: MediaGridTransitionDirection) -> MediaGridDensity? {
        let offset = direction == .denser ? 1 : -1
        return MediaGridDensity(rawValue: rawValue + offset)
    }

    /// 选择标记随密度缩放。
    var selectionIndicatorFont: Font {
        switch self {
        case .large: .title2
        case .medium: .body
        case .compact: .caption2
        }
    }

    /// 选择标记边距随密度缩小。
    var selectionIndicatorPadding: CGFloat {
        switch self {
        case .large: 6
        case .medium: 3
        case .compact: 1
        }
    }

    /// 媒体类型标记字体随缩略图变小。
    var badgeFont: Font {
        self == .large ? .caption : .caption2
    }

    /// 视频时长字体随缩略图变小。
    var durationFont: Font {
        self == .large ? .caption2 : .system(size: 8)
    }

    /// 媒体标记内部边距随密度缩小。
    var badgePadding: CGFloat {
        self == .large ? 6 : 3
    }

    /// 媒体标记与缩略图边缘的距离随密度缩小。
    var badgeOuterPadding: CGFloat {
        self == .large ? 6 : 2
    }
}

/// 表示当前捏合手势希望网格变密或变疏。
private enum MediaGridTransitionDirection {
    case denser
    case larger
}

/// 保存捏合中心所在资源及其单元格内相对位置。
private struct MediaPinchAnchor {
    let indexPath: IndexPath
    let normalizedPoint: CGPoint
}
