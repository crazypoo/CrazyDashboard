//
//  PTMusicCollectionCell.swift
//  CrazyDashboard
//

import UIKit
import MusicKit

@MainActor
public final class PTMusicCollectionCell: UITableViewCell {

    public static let reuseIdentifier = "PTMusicCollectionCell"

    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private var artworkTask: Task<Void, Never>?
    private var representedID: String?

    public override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        artworkTask?.cancel()
        artworkTask = nil
        representedID = nil

        artworkImageView.image = Self.placeholderImage
        titleLabel.text = nil
        subtitleLabel.text = nil
        accessoryType = .none
    }

    public func configure(
        id: String,
        title: String,
        subtitle: String?,
        artwork: Artwork?,
        showsDisclosure: Bool = true
    ) {
        representedID = id
        titleLabel.text = title
        subtitleLabel.text = subtitle
        accessoryType = showsDisclosure ? .disclosureIndicator : .none
        artworkImageView.image = Self.placeholderImage

        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let image = await PTMusicArtworkCache.shared.image(
                for: artwork,
                targetSize: CGSize(width: 58, height: 58)
            )

            guard
                !Task.isCancelled,
                representedID == id
            else {
                return
            }

            artworkImageView.image = image ?? Self.placeholderImage
        }
    }

    private func setupUI() {
        selectionStyle = .default

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.clipsToBounds = true
        artworkImageView.layer.cornerRadius = 9
        artworkImageView.backgroundColor = .secondarySystemBackground
        artworkImageView.image = Self.placeholderImage

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.spacing = 4

        contentView.addSubview(artworkImageView)
        contentView.addSubview(labels)

        NSLayoutConstraint.activate([
            artworkImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artworkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkImageView.widthAnchor.constraint(equalToConstant: 58),
            artworkImageView.heightAnchor.constraint(equalToConstant: 58),

            labels.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 76)
        ])
    }

    private static var placeholderImage: UIImage? {
        UIImage(systemName: "music.note")
    }
}
