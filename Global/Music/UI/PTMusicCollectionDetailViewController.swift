//
//  PTMusicCollectionDetailViewController.swift
//  CrazyDashboard
//
//  English: Detail loading uses the same generation, timeout and error rules as browsing.
//  Español: La carga de detalles usa las mismas reglas de generación, tiempo límite y errores.
//  中文：详情页复用浏览页的 generation、超时和错误处理规则。
//

import UIKit
import MusicKit
import PooTools

@MainActor
class PTMusicCollectionDetailViewController: PTMotoBaseViewController {

    public enum Content {
        case album(Album, PTMusicSource)
        case playlist(Playlist, PTMusicSource)
        case artist(Artist, PTMusicSource)
    }

    private let content: Content
    private let libraryService: any PTMusicCollectionServing
    private let catalogService: any PTMusicCollectionServing
    private let authorization: any PTMusicAuthorizationProviding

    private let headerArtworkImageView = UIImageView()
    private let headerTitleLabel = UILabel()
    private let headerSubtitleLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = PTMusicStateView()

    private var tracks: [Track] = []
    private var albums: [Album] = []
    private var loadTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var requestID: UUID?
    private var state: PTMusicLoadState = .idle

    public init(
        content: Content,
        libraryService: any PTMusicCollectionServing,
        catalogService: any PTMusicCollectionServing,
        authorization: any PTMusicAuthorizationProviding
    ) {
        self.content = content
        self.libraryService = libraryService
        self.catalogService = catalogService
        self.authorization = authorization
        super.init(nibName: nil, bundle: nil)
    }

    public convenience init(content: Content) {
        self.init(
            content: content,
            libraryService: PTMusicLibraryService.shared,
            catalogService: PTMusicCatalogService.shared,
            authorization: PTMusicAuthorizationManager.shared
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor deinit {
        loadTask?.cancel()
        timeoutTask?.cancel()
        artworkTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
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

    private var queryKey: PTMusicQueryKey {
        let identity: String
        let category: PTMusicBrowseCategory
        switch content {
        case .album(let album, _):
            identity = album.id.rawValue
            category = .albums
        case .playlist(let playlist, _):
            identity = playlist.id.rawValue
            category = .playlists
        case .artist(let artist, _):
            identity = artist.id.rawValue
            category = .artists
        }
        return PTMusicQueryKey(
            surface: .collectionDetail,
            source: source,
            category: category,
            keyword: identity
        )
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
        playButton.isHidden = true

        let textStack = UIStackView(arrangedSubviews: [headerTitleLabel, headerSubtitleLabel, playButton])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 7

        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerArtworkImageView)
        header.addSubview(textStack)
        header.tag = 10_001
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
    }

    private func setupTableView() {
        guard let header = view.viewWithTag(10_001) else { return }

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(PTMusicTrackCell.self, forCellReuseIdentifier: PTMusicTrackCell.reuseIdentifier)
        tableView.register(PTMusicCollectionCell.self, forCellReuseIdentifier: PTMusicCollectionCell.reuseIdentifier)

        stateView.onRetry = { [weak self] in
            self?.performStateAction()
        }
        tableView.backgroundView = stateView
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
            let image = await PTMusicArtworkCache.shared.image(
                for: artwork,
                targetSize: CGSize(width: 240, height: 240)
            )
            guard let self, !Task.isCancelled else { return }
            headerArtworkImageView.image = image ?? UIImage(systemName: "music.note")
        }
    }

    private func loadContent() {
        loadTask?.cancel()
        timeoutTask?.cancel()
        generation &+= 1
        let localGeneration = generation
        let localRequestID = UUID()
        requestID = localRequestID
        state = .loading(queryKey)
        render()

        let content = self.content
        let source = self.source
        let authorization = self.authorization
        let libraryService = self.libraryService
        let catalogService = self.catalogService

        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }
            guard let self,
                  self.isCurrent(localGeneration, localRequestID) else { return }
            self.loadTask?.cancel()
            self.loadTask = nil
            self.timeoutTask = nil
            self.generation &+= 1
            self.requestID = nil
            self.state = .timedOut(self.queryKey)
            self.render()
        }

        loadTask = Task { @MainActor [weak self] in
            do {
                authorization.refreshAuthorizationStatus()
                switch PTMusicAuthorizationCapability(status: authorization.authorizationStatus) {
                case .notDetermined:
                    throw PTMusicUIError.authorizationRequired
                case .denied:
                    throw PTMusicUIError.accessDenied
                case .restricted:
                    throw PTMusicUIError.accessRestricted
                case .authorized:
                    break
                }
                if source == .library {
                    await authorization.refreshSubscription()
                    guard authorization.hasCloudLibraryEnabled else {
                        throw PTMusicUIError.libraryUnavailable
                    }
                }

                var loadedTracks: [Track] = []
                var loadedAlbums: [Album] = []
                switch content {
                case .album(let album, _):
                    let detailed = source == .library
                        ? try await libraryService.loadAlbum(album)
                        : try await catalogService.loadAlbum(album)
                    loadedTracks = Array(detailed.tracks ?? [])
                case .playlist(let playlist, _):
                    let detailed = source == .library
                        ? try await libraryService.loadPlaylist(playlist)
                        : try await catalogService.loadPlaylist(playlist)
                    loadedTracks = Array(detailed.tracks ?? [])
                case .artist(let artist, _):
                    let detailed = source == .library
                        ? try await libraryService.loadArtist(artist)
                        : try await catalogService.loadArtist(artist)
                    loadedAlbums = Array(detailed.albums ?? [])
                }

                try Task.checkCancellation()
                guard let self,
                      self.isCurrent(localGeneration, localRequestID) else { return }

                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.loadTask = nil
                self.requestID = nil
                self.tracks = loadedTracks
                self.albums = loadedAlbums
                self.state = loadedTracks.isEmpty && loadedAlbums.isEmpty
                    ? .empty(self.queryKey)
                    : .content(self.queryKey)
                self.render()
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrent(localGeneration, localRequestID) else { return }
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.loadTask = nil
                self.requestID = nil
                self.state = .failed(self.queryKey, PTMusicUIError.map(error))
                self.render()
            }
        }
    }

    private func render() {
        guard isViewLoaded else { return }
        tableView.reloadData()
        switch state {
        case .idle:
            stateView.render(message: nil, showsRetry: false, showsLoading: false)
            playButton.isHidden = true
        case .loading:
            stateView.render(
                message: NSLocalizedString("正在加载…", comment: ""),
                showsRetry: false,
                showsLoading: true
            )
            playButton.isHidden = true
        case .content:
            stateView.render(message: nil, showsRetry: false, showsLoading: false)
            playButton.isHidden = tracks.isEmpty
        case .empty:
            stateView.render(
                message: NSLocalizedString("暂无内容", comment: ""),
                showsRetry: false,
                showsLoading: false
            )
            playButton.isHidden = true
        case .failed(_, let error):
            stateView.render(
                message: error.userMessage,
                showsRetry: true,
                showsLoading: false,
                actionTitle: stateActionTitle(for: error)
            )
            playButton.isHidden = true
        case .timedOut:
            stateView.render(
                message: PTMusicUIError.timedOut.userMessage,
                showsRetry: true,
                showsLoading: false
            )
            playButton.isHidden = true
        }
    }

    private func isCurrent(_ generation: UInt64, _ requestID: UUID) -> Bool {
        self.generation == generation && self.requestID == requestID
    }

    private func performStateAction() {
        guard case .failed(_, let error) = state else {
            loadContent()
            return
        }

        switch error {
        case .authorizationRequired:
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await authorization.requestAuthorization()
                loadContent()
            }
        case .accessDenied:
            openMusicSettings()
        default:
            loadContent()
        }
    }

    private func stateActionTitle(for error: PTMusicUIError) -> String {
        switch error {
        case .authorizationRequired:
            return NSLocalizedString("允许访问", comment: "")
        case .accessDenied:
            return NSLocalizedString("打开设置", comment: "")
        default:
            return NSLocalizedString("重试", comment: "")
        }
    }

    private func openMusicSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func playAllTapped() {
        guard let first = tracks.first else { return }
        let allTracks = tracks
        Task { @MainActor [weak self] in
            do {
                try await PTMusicPlaybackManager.shared.play(tracks: allTracks, startingAt: first)
            } catch {
                self?.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        let uiError = PTMusicUIError.map(error)
        let alert = UIAlertController(
            title: NSLocalizedString("Apple Music", comment: ""),
            message: uiError.userMessage,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("确定", comment: ""), style: .default))
        present(alert, animated: true)
    }
}

extension PTMusicCollectionDetailViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch content {
        case .artist:
            return albums.count
        case .album, .playlist:
            return tracks.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch content {
        case .artist:
            guard albums.indices.contains(indexPath.row),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                  ) as? PTMusicCollectionCell else { return UITableViewCell() }
            let album = albums[indexPath.row]
            cell.configure(id: album.id.rawValue, title: album.title, subtitle: album.artistName, artwork: album.artwork)
            return cell

        case .album, .playlist:
            guard tracks.indices.contains(indexPath.row),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicTrackCell.reuseIdentifier,
                    for: indexPath
                  ) as? PTMusicTrackCell else { return UITableViewCell() }
            cell.configure(with: PTMusicTrack(track: tracks[indexPath.row], source: source))
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch content {
        case .artist:
            guard albums.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .album(albums[indexPath.row], source)),
                animated: true
            )
        case .album, .playlist:
            guard tracks.indices.contains(indexPath.row) else { return }
            let selectedTrack = tracks[indexPath.row]
            let allTracks = tracks
            Task { @MainActor [weak self] in
                do {
                    try await PTMusicPlaybackManager.shared.play(tracks: allTracks, startingAt: selectedTrack)
                } catch {
                    self?.showError(error)
                }
            }
        }
    }
}
