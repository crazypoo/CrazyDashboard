//
//  PTMusicTrackCell.swift
//  CrazyDashboard
//

import UIKit
import MusicKit

@MainActor
public final class PTMusicTrackCell: UITableViewCell {

    public static let reuseIdentifier = "PTMusicTrackCell"

    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private var artworkTask: Task<Void, Never>?
    private var representedTrackID: String?

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
        representedTrackID = nil

        artworkImageView.image = Self.placeholderImage
        titleLabel.text = nil
        subtitleLabel.text = nil
    }

    public func configure(with track: PTMusicTrack) {
        representedTrackID = track.id

        titleLabel.text = track.title

        if let album = track.albumTitle, !album.isEmpty {
            subtitleLabel.text = "\(track.artist) · \(album)"
        } else {
            subtitleLabel.text = track.artist
        }

        artworkImageView.image = Self.placeholderImage
        artworkTask?.cancel()

        artworkTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let image = await PTMusicArtworkCache.shared.image(
                for: track.artwork,
                targetSize: CGSize(width: 56, height: 56)
            )

            guard
                !Task.isCancelled,
                representedTrackID == track.id
            else {
                return
            }

            artworkImageView.image = image ?? Self.placeholderImage
        }
    }

    private func setupUI() {
        selectionStyle = .default
        accessoryType = .disclosureIndicator

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.clipsToBounds = true
        artworkImageView.layer.cornerRadius = 8
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
        labels.spacing = 3

        contentView.addSubview(artworkImageView)
        contentView.addSubview(labels)

        NSLayoutConstraint.activate([
            artworkImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            artworkImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            artworkImageView.widthAnchor.constraint(equalToConstant: 56),
            artworkImageView.heightAnchor.constraint(equalToConstant: 56),

            labels.leadingAnchor.constraint(equalTo: artworkImageView.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    private static var placeholderImage: UIImage? {
        UIImage(systemName: "music.note")
    }
}
