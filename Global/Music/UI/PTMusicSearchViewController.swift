//
//  PTMusicSearchViewController.swift
//  CrazyDashboard
//

import UIKit
import MusicKit
import PooTools

@MainActor
class PTMusicSearchViewController: PTMotoBaseViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private let searchController = UISearchController(searchResultsController: nil)

    private var songs: [Song] = []
    private var albums: [Album] = []
    private var artists: [Artist] = []
    private var playlists: [Playlist] = []

    private var searchTask: Task<Void, Never>?

//    lazy var searchBar:PTSearchBar = {
//        let view = PTSearchBar()
//        view.delegate = self
//        view.searchPlaceholder = NSLocalizedString("搜索 Apple Music", comment: "")
//        return view
//    }()
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        pt_Title = NSLocalizedString("搜索 Apple Music", comment: "")
        view.backgroundColor = .black

        setupTableView()
        setupSearchController()
        setupStatusLabel()
    }

    private var category: PTMusicBrowseCategory {
        PTMusicBrowseCategory(
            rawValue: searchController.searchBar.selectedScopeButtonIndex
        ) ?? .songs
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

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.searchBar.delegate = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString(
            "搜索 Apple Music",
            comment: ""
        )
        searchController.searchBar.scopeButtonTitles = PTMusicBrowseCategory.allCases.map(\.title)
        searchController.searchBar.selectedScopeButtonIndex = 0

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupStatusLabel() {
        statusLabel.textAlignment = .center
        statusLabel.textColor = .grayCA
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.numberOfLines = 0

        tableView.backgroundView = statusLabel
        setStatus(NSLocalizedString("输入至少 2 个字符开始搜索", comment: ""))
    }

    private func clearResults() {
        songs = []
        albums = []
        artists = []
        playlists = []
    }

    private func search(_ term: String) {
        searchTask?.cancel()

        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = self.category

        guard keyword.count >= 2 else {
            clearResults()
            tableView.reloadData()
            setStatus(NSLocalizedString("输入至少 2 个字符开始搜索", comment: ""))
            return
        }

        setStatus(NSLocalizedString("正在搜索…", comment: ""))

        searchTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()

                guard let self else { return }

                clearResults()

                switch category {
                case .songs:
                    songs = try await PTMusicCatalogService.shared.searchSongs(
                        term: keyword,
                        limit: 40
                    )

                case .albums:
                    albums = try await PTMusicCatalogService.shared.searchAlbums(
                        term: keyword,
                        limit: 40
                    )

                case .artists:
                    artists = try await PTMusicCatalogService.shared.searchArtists(
                        term: keyword,
                        limit: 40
                    )

                case .playlists:
                    playlists = try await PTMusicCatalogService.shared.searchPlaylists(
                        term: keyword,
                        limit: 40
                    )
                }

                try Task.checkCancellation()
                tableView.reloadData()

                setStatus(
                    currentResultCount == 0
                    ? NSLocalizedString("没有找到内容", comment: "")
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

extension PTMusicSearchViewController: UISearchResultsUpdating {

    public func updateSearchResults(for searchController: UISearchController) {
        search(searchController.searchBar.text ?? "")
    }
}

extension PTMusicSearchViewController: UISearchBarDelegate {

    public func searchBar(
        _ searchBar: UISearchBar,
        selectedScopeButtonIndexDidChange selectedScope: Int
    ) {
        search(searchBar.text ?? "")
    }
}

extension PTMusicSearchViewController: UITableViewDataSource, UITableViewDelegate {

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
        switch category {
        case .songs:
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
                    source: .catalog
                )
            )
            return cell

        case .albums:
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

        case .artists:
            guard
                artists.indices.contains(indexPath.row),
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                ) as? PTMusicCollectionCell
            else {
                return UITableViewCell()
            }

            let artist = artists[indexPath.row]
            cell.configure(
                id: artist.id.rawValue,
                title: artist.name,
                subtitle: NSLocalizedString("歌手", comment: ""),
                artwork: artist.artwork
            )
            return cell

        case .playlists:
            guard
                playlists.indices.contains(indexPath.row),
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                ) as? PTMusicCollectionCell
            else {
                return UITableViewCell()
            }

            let playlist = playlists[indexPath.row]
            cell.configure(
                id: playlist.id.rawValue,
                title: playlist.name,
                subtitle: playlist.curatorName,
                artwork: playlist.artwork
            )
            return cell
        }
    }

    public func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch category {
        case .songs:
            guard songs.indices.contains(indexPath.row) else { return }

            let selected = songs[indexPath.row]
            let allSongs = songs

            Task { @MainActor [weak self] in
                do {
                    try await PTMusicPlaybackManager.shared.play(
                        songs: allSongs,
                        startingAt: selected
                    )
                    self?.navigationController?.popViewController(animated: true)
                } catch {
                    self?.showError(error.localizedDescription)
                }
            }

        case .albums:
            guard albums.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .album(albums[indexPath.row], .catalog)
                ),
                animated: true
            )

        case .artists:
            guard artists.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .artist(artists[indexPath.row], .catalog)
                ),
                animated: true
            )

        case .playlists:
            guard playlists.indices.contains(indexPath.row) else { return }

            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(
                    content: .playlist(playlists[indexPath.row], .catalog)
                ),
                animated: true
            )
        }
    }

    public func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard category == .songs, songs.indices.contains(indexPath.row) else {
            return nil
        }

        let song = songs[indexPath.row]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let playNext = UIAction(
                title: NSLocalizedString("Riding Queue 下一首播放", comment: ""),
                image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")
            ) { _ in
                Task { @MainActor in
                    try? await PTMusicPlaybackManager.shared.playNextInRidingQueue(song)
                }
            }

            let addLater = UIAction(
                title: NSLocalizedString("加入 Riding Queue", comment: ""),
                image: UIImage(systemName: "text.badge.plus")
            ) { _ in
                Task { @MainActor in
                    try? await PTMusicPlaybackManager.shared.appendToRidingQueue(song)
                }
            }

            return UIMenu(children: [playNext, addLater])
        }
    }
}
