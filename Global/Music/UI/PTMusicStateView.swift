//
//  PTMusicStateView.swift
//  CrazyDashboard
//
//  English: Shared empty, loading, error and retry presentation for Music screens.
//  Español: Presentación compartida de vacío, carga, error y reintento para Music.
//  中文：为 Music 页面统一提供空状态、加载、错误和重试界面。
//

import UIKit

@MainActor
final class PTMusicStateView: UIView {

    var onRetry: (() -> Void)?

    private let messageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private lazy var stackView: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [activityIndicator, messageLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(
        message: String?,
        showsRetry: Bool,
        showsLoading: Bool,
        actionTitle: String? = nil
    ) {
        isHidden = message == nil
        messageLabel.text = message
        retryButton.isHidden = !showsRetry
        retryButton.configuration?.title = actionTitle ?? NSLocalizedString("重试", comment: "")

        if showsLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
        activityIndicator.isHidden = !showsLoading
    }

    private func setupView() {
        backgroundColor = .clear
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.numberOfLines = 0

        retryButton.configuration = .borderedProminent()
        retryButton.configuration?.title = NSLocalizedString("重试", comment: "")
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        isHidden = true
    }

    @objc private func retryTapped() {
        onRetry?()
    }
}
