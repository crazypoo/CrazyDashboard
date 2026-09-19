//
//  PTMusicSearchViewController.swift
//  CrazyDashboard
//
//  English: Search UI delegates all request correctness to PTMusicBrowseStore.
//  Español: La UI de búsqueda delega toda la corrección de solicitudes a PTMusicBrowseStore.
//  中文：搜索界面把请求一致性统一交给 PTMusicBrowseStore。
//

import Combine
import UIKit
import MusicKit
import PooTools

@MainActor
class PTMusicSearchViewController: PTMotoBaseViewController {

    private let store: PTMusicBrowseStore
    private var cancellables = Set<AnyCancellable>()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = PTMusicStateView()

    private lazy var searchBar: PTSearchBar = {
        let view = PTSearchBar(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        view.searchPlaceholder = NSLocalizedString("搜索 Apple Music", comment: "")
        view.searchPlaceholderFont = .systemFont(ofSize: 15)
        view.searchPlaceholderColor = .grayCA
        view.searchTextColor = .white
        view.cursorColor = .white
        view.searchBarOutViewColor = .clear
        view.searchTextFieldBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        view.searchBarTextFieldBorderColor = .clear
        view.searchBarTextFieldBorderWidth = 0
        view.searchBarTextFieldCornerRadius = 12
        view.scopeButtonTitles = PTMusicBrowseCategory.allCases.map(\.title)
        view.selectedScopeButtonIndex = 0
        view.showsScopeBar = true
        view.tintColor = .white
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.searchTextField.returnKeyType = .search
        view.searchTextField.clearButtonMode = .whileEditing
        return view
    }()

    init(store: PTMusicBrowseStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    convenience init() {
        self.init(store: PTMusicBrowseStore())
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor deinit {
        store.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pt_Title = NSLocalizedString("搜索 Apple Music", comment: "")
        view.backgroundColor = .black
        setupSearchBar()
        setupTableView()
        bindStore()
        render()
    }

    private var category: PTMusicBrowseCategory {
        PTMusicBrowseCategory(rawValue: searchBar.selectedScopeButtonIndex) ?? .songs
    }

    private var visiblePayload: PTMusicBrowsePayload? {
        guard
            let key = store.currentQueryKey,
            key.surface == .search,
            key.category == category
        else {
            return nil
        }
        return store.payload
    }

    private func setupSearchBar() {
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.register(PTMusicTrackCell.self, forCellReuseIdentifier: PTMusicTrackCell.reuseIdentifier)
        tableView.register(PTMusicCollectionCell.self, forCellReuseIdentifier: PTMusicCollectionCell.reuseIdentifier)

        stateView.onRetry = { [weak self] in
            self?.performStateAction()
        }
        tableView.backgroundView = stateView
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func bindStore() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.render()
            }
            .store(in: &cancellables)
    }

    private func render() {
        guard isViewLoaded else { return }
        tableView.reloadData()

        let message: String?
        let showsRetry: Bool
        let showsLoading: Bool
        let actionTitle: String?
        switch store.state {
        case .idle:
            message = NSLocalizedString("输入至少 2 个字符开始搜索", comment: "")
            showsRetry = false
            showsLoading = false
            actionTitle = nil
        case .loading:
            message = NSLocalizedString("正在搜索…", comment: "")
            showsRetry = false
            showsLoading = true
            actionTitle = nil
        case .content:
            message = nil
            showsRetry = false
            showsLoading = false
            actionTitle = nil
        case .empty:
            message = NSLocalizedString("没有找到内容", comment: "")
            showsRetry = false
            showsLoading = false
            actionTitle = nil
        case .failed(_, let error):
            message = error.userMessage
            showsRetry = true
            showsLoading = false
            actionTitle = stateActionTitle(for: error)
        case .timedOut:
            message = PTMusicUIError.timedOut.userMessage
            showsRetry = true
            showsLoading = false
            actionTitle = NSLocalizedString("重试", comment: "")
        }
        stateView.render(
            message: message,
            showsRetry: showsRetry,
            showsLoading: showsLoading,
            actionTitle: actionTitle
        )
    }

    private func search(_ term: String) {
        store.search(term: term, category: category)
    }

    private func performStateAction() {
        guard case .failed(_, let error) = store.state else {
            store.retryCurrentQuery()
            return
        }

        switch error {
        case .authorizationRequired:
            store.requestAuthorizationAndRetry()
        case .accessDenied:
            openMusicSettings()
        default:
            store.retryCurrentQuery()
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

extension PTMusicSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        search(searchText)
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        search(searchBar.text ?? "")
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension PTMusicSearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visiblePayload?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let payload = visiblePayload else { return UITableViewCell() }

        switch payload {
        case .songs(let values):
            guard values.indices.contains(indexPath.row),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicTrackCell.reuseIdentifier,
                    for: indexPath
                  ) as? PTMusicTrackCell else { return UITableViewCell() }
            cell.configure(with: PTMusicTrack(song: values[indexPath.row], source: .catalog))
            return cell

        case .albums(let values):
            guard values.indices.contains(indexPath.row),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                  ) as? PTMusicCollectionCell else { return UITableViewCell() }
            let value = values[indexPath.row]
            cell.configure(id: value.id.rawValue, title: value.title, subtitle: value.artistName, artwork: value.artwork)
            return cell

        case .artists(let values):
            guard values.indices.contains(indexPath.row),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                  ) as? PTMusicCollectionCell else { return UITableViewCell() }
            let value = values[indexPath.row]
            cell.configure(
                id: value.id.rawValue,
                title: value.name,
                subtitle: NSLocalizedString("歌手", comment: ""),
                artwork: value.artwork
            )
            return cell

        case .playlists(let values):
            guard values.indices.contains(indexPath.row),
                  let cell = tableView.dequeueReusableCell(
                    withIdentifier: PTMusicCollectionCell.reuseIdentifier,
                    for: indexPath
                  ) as? PTMusicCollectionCell else { return UITableViewCell() }
            let value = values[indexPath.row]
            cell.configure(id: value.id.rawValue, title: value.name, subtitle: value.curatorName, artwork: value.artwork)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let payload = visiblePayload else { return }

        switch payload {
        case .songs(let values):
            guard values.indices.contains(indexPath.row) else { return }
            let selected = values[indexPath.row]
            Task { @MainActor [weak self] in
                do {
                    try await PTMusicPlaybackManager.shared.play(songs: values, startingAt: selected)
                    self?.navigationController?.popViewController(animated: true)
                } catch {
                    self?.showError(error)
                }
            }

        case .albums(let values):
            guard values.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .album(values[indexPath.row], .catalog)),
                animated: true
            )

        case .artists(let values):
            guard values.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .artist(values[indexPath.row], .catalog)),
                animated: true
            )

        case .playlists(let values):
            guard values.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .playlist(values[indexPath.row], .catalog)),
                animated: true
            )
        }
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard
            case .songs(let values) = visiblePayload,
            values.indices.contains(indexPath.row)
        else {
            return nil
        }

        let song = values[indexPath.row]
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
