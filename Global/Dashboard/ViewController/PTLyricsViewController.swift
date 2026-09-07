//
//  PTLyricsViewController.swift
//  CrazyDashboard
//
//  EN: Presents read-only lyrics and automatically leaves the page when riding starts.
//  ES: Presenta letras de solo lectura y abandona la página cuando comienza la marcha.
//  中文：展示只读歌词，并在开始骑行时自动离开页面。
//

import UIKit
import MediaPlayer
import SnapKit
import PooTools

@MainActor
final class PTLyricsViewController: PTMotoBaseViewController {
    private let snapshot: PTNowPlayingTrackSnapshot
    private let document: PTLyricsDocument
    private let artwork: UIImage?
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer

    private let artworkImageView = UIImageView()
    private let scrollView = UIScrollView()
    private let lyricsStack = UIStackView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    private let sourceLabel = UILabel()
    private var lyricLabels: [UILabel] = []
    private var playbackTimer: Timer?
    private var activeLineIndex = -1

    var isFullLyricsAllowed: (() -> Bool)?

    init(snapshot: PTNowPlayingTrackSnapshot, document: PTLyricsDocument, artwork: UIImage?) {
        self.snapshot = snapshot
        self.document = document
        self.artwork = artwork
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateLyrics()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemDidChange),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: musicPlayer
        )
        musicPlayer.beginGeneratingPlaybackNotifications()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isFullLyricsAllowed?() ?? false else {
            dismiss(animated: true)
            return
        }
        startPlaybackTimer()
        updateActiveLine()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPlaybackTimer()
    }

    private func setupUI() {
        view.backgroundColor = .black

        artworkImageView.image = artwork
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.clipsToBounds = true
        artworkImageView.alpha = 0.18

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        blurView.isUserInteractionEnabled = false

        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        overlayView.isUserInteractionEnabled = false

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = PTDashboardConfig.languageFunc(text: "button_cancel")
        closeButton.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        }, for: .touchUpInside)

        titleLabel.text = snapshot.title
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        artistLabel.text = snapshot.artist
        artistLabel.textColor = .lightGray
        artistLabel.font = .systemFont(ofSize: 15, weight: .medium)
        artistLabel.textAlignment = .center
        artistLabel.numberOfLines = 1

        sourceLabel.text = document.source == .lrclib
            ? PTDashboardConfig.languageFunc(text: "lyrics_source_lrclib")
            : PTDashboardConfig.languageFunc(text: "lyrics_source_embedded")
        sourceLabel.textColor = UIColor.white.withAlphaComponent(0.5)
        sourceLabel.font = .systemFont(ofSize: 11, weight: .regular)
        sourceLabel.textAlignment = .center

        lyricsStack.axis = .vertical
        lyricsStack.alignment = .fill
        lyricsStack.spacing = 14
        lyricsStack.layoutMargins = UIEdgeInsets(top: 18, left: 20, bottom: 36, right: 20)
        lyricsStack.isLayoutMarginsRelativeArrangement = true

        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false

        view.addSubview(artworkImageView)
        view.addSubview(blurView)
        view.addSubview(overlayView)
        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(artistLabel)
        view.addSubview(sourceLabel)
        view.addSubview(scrollView)
        scrollView.addSubview(lyricsStack)

        artworkImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.trailing.equalToSuperview().inset(18)
            make.size.equalTo(36)
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(18)
            make.leading.trailing.equalToSuperview().inset(58)
        }
        artistLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(36)
        }
        sourceLabel.snp.makeConstraints { make in
            make.top.equalTo(artistLabel.snp.bottom).offset(3)
            make.leading.trailing.equalToSuperview().inset(36)
        }
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(sourceLabel.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
        lyricsStack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
    }

    private func populateLyrics() {
        if document.isInstrumental {
            let label = makeLyricLabel(text: PTDashboardConfig.languageFunc(text: "lyrics_instrumental"))
            label.textColor = PTDashboardConfig.shared.appMainColor
            lyricsStack.addArrangedSubview(label)
            lyricLabels = [label]
            return
        }

        lyricLabels = document.lines.map { line in
            makeLyricLabel(text: line.text)
        }
        for label in lyricLabels {
            lyricsStack.addArrangedSubview(label)
        }
    }

    private func makeLyricLabel(text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor.white.withAlphaComponent(0.72)
        label.font = .systemFont(ofSize: 18, weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = true
        return label
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        let timer = Timer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(playbackTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        playbackTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // EN: UIKit invokes the timer callback on the main run loop, preserving view isolation.
    // ES: UIKit invoca el temporizador en el bucle principal y conserva el aislamiento de la vista.
    // 中文：UIKit 会在主运行循环中调用定时器，保持页面状态的主线程隔离。
    @objc private func playbackTimerFired(_ timer: Timer) {
        guard isFullLyricsAllowed?() ?? false else {
            dismiss(animated: true)
            return
        }
        updateActiveLine()
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updateActiveLine() {
        guard document.isSynced, !document.lines.isEmpty else { return }

        let currentTime = max(0, musicPlayer.currentPlaybackTime)
        let newIndex = document.lines.lastIndex {
            guard let startTime = $0.startTime else { return false }
            return startTime <= currentTime
        } ?? -1
        guard newIndex != activeLineIndex else { return }
        activeLineIndex = newIndex

        UIView.performWithoutAnimation {
            for (index, label) in lyricLabels.enumerated() {
                let isActive = index == newIndex
                label.textColor = isActive ? PTDashboardConfig.shared.appMainColor : UIColor.white.withAlphaComponent(0.62)
                label.font = .systemFont(ofSize: isActive ? 21 : 18, weight: isActive ? .bold : .regular)
                label.alpha = isActive ? 1 : 0.82
            }
        }

        guard newIndex >= 0, newIndex < lyricLabels.count else { return }
        let label = lyricLabels[newIndex]
        let rect = label.convert(label.bounds, to: scrollView)
        let targetY = max(0, rect.midY - scrollView.bounds.height / 2)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: min(targetY, maxY)), animated: true)
    }

    @objc private func nowPlayingItemDidChange() {
        // EN: A full lyric page must never remain attached to a song that is no longer playing.
        // ES: La página completa nunca debe permanecer vinculada a una canción que ya no se reproduce.
        // 中文：完整歌词页不能继续显示已经切换掉的歌曲。
        dismiss(animated: true)
    }
}
