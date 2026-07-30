//
//  PTWeatherOverlayView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 30/7/2026.
//

import UIKit

class PTWeatherOverlayView: PTDashboardBaseView {

    private var emitterLayer: CAEmitterLayer?
    
    // 确保这个视图本身也完全穿透触摸，以防万一
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.isUserInteractionEnabled = false // 禁用交互
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 停止所有天气动画
    public func stopWeather() {
        emitterLayer?.removeFromSuperlayer()
        emitterLayer = nil
    }
    
    /// 播放下雨动画
    public func showRain() {
        stopWeather()
        
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -50) // 发射源在屏幕正上方外部
        emitter.emitterSize = CGSize(width: bounds.width, height: 1) // 发射源宽度等同于屏幕宽
        emitter.emitterShape = .line // 呈线型发射
        
        let rainCell = CAEmitterCell()
        // 使用代码生成一个小小的白色长条作为雨滴
        rainCell.contents = createRainDropImage()?.cgImage
        rainCell.birthRate = 150 // 每秒产生的雨滴数量
        rainCell.lifetime = 3.0  // 存活时间 (秒)
        rainCell.velocity = 600  // 基础下落速度
        rainCell.velocityRange = 150 // 速度随机范围
        rainCell.yAcceleration = 500 // 向下的重力加速度
        rainCell.emissionLongitude = .pi // 发射方向向下
        rainCell.scale = 0.1 // 缩放比例
        rainCell.scaleRange = 0.05
        rainCell.alphaRange = 0.5 // 透明度随机变化
        
        emitter.emitterCells = [rainCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    /// 播放下雪动画
    public func showSnow() {
        stopWeather()
        
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -50)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
        emitter.emitterShape = .line
        
        let snowCell = CAEmitterCell()
        // 使用代码生成一个小圆点作为雪花
        snowCell.contents = createSnowFlakeImage()?.cgImage
        snowCell.birthRate = 60  // 雪花数量较少，显得更轻柔
        snowCell.lifetime = 10.0 // 飘落时间更长
        snowCell.velocity = 100  // 下落速度慢
        snowCell.velocityRange = 50
        snowCell.yAcceleration = 50 // 重力较小
        snowCell.emissionLongitude = .pi
        // 让雪花左右飘动
        snowCell.xAcceleration = 10
        snowCell.spinRange = .pi
        
        snowCell.scale = 0.05
        snowCell.scaleRange = 0.05
        snowCell.alphaRange = 0.5
        
        emitter.emitterCells = [snowCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    // MARK: - 辅助方法：代码生成粒子图片，省去导入图片的麻烦
    
    private func createRainDropImage() -> UIImage? {
        let size = CGSize(width: 4, height: 30)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
    private func createSnowFlakeImage() -> UIImage? {
        let size = CGSize(width: 20, height: 20)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
        context.fillEllipse(in: CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}
