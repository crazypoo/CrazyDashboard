//
//  PTMusicPlayerView.swift
//  CrazyDashboard
//

import UIKit

@MainActor
public final class PTMusicPlayerView: UIView {

    public var onPlayPause: (() -> Void)?
    public var onPrevious: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onShuffle: (() -> Void)?
    public var onRepeat: (() -> Void)?
    public var onSeek: ((TimeInterval) -> Void)?

    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let albumLabel = UILabel()

    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressSlider = UISlider()

    private let shuffleButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let repeatButton = UIButton(type: .system)

    private var artworkTask: Task<Void, Never>?
    private var representedTrackID: String?
    private var currentDuration: TimeInterval = 0
    private var isUserSeeking = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    public func render(_ snapshot: PTMusicPlaybackSnapshot) {
        let track = snapshot.track

        titleLabel.text = track?.title ?? NSLocalizedString("暂无播放", comment: "")
        artistLabel.text = track?.artist
        albumLabel.text = track?.albumTitle

        currentDuration = snapshot.duration

        if !isUserSeeking {
            progressSlider.value = Float(snapshot.progress)
            currentTimeLabel.text = Self.timeString(snapshot.currentTime)
        }

        durationLabel.text = Self.timeString(snapshot.duration)

        playPauseButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playPauseButton.setImage(UIImage(systemName: "pause.fill"), for: .selected)
        playPauseButton.isSelected = snapshot.isPlaying
        playPauseButton.accessibilityLabel = snapshot.isPlaying
            ? NSLocalizedString("暂停", comment: "")
            : NSLocalizedString("播放", comment: "")

        shuffleButton.tintColor = snapshot.shuffleEnabled ? tintColor : .secondaryLabel

        let repeatSymbol: String
        switch snapshot.repeatMode {
        case .none:
            repeatSymbol = "repeat"
            repeatButton.tintColor = .secondaryLabel

        case .all:
            repeatSymbol = "repeat"
            repeatButton.tintColor = tintColor

        case .one:
            repeatSymbol = "repeat.1"
            repeatButton.tintColor = tintColor
        }

        repeatButton.setImage(UIImage(systemName: repeatSymbol), for: .normal)

        updateArtwork(track)
    }

    private func updateArtwork(_ track: PTMusicTrack?) {
        guard representedTrackID != track?.id else { return }

        representedTrackID = track?.id
        artworkTask?.cancel()
        artworkImageView.image = UIImage(systemName: "music.note")

        guard let track else { return }

        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let image = await PTMusicArtworkCache.shared.image(
                for: track.artwork,
                targetSize: CGSize(width: 600, height: 600)
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
        backgroundColor = .black

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.clipsToBounds = true
        artworkImageView.layer.cornerRadius = 18
        artworkImageView.backgroundColor = .secondarySystemBackground
        artworkImageView.image = UIImage(systemName: "music.note")

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.textColor = .white

        artistLabel.font = .preferredFont(forTextStyle: .body)
        artistLabel.adjustsFontForContentSizeCategory = true
        artistLabel.textColor = .grayCA
        artistLabel.textAlignment = .center

        albumLabel.font = .preferredFont(forTextStyle: .caption1)
        albumLabel.adjustsFontForContentSizeCategory = true
        albumLabel.textColor = .grayCA
        albumLabel.textAlignment = .center
        albumLabel.numberOfLines = 1

        let metadataStack = UIStackView(arrangedSubviews: [
            titleLabel,
            artistLabel,
            albumLabel
        ])
        metadataStack.translatesAutoresizingMaskIntoConstraints = false
        metadataStack.axis = .vertical
        metadataStack.spacing = 5

        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        currentTimeLabel.textColor = .grayCA
        currentTimeLabel.text = "0:00"

        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        durationLabel.textColor = .grayCA
        durationLabel.textAlignment = .right
        durationLabel.text = "0:00"

        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = 1
        progressSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        progressSlider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        progressSlider.addTarget(
            self,
            action: #selector(sliderTouchEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )

        let progressStack = UIStackView(arrangedSubviews: [
            currentTimeLabel,
            progressSlider,
            durationLabel
        ])
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressStack.axis = .horizontal
        progressStack.alignment = .center
        progressStack.spacing = 8

        currentTimeLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        durationLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true

        configureButton(shuffleButton, symbol: "shuffle", action: #selector(shuffleTapped))
        configureButton(previousButton, symbol: "backward.fill", action: #selector(previousTapped))
        configureButton(playPauseButton, symbol: "play.fill", action: #selector(playPauseTapped))
        configureButton(nextButton, symbol: "forward.fill", action: #selector(nextTapped))
        configureButton(repeatButton, symbol: "repeat", action: #selector(repeatTapped))

//        playPauseButton.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
//            pointSize: 34,
//            weight: .semibold
//        )

        let controlsStack = UIStackView(arrangedSubviews: [
            shuffleButton,
            previousButton,
            playPauseButton,
            nextButton,
            repeatButton
        ])
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.axis = .horizontal
        controlsStack.distribution = .equalSpacing
        controlsStack.alignment = .center

        addSubview(artworkImageView)
        addSubview(metadataStack)
        addSubview(progressStack)
        addSubview(controlsStack)

        NSLayoutConstraint.activate([
            artworkImageView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            artworkImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            artworkImageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.72),
            artworkImageView.heightAnchor.constraint(equalTo: artworkImageView.widthAnchor),
            artworkImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 360),

            metadataStack.topAnchor.constraint(equalTo: artworkImageView.bottomAnchor, constant: 20),
            metadataStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            metadataStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            progressStack.topAnchor.constraint(equalTo: metadataStack.bottomAnchor, constant: 18),
            progressStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            progressStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            controlsStack.topAnchor.constraint(equalTo: progressStack.bottomAnchor, constant: 16),
            controlsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            controlsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            playPauseButton.widthAnchor.constraint(equalToConstant: 58),
            playPauseButton.heightAnchor.constraint(equalToConstant: 58)
        ])
    }

    private func configureButton(
        _ button: UIButton,
        symbol: String,
        action: Selector
    ) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
//        button.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
//            pointSize: 22,
//            weight: .medium
//        )
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    @objc private func playPauseTapped() {
        playPauseButton.isSelected.toggle()
        onPlayPause?()
    }

    @objc private func previousTapped() {
        onPrevious?()
    }

    @objc private func nextTapped() {
        onNext?()
    }

    @objc private func shuffleTapped() {
        onShuffle?()
    }

    @objc private func repeatTapped() {
        onRepeat?()
    }

    @objc private func sliderTouchDown() {
        isUserSeeking = true
    }

    @objc private func sliderChanged() {
        let proposedTime = TimeInterval(progressSlider.value) * currentDuration
        currentTimeLabel.text = Self.timeString(proposedTime)
    }

    @objc private func sliderTouchEnded() {
        let proposedTime = TimeInterval(progressSlider.value) * currentDuration
        isUserSeeking = false
        onSeek?(proposedTime)
    }

    private static func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }

        let total = Int(seconds.rounded(.down))
        let minutes = total / 60
        let remainder = total % 60

        return String(format: "%d:%02d", minutes, remainder)
    }
}
