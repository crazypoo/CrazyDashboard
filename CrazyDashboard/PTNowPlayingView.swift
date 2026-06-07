//
//  PTNowPlayingView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 7/6/2026.
//

import UIKit
import MediaPlayer

@objcMembers
public class PTNowPlayingView: UIView {
    
    private let artworkImageView = UIImageView()
    private let titleLabel = UILabel()
    private let artistLabel = UILabel()
    
    // 获取系统的音乐播放器
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupNotifications()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        // 记得结束监听并移除通知
        musicPlayer.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        self.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        self.layer.cornerRadius = 20
        self.clipsToBounds = true
        
        // 专辑封面
        artworkImageView.frame = CGRect(x: 20, y: 20, width: bounds.width - 40, height: bounds.width - 40)
        artworkImageView.layer.cornerRadius = 10
        artworkImageView.clipsToBounds = true
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.backgroundColor = .darkGray // 占位色
        addSubview(artworkImageView)
        
        // 歌名
        titleLabel.frame = CGRect(x: 10, y: artworkImageView.frame.maxY + 15, width: bounds.width - 20, height: 25)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.boldSystemFont(ofSize: 18)
        titleLabel.text = "暂无播放"
        addSubview(titleLabel)
        
        // 歌手
        artistLabel.frame = CGRect(x: 10, y: titleLabel.frame.maxY + 5, width: bounds.width - 20, height: 20)
        artistLabel.textColor = .lightGray
        artistLabel.textAlignment = .center
        artistLabel.font = UIFont.systemFont(ofSize: 14)
        artistLabel.text = "--"
        addSubview(artistLabel)
    }
    
    private func setupNotifications() {
        // 开启系统播放通知
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        // 监听切歌事件
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateNowPlayingInfo),
                                               name: .MPMusicPlayerControllerNowPlayingItemDidChange,
                                               object: musicPlayer)
        
        // 首次初始化时手动拉取一次
        updateNowPlayingInfo()
    }
    
    @objc private func updateNowPlayingInfo() {
        // 必须切回主线程更新 UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if let item = self.musicPlayer.nowPlayingItem {
                self.titleLabel.text = item.title ?? "未知歌曲"
                self.artistLabel.text = item.artist ?? "未知歌手"
                
                // 提取专辑封面图片 (设置一个合理的清晰度，比如 300x300)
                if let artwork = item.artwork, let image = artwork.image(at: CGSize(width: 300, height: 300)) {
                    self.artworkImageView.image = image
                } else {
                    self.artworkImageView.image = nil // 也可以放一张你默认的占位图
                }
            } else {
                self.titleLabel.text = "暂无播放"
                self.artistLabel.text = "--"
                self.artworkImageView.image = nil
            }
        }
    }
}
