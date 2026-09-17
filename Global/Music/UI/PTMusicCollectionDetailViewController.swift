//
//  PTMusicCollectionDetailViewController.swift
//  CrazyDashboard
//

import UIKit
import MusicKit

@MainActor
public final class PTMusicCollectionDetailViewController: UIViewController {

    public enum Content {
        case album(Album, PTMusicSource)
        case playlist(Playlist, PTMusicSource)
        case artist(Artist, PTMusicSource)
    }

    private let content: Content

    private let headerArtworkImageView = UIImageView()
    private let headerTitleLabel = UILabel()
    private let headerSubtitleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()

    private var tracks: [Track] = []
    private var albums: [Album] = []
    private var loadTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?

    public init(content: Content) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        artworkTask?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        setupHeader()
        setupTableView()
        configureHeader()
        loadContent()
    }

    private var source: PTMusicSource {
        switch content {
        case .album(_, let source),
             .playlist(_, let source),
             .artist(_, let source):
            return source
        }
    }

    private func setupHeader() {
        headerArtworkImageView.translatesAutoresizingMaskIntoConstraints = false
        headerArtworkImageView.contentMode = .scaleAspectFill
        headerArtworkImageView.clipsToBounds = true
        headerArtworkImageView.layer.cornerRadius = 16
        headerArtworkImageView.backgroundColor = .secondarySystemBackground
        headerArtworkImageView.image = UIImage(systemName: "music.note")

        headerTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerTitleLabel.font = .preferredFont(forTextStyle: .title2)
        headerTitleLabel.adjustsFontForContentSizeCategory = true
        headerTitleLabel.numberOfLines = 2

        headerSubtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerSubtitleLabel.font = .preferredFont(forTextStyle: .body)
        headerSubtitleLabel.adjustsFontForContentSizeCategory = true
        headerSubtitleLabel.textColor = .secondaryLabel
        headerSubtitleLabel.numberOfLines = 2

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.configuration = .filled()
        playButton.configuration?.image = UIImage(systemName: "play.fill")
        playButton.configuration?.title = NSLocalizedString("播放", comment: "")
        playButton.configuration?.imagePadding = 8
        playButton.addTarget(self, action: #selector(playAllTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [
            headerTitleLabel,
            headerSubtitleLabel,
            playButton
        ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 7

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerArtworkImageView)
        header.addSubview(textStack)

        view.addSubview(header)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerArtworkImageView.topAnchor.constraint(equalTo: header.topAnchor, constant: 16),
            headerArtworkImageView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            headerArtworkImageView.widthAnchor.constraint(equalToConstant: 120),
            headerArtworkImageView.heightAnchor.constraint(equalToConstant: 120),
            headerArtworkImageView.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -16),

            textStack.leadingAnchor.constraint(equalTo: headerArtworkImageView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            textStack.centerYAnchor.constraint(equalTo: headerArtworkImageView.centerYAnchor)
        ])

        header.tag = 10_001
    }

    private func setupTableView() {
        guard let header = view.viewWithTag(10_001) else { return }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(
            PTMusicTrackCell.self,
            forCellReuseIdentifier: PTMusicTrackCell.reuseIdentifier
        )
        tableView.register(
            PTMusicCollectionCell.self,
            forCellReuseIdentifier: PTMusicCollectionCell.reuseIdentifier
        )

        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 0
        tableView.backgroundView = statusLabel

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureHeader() {
        let artwork: Artwork?

        switch content {
        case .album(let album, _):
            title = album.title
            headerTitleLabel.text = album.title
            headerSubtitleLabel.text = album.artistName
            artwork = album.artwork

        case .playlist(let playlist, _):
            title = playlist.name
            headerTitleLabel.text = playlist.name
            headerSubtitleLabel.text = playlist.curatorName
            artwork = playlist.artwork

        case .artist(let artist, _):
            title = artist.name
            headerTitleLabel.text = artist.name
            headerSubtitleLabel.text = NSLocalizedString("歌手", comment: "")
            artwork = artist.artwork
        }

        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let image = await PTMusicArtworkCache.shared.image(
                for: artwork,
                targetSize: CGSize(width: 240, height: 240)
            )

            guard !Task.isCancelled else { return }
            headerArtworkImageView.image = image ?? UIImage(systemName: "music.note")
        }
    }

    private func loadContent() {
        loadTask?.cancel()
        setStatus(NSLocalizedString("正在加载…", comment: ""))

        let content = self.content

        loadTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }

                switch content {
                case .album(let album, let source):
                    let detailed: Album
                    if source == .library {
                        detailed = try await PTMusicLibraryService.shared.loadAlbum(album)
                    } else {
                        detailed = try await PTMusicCatalogService.shared.loadAlbum(album)
                    }

                    tracks = Array(detailed.tracks ?? [])

                case .playlist(let playlist, let source):
                    let detailed: Playlist
                    if source == .library {
                        detailed = try await PTMusicLibraryService.shared.loadPlaylist(playlist)
                    } else {
                        detailed = try await PTMusicCatalogService.shared.loadPlaylist(playlist)
                    }

                    tracks = Array(detailed.tracks ?? [])

                case .artist(let artist, let source):
                    let detailed: Artist
                    if source == .library {
                        detailed = try await PTMusicLibraryService.shared.loadArtist(artist)
                    } else {
                        detailed = try await PTMusicCatalogService.shared.loadArtist(artist)
                    }

                    albums = Array(detailed.albums ?? [])
                }

                try Task.checkCancellation()
                tableView.reloadData()

                if tracks.isEmpty && albums.isEmpty {
                    setStatus(NSLocalizedString("暂无内容", comment: ""))
                } else {
                    setStatus(nil)
                }

                playButton.isHidden = tracks.isEmpty

            } catch is CancellationError {
                return

            } catch {
                guard !Task.isCancelled else { return }
                self?.setStatus(error.localizedDescription)
            }
        }
    }

    @objc private func playAllTapped() {
        guard let first = tracks.first else { return }

        Task { @MainActor [weak self] in
            do {
                try await PTMusicPlaybackManager.shared.play(
                    tracks: self?.tracks ?? [],
                    startingAt: first
                )
            } catch {
                self?.showError(error.localizedDescription)
            }
        }
    }

    private func setStatus(_ text: String?) {
        statusLabel.text = text
        statusLabel.isHidden = text == nil
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(
            title: NSLocalizedString("Apple Music", comment: ""),
            message: message,
            preferredStyle: .alert
        )

        alert.addAction(
            UIAlertAction(
                title: NSLocalizedString("确定", comment: ""),
                style: .default
            )
        )

        present(alert, animated: true)
    }
}

extension PTMusicCollectionDetailViewController: UITableViewDataSource, UITableViewDelegate {

    public func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        switch content {
        case .artist:
            return albums.count
        case .album, .playlist:
            return tracks.count
        }
    }

    public func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        switch content {
        case .artist:
            guard
                albums.indices.contains(indexPath.row),
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                ) as? PTMusicCollectionCell
            else {
                return UITableViewCell()
            }

            let album = albums[indexPath.row]
            cell.configure(
                id: album.id.rawValue,
                title: album.title,
                subtitle: album.artistName,
                artwork: album.artwork
            )
            return cell

        case .album, .playlist:
            guard
                tracks.indices.contains(indexPath.row),
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicTrackCell.reuseIdentifier,
                    for: indexPath
                ) as? PTMusicTrackCell
            else {
                return UITableViewCell()
            }

            cell.configure(
                with: PTMusicTrack(
                    track: tracks[indexPath.row],
                    source: source
                )
            )
            return cell
        }
    }

    public func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch content {
        case .artist:
            guard albums.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .album(albums[indexPath.row], source)
                ),
                animated: true
            )

        case .album, .playlist:
            guard tracks.indices.contains(indexPath.row) else { return }

            let selectedTrack = tracks[indexPath.row]
            let allTracks = tracks

            Task { @MainActor [weak self] in
                do {
                    try await PTMusicPlaybackManager.shared.play(
                        tracks: allTracks,
                        startingAt: selectedTrack
                    )
                } catch {
                    self?.showError(error.localizedDescription)
                }
            }
        }
    }
}
