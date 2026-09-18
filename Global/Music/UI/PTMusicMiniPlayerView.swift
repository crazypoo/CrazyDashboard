//
//  PTMusicMiniPlayerView.swift
//  CrazyDashboard
//

import UIKit

@MainActor
public final class PTMusicMiniPlayerView: UIView {

    public var onOpenPlayer: (() -> Void)?
    public var onPlayPause: (() -> Void)?
    public var onNext: (() -> Void)?

    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)

    private var artworkTask: Task<Void, Never>?
    private var representedTrackID: String?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    public func render(_ snapshot: PTMusicPlaybackSnapshot) {
        isHidden = false

        guard let track = snapshot.track else {
            representedTrackID = nil
            artworkTask?.cancel()
            artworkTask = nil

            artworkImageView.image = UIImage(
                systemName: "music.note"
            )

            titleLabel.text = NSLocalizedString(
                "暂无播放",
                comment: ""
            )

            artistLabel.text = NSLocalizedString(
                "打开 Apple Music 或点击进入音乐",
                comment: ""
            )

            playPauseButton.setImage(
                UIImage(systemName: "play.fill"),
                for: .normal
            )

            return
        }

        titleLabel.text = track.title
        artistLabel.text = track.artist

        playPauseButton.setImage(
            UIImage(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill"),
            for: .normal
        )

        updateArtwork(track)
    }

    private func updateArtwork(_ track: PTMusicTrack) {
        guard representedTrackID != track.id else { return }

        representedTrackID = track.id
        artworkTask?.cancel()
        artworkImageView.image = UIImage(systemName: "music.note")

        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let image = await PTMusicArtworkCache.shared.image(
                for: track.artwork,
                targetSize: CGSize(width: 64, height: 64)
            )

            guard
                !Task.isCancelled,
                representedTrackID == track.id
            else {
                return
            }

            artworkImageView.image = image ?? UIImage(systemName: "music.note")
        }
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 14
        clipsToBounds = true
        isHidden = true

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.clipsToBounds = true
        artworkImageView.layer.cornerRadius = 9
        artworkImageView.backgroundColor = .tertiarySystemBackground

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.textColor = .white

        artistLabel.font = .preferredFont(forTextStyle: .caption1)
        artistLabel.adjustsFontForContentSizeCategory = true
        artistLabel.textColor = .secondaryLabel
        artistLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 2

        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)

        addSubview(artworkImageView)
        addSubview(labels)
        addSubview(playPauseButton)
        addSubview(nextButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 72),

            artworkImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            artworkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            artworkImageView.widthAnchor.constraint(equalToConstant: 56),
            artworkImageView.heightAnchor.constraint(equalToConstant: 56),

            labels.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 10),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),

            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 44),
            nextButton.heightAnchor.constraint(equalToConstant: 44),

            playPauseButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -2),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 44),
            playPauseButton.heightAnchor.constraint(equalToConstant: 44),

            labels.trailingAnchor.constraint(lessThanOrEqualTo: playPauseButton.leadingAnchor, constant: -8)
        ])
    }

    @objc private func openTapped() {
        onOpenPlayer?()
    }

    @objc private func playPauseTapped() {
        onPlayPause?()
    }

    @objc private func nextTapped() {
        onNext?()
    }
}
