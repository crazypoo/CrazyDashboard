//
//  PTAnnouncementDetailViewController.swift
//  CrazyDashboard
//

import UIKit
import PooTools
import SnapKit

@MainActor
final class PTAnnouncementDetailViewController: PTMotoBaseViewController {
    private let announcement: PTAnnouncement

    init(announcement: PTAnnouncement) {
        self.announcement = announcement
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let language = PTDashboardConfig.selectedLanguageIdentifier
        pt_Title = announcement.localizedTitle(languageIdentifier: language)

        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.font = .systemFont(ofSize: 16)
        textView.text = announcement.localizedBody(languageIdentifier: language)
        view.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + 12)
            make.left.right.equalToSuperview().inset(16)
            make.bottom.equalToSuperview()
        }
    }
}
