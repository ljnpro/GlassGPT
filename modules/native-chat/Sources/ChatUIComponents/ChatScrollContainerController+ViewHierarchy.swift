import SwiftUI
import UIKit

@MainActor
extension ChatScrollContainerController {
    func configureViewHierarchy() {
        view.backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        backgroundTapTarget.handler = { [weak self] in
            self?.onBackgroundTap?()
        }
        let contentSizeRelay = ChatScrollContainerContentSizeRelay { [weak self] in
            self?.handleObservedContentSizeChange()
        }
        let tapGesture = UITapGestureRecognizer(
            target: backgroundTapTarget,
            action: #selector(ChatScrollContainerTapTarget.handleTap)
        )
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        scrollView.addGestureRecognizer(tapGesture)

        contentHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        contentHostingController.view.backgroundColor = .clear
        contentHostingController.sizingOptions = [.intrinsicContentSize]

        addChild(contentHostingController)
        scrollView.addSubview(contentHostingController.view)
        contentHostingController.didMove(toParent: self)

        composerHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        composerHostingController.view.backgroundColor = .clear
        composerHostingController.sizingOptions = [.intrinsicContentSize]

        addChild(composerHostingController)
        view.addSubview(composerHostingController.view)
        composerHostingController.didMove(toParent: self)

        let scrollBottomConstraint = scrollView.bottomAnchor.constraint(
            equalTo: composerHostingController.view.topAnchor,
            constant: -fixedBottomGap
        )
        let composerBottomConstraint = composerHostingController.view.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor
        )
        self.scrollBottomConstraint = scrollBottomConstraint
        self.composerBottomConstraint = composerBottomConstraint

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollBottomConstraint,

            composerHostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            composerHostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            composerBottomConstraint,

            contentHostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentHostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentHostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentHostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentHostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        contentSizeObservation = scrollView.observe(\.contentSize, options: [.new]) { [contentSizeRelay] _, _ in
            Task {
                await contentSizeRelay.notifyChange()
            }
        }
    }
}
