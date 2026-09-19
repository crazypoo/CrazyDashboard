//
//  PTMusicLibraryViewController.swift
//  CrazyDashboard
//
//  English: UIKit rendering for the library; request lifecycle lives in the store.
//  Español: UIKit solo renderiza la biblioteca; el ciclo de solicitudes vive en el store.
//  中文：控制器只负责 UIKit 渲染，请求生命周期统一交给 Store。
//

import Combine
import UIKit
import MusicKit
import PooTools

@MainActor
class PTMusicLibraryViewController: PTMotoBaseViewController {

    private enum SourceMode: Int {
        case library
        case recentlyPlayed
    }

    private let store: PTMusicBrowseStore
    private var cancellables = Set<AnyCancellable>()

    private let sourceControl = UISegmentedControl(
        items: [
            NSLocalizedString("资料库", comment: ""),
            NSLocalizedString("最近播放", comment: "")
        ]
    )

    private let categoryControl = UISegmentedControl(
        items: PTMusicBrowseCategory.allCases.map(\.title)
    )

    private lazy var searchBar: PTSearchBar = {
        let view = PTSearchBar(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        view.searchPlaceholder = NSLocalizedString("搜索资料库", comment: "")
        view.searchPlaceholderFont = .systemFont(ofSize: 15)
        view.searchPlaceholderColor = .grayCA
        view.searchTextColor = .white
        view.cursorColor = .white
        view.searchBarOutViewColor = .clear
        view.searchTextFieldBackgroundColor = UIColor.white.withAlphaComponent(0.12)
        view.searchBarTextFieldBorderColor = .clear
        view.searchBarTextFieldBorderWidth = 0
        view.searchBarTextFieldCornerRadius = 12
        view.tintColor = .white
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.searchTextField.returnKeyType = .search
        view.searchTextField.clearButtonMode = .whileEditing
        return view
    }()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = PTMusicStateView()

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

        pt_Title = NSLocalizedString("我的音乐", comment: "")
        view.backgroundColor = .black
        setupControls()
        setupSearchBar()
        setupTableView()
        bindStore()
        updateSourceAvailability()
        loadCurrentMode()
    }

    private var sourceMode: SourceMode {
        SourceMode(rawValue: sourceControl.selectedSegmentIndex) ?? .library
    }

    private var category: PTMusicBrowseCategory {
        PTMusicBrowseCategory(rawValue: categoryControl.selectedSegmentIndex) ?? .songs
    }

    private var itemSource: PTMusicSource {
        sourceMode == .recentlyPlayed ? .recentlyPlayed : .library
    }

    private var visiblePayload: PTMusicBrowsePayload? {
        guard
            let key = store.currentQueryKey,
            key.surface == .library,
            key.source == itemSource,
            key.category == category
        else {
            return nil
        }
        return store.payload
    }

    private var currentResultCount: Int {
        visiblePayload?.count ?? 0
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

    private func setupSearchBar() {
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: categoryControl.bottomAnchor, constant: 8),
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
            message = nil
            showsRetry = false
            showsLoading = false
            actionTitle = nil
        case .loading:
            message = NSLocalizedString("正在加载…", comment: "")
            showsRetry = false
            showsLoading = true
            actionTitle = nil
        case .content:
            message = nil
            showsRetry = false
            showsLoading = false
            actionTitle = nil
        case .empty:
            message = sourceMode == .recentlyPlayed
                ? NSLocalizedString("暂无最近播放内容", comment: "")
                : NSLocalizedString("暂无内容", comment: "")
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

    private func updateSourceAvailability() {
        let isRecent = sourceMode == .recentlyPlayed
        categoryControl.isEnabled = !isRecent
        searchBar.isUserInteractionEnabled = !isRecent
        searchBar.alpha = isRecent ? 0.45 : 1
        if isRecent {
            categoryControl.selectedSegmentIndex = PTMusicBrowseCategory.songs.rawValue
        }
    }

    private func loadCurrentMode() {
        updateSourceAvailability()
        store.selectLibrary(source: itemSource, category: category)
    }

    private func searchLibrary(_ term: String) {
        guard sourceMode == .library else { return }
        let keyword = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            store.selectLibrary(source: .library, category: category)
        } else {
            store.search(term: keyword, category: category)
        }
    }

    @objc private func sourceChanged() {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        loadCurrentMode()
    }

    @objc private func categoryChanged() {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        loadCurrentMode()
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

extension PTMusicLibraryViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchLibrary(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension PTMusicLibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        currentResultCount
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
            cell.configure(with: PTMusicTrack(song: values[indexPath.row], source: itemSource))
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
                } catch {
                    self?.showError(error)
                }
            }

        case .albums(let values):
            guard values.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .album(values[indexPath.row], .library)),
                animated: true
            )

        case .artists(let values):
            guard values.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .artist(values[indexPath.row], .library)),
                animated: true
            )

        case .playlists(let values):
            guard values.indices.contains(indexPath.row) else { return }
            navigationController?.pushViewController(
                PTMusicCollectionDetailViewController(content: .playlist(values[indexPath.row], .library)),
                animated: true
            )
        }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.contentSize.height > 0 else { return }
        let threshold = scrollView.contentSize.height - scrollView.bounds.height * 1.5
        if scrollView.contentOffset.y > threshold {
            store.loadNextPage()
        }
    }
}
