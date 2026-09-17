//
//  PTMusicDashboardCardView.swift
//  CrazyDashboard
//
//  Standalone card only.
//  The host dashboard decides where/how to mount it.
//

import UIKit

@MainActor
public final class PTMusicDashboardCardView: UIView {

    public var onOpenPlayer: (() -> Void)? {
        didSet {
            miniPlayer.onOpenPlayer = onOpenPlayer
        }
    }

    public var onPlayPause: (() -> Void)? {
        didSet {
            miniPlayer.onPlayPause = onPlayPause
        }
    }

    public var onNext: (() -> Void)? {
        didSet {
            miniPlayer.onNext = onNext
        }
    }

    private let titleLabel = UILabel()
    private let miniPlayer = PTMusicMiniPlayerView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    public func render(_ snapshot: PTMusicPlaybackSnapshot) {
        miniPlayer.render(snapshot)
        isHidden = !snapshot.hasCurrentItem
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 18
        clipsToBounds = true
        isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Apple Music"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        miniPlayer.translatesAutoresizingMaskIntoConstraints = false
        miniPlayer.backgroundColor = .clear

        addSubview(titleLabel)
        addSubview(miniPlayer)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            miniPlayer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            miniPlayer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            miniPlayer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            miniPlayer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
}
