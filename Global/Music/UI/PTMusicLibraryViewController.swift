//
//  PTMusicLibraryViewController.swift
//  CrazyDashboard
//

import UIKit
import MusicKit
import PooTools

@MainActor
class PTMusicLibraryViewController: PTMotoBaseViewController {

    private enum SourceMode: Int {
        case library
        case recentlyPlayed
    }

    private let sourceControl = UISegmentedControl(
        items: [
            NSLocalizedString("资料库", comment: ""),
            NSLocalizedString("最近播放", comment: "")
        ]
    )

    private let categoryControl = UISegmentedControl(
        items: PTMusicBrowseCategory.allCases.map(\.title)
    )

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)

    private var songs: [Song] = []
    private var albums: [Album] = []
    private var artists: [Artist] = []
    private var playlists: [Playlist] = []

    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    public override func viewDidLoad() {
        super.viewDidLoad()

        pt_Title = NSLocalizedString("我的音乐", comment: "")
        view.backgroundColor = .black

        setupControls()
        setupTableView()
        setupSearchController()

        loadCurrentMode()
    }

    private var sourceMode: SourceMode {
        SourceMode(rawValue: sourceControl.selectedSegmentIndex) ?? .library
    }

    private var category: PTMusicBrowseCategory {
        PTMusicBrowseCategory(rawValue: categoryControl.selectedSegmentIndex) ?? .songs
    }

    private func setupControls() {
        sourceControl.translatesAutoresizingMaskIntoConstraints = false
        sourceControl.selectedSegmentIndex = 0
        sourceControl.addTarget(self, action: #selector(sourceChanged), for: .valueChanged)

        categoryControl.translatesAutoresizingMaskIntoConstraints = false
        categoryControl.selectedSegmentIndex = 0
        categoryControl.addTarget(self, action: #selector(categoryChanged), for: .valueChanged)

        view.addSubview(sourceControl)
        view.addSubview(categoryControl)

        NSLayoutConstraint.activate([
            sourceControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            sourceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sourceControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            categoryControl.topAnchor.constraint(equalTo: sourceControl.bottomAnchor, constant: 8),
            categoryControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            categoryControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag

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
            tableView.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("搜索资料库", comment: "")

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true
    }

    @objc private func sourceChanged() {
        searchController.searchBar.text = nil
        searchController.isActive = false

        if sourceMode == .recentlyPlayed {
            categoryControl.selectedSegmentIndex = PTMusicBrowseCategory.songs.rawValue
            categoryControl.isEnabled = false
            searchController.searchBar.isUserInteractionEnabled = false
        } else {
            categoryControl.isEnabled = true
            searchController.searchBar.isUserInteractionEnabled = true
        }

        loadCurrentMode()
    }

    @objc private func categoryChanged() {
        searchController.searchBar.text = nil
        searchController.isActive = false
        loadCurrentMode()
    }

    private func clearResults() {
        songs = []
        albums = []
        artists = []
        playlists = []
    }

    private func loadCurrentMode() {
        loadTask?.cancel()
        searchTask?.cancel()

        clearResults()
        tableView.reloadData()
        setStatus(NSLocalizedString("正在加载…", comment: ""))

        let sourceMode = self.sourceMode
        let category = self.category

        loadTask = Task { @MainActor [weak self] in
            do {
                guard let self else { return }

                if sourceMode == .recentlyPlayed {
                    songs = try await PTMusicLibraryService.shared.recentlyPlayedSongs(limit: 40)
                } else {
                    switch category {
                    case .songs:
                        songs = try await PTMusicLibraryService.shared.songs(limit: 150)
                    case .albums:
                        albums = try await PTMusicLibraryService.shared.albums(limit: 100)
                    case .artists:
                        artists = try await PTMusicLibraryService.shared.artists(limit: 100)
                    case .playlists:
                        playlists = try await PTMusicLibraryService.shared.playlists(limit: 100)
                    }
                }

                try Task.checkCancellation()
                tableView.reloadData()

                setStatus(
                    currentResultCount == 0
                    ? NSLocalizedString("暂无内容", comment: "")
                    : nil
                )

            } catch is CancellationError {
                return

            } catch {
                guard !Task.isCancelled else { return }
                self?.setStatus(error.localizedDescription)
            }
        }
    }

    private func searchLibrary(_ term: String) {
        guard sourceMode == .library else { return }

        searchTask?.cancel()

        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = self.category

        guard !keyword.isEmpty else {
            loadCurrentMode()
            return
        }

        searchTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()

                guard let self else { return }

                clearResults()

                switch category {
                case .songs:
                    songs = try await PTMusicLibraryService.shared.searchSongs(
                        term: keyword,
                        limit: 100
                    )

                case .albums:
                    albums = try await PTMusicLibraryService.shared.searchAlbums(
                        term: keyword,
                        limit: 100
                    )

                case .artists:
                    artists = try await PTMusicLibraryService.shared.searchArtists(
                        term: keyword,
                        limit: 100
                    )

                case .playlists:
                    playlists = try await PTMusicLibraryService.shared.searchPlaylists(
                        term: keyword,
                        limit: 100
                    )
                }

                try Task.checkCancellation()
                tableView.reloadData()

                setStatus(
                    currentResultCount == 0
                    ? NSLocalizedString("资料库中没有匹配内容", comment: "")
                    : nil
                )

            } catch is CancellationError {
                return

            } catch {
                guard !Task.isCancelled else { return }
                self?.setStatus(error.localizedDescription)
            }
        }
    }

    private var currentResultCount: Int {
        if sourceMode == .recentlyPlayed {
            return songs.count
        }

        switch category {
        case .songs:
            return songs.count
        case .albums:
            return albums.count
        case .artists:
            return artists.count
        case .playlists:
            return playlists.count
        }
    }

    private var itemSource: PTMusicSource {
        sourceMode == .recentlyPlayed ? .recentlyPlayed : .library
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

extension PTMusicLibraryViewController: UISearchResultsUpdating {

    public func updateSearchResults(for searchController: UISearchController) {
        searchLibrary(searchController.searchBar.text ?? "")
    }
}

extension PTMusicLibraryViewController: UITableViewDataSource, UITableViewDelegate {

    public func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        currentResultCount
    }

    public func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if sourceMode == .recentlyPlayed || category == .songs {
            guard
                songs.indices.contains(indexPath.row),
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicTrackCell.reuseIdentifier,
                    for: indexPath
                ) as? PTMusicTrackCell
            else {
                return UITableViewCell()
            }

            cell.configure(
                with: PTMusicTrack(
                    song: songs[indexPath.row],
                    source: itemSource
                )
            )
            return cell
        }

        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PTMusicCollectionCell.reuseIdentifier,
            for: indexPath
        ) as? PTMusicCollectionCell else {
            return UITableViewCell()
        }

        switch category {
        case .songs:
            return UITableViewCell()

        case .albums:
            guard albums.indices.contains(indexPath.row) else { return UITableViewCell() }
            let album = albums[indexPath.row]
            cell.configure(
                id: album.id.rawValue,
                title: album.title,
                subtitle: album.artistName,
                artwork: album.artwork
            )

        case .artists:
            guard artists.indices.contains(indexPath.row) else { return UITableViewCell() }
            let artist = artists[indexPath.row]
            cell.configure(
                id: artist.id.rawValue,
                title: artist.name,
                subtitle: NSLocalizedString("歌手", comment: ""),
                artwork: artist.artwork
            )

        case .playlists:
            guard playlists.indices.contains(indexPath.row) else { return UITableViewCell() }
            let playlist = playlists[indexPath.row]
            cell.configure(
                id: playlist.id.rawValue,
                title: playlist.name,
                subtitle: playlist.curatorName,
                artwork: playlist.artwork
            )
        }

        return cell
    }

    public func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        if sourceMode == .recentlyPlayed || category == .songs {
            guard songs.indices.contains(indexPath.row) else { return }

            let selected = songs[indexPath.row]
            let allSongs = songs

            Task { @MainActor [weak self] in
                do {
                    try await PTMusicPlaybackManager.shared.play(
                        songs: allSongs,
                        startingAt: selected
                    )
                } catch {
                    self?.showError(error.localizedDescription)
                }
            }
            return
        }

        switch category {
        case .songs:
            break

        case .albums:
            guard albums.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .album(albums[indexPath.row], .library)
                ),
                animated: true
            )

        case .artists:
            guard artists.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .artist(artists[indexPath.row], .library)
                ),
                animated: true
            )

        case .playlists:
            guard playlists.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .playlist(playlists[indexPath.row], .library)
                ),
                animated: true
            )
        }
    }
}
