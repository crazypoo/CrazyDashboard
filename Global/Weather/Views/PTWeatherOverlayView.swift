//
//  PTWeatherOverlayView.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 30/7/2026.
//

import UIKit
import WeatherKit
import PooTools

// 定义天气强度枚举，用于控制粒子的数量和速度
public enum PTWeatherIntensity {
    case light
    case normal
    case heavy
}

class PTWeatherOverlayView: PTDashboardBaseView { // 保持继承你原有的基类
    
    private var emitterLayer: CAEmitterLayer?
    
    // 确保这个视图本身完全穿透触摸
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
    
    // MARK: - 🌍 核心路由器：根据和风天气状态码自动展示特效
    /// 将和风天气的 Code 直接传给此方法即可自动匹配最佳动画
    public func updateWeatherEffect(by qweatherCode: String) {
        guard let code = Int(qweatherCode) else {
            stopWeather()
            return
        }
        
        switch code {
        // --- 1. 晴天、多云、阴天 (无需遮挡视线的粒子动画) ---
        case 100...153, 900, 901, 999:
            stopWeather()
            
        // --- 2. 下雨系列 ---
        case 305, 309, 314: // 小雨、毛毛雨
            showRain(intensity: .light)
        case 300, 301, 306, 315, 350, 351, 399: // 阵雨、中雨
            showRain(intensity: .normal)
        case 302...304, 307, 308, 310...313, 316...318: // 大雨、暴雨、雷阵雨、冻雨
            showRain(intensity: .heavy)
            
        // --- 3. 下雪系列 ---
        case 400, 408: // 小雪
            showSnow(intensity: .light)
        case 401, 409: // 中雪
            showSnow(intensity: .normal)
        case 402, 403, 410, 499: // 大雪、暴雪
            showSnow(intensity: .heavy)
            
        // --- 4. 雨夹雪系列 ---
        case 404...407, 456, 457: // 雨夹雪、阵雨夹雪
            showSleet()
            
        // --- 5. 雾、霾系列 ---
        case 500...502, 509...515: // 雾、霾、浓雾
            showFog()
            
        // --- 6. 扬沙、沙尘暴系列 ---
        case 503...508: // 浮尘、扬沙、沙尘暴
            showSandstorm()
            
        default:
            stopWeather()
        }
    }
    
    // MARK: - 🎬 物理粒子动画引擎
    
    /// 停止所有天气动画
    public func stopWeather() {
        emitterLayer?.removeFromSuperlayer()
        emitterLayer = nil
    }
    
    /// 播放下雨动画 (支持强度调整)
    private func showRain(intensity: PTWeatherIntensity) {
        stopWeather()
        
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -50)
        emitter.emitterSize = CGSize(width: bounds.width + 100, height: 1)
        emitter.emitterShape = .line
        
        let rainCell = CAEmitterCell()
        rainCell.contents = createRainDropImage()?.cgImage
        rainCell.lifetime = 3.0
        rainCell.emissionLongitude = .pi
        
        // 根据强度配置物理参数
        switch intensity {
        case .light:
            rainCell.birthRate = 40
            rainCell.velocity = 400
            rainCell.velocityRange = 100
            rainCell.yAcceleration = 300
            rainCell.scale = 0.08
        case .normal:
            rainCell.birthRate = 150
            rainCell.velocity = 600
            rainCell.velocityRange = 150
            rainCell.yAcceleration = 500
            rainCell.scale = 0.1
        case .heavy:
            rainCell.birthRate = 400
            rainCell.velocity = 800
            rainCell.velocityRange = 200
            rainCell.yAcceleration = 800
            rainCell.scale = 0.15 // 雨滴更大
            rainCell.alphaSpeed = -0.2 // 快速消失，模拟大雨砸在地上的感觉
        }
        
        rainCell.scaleRange = 0.05
        rainCell.alphaRange = 0.5
        
        emitter.emitterCells = [rainCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    /// 播放下雪动画 (支持强度调整)
    private func showSnow(intensity: PTWeatherIntensity) {
        stopWeather()
        
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -50)
        emitter.emitterSize = CGSize(width: bounds.width + 100, height: 1)
        emitter.emitterShape = .line
        
        let snowCell = CAEmitterCell()
        snowCell.contents = createSnowFlakeImage()?.cgImage
        snowCell.lifetime = 10.0
        snowCell.emissionLongitude = .pi
        snowCell.spinRange = .pi
        
        switch intensity {
        case .light:
            snowCell.birthRate = 20
            snowCell.velocity = 50
            snowCell.yAcceleration = 20
            snowCell.xAcceleration = 5 // 微风飘动
            snowCell.scale = 0.03
        case .normal:
            snowCell.birthRate = 60
            snowCell.velocity = 100
            snowCell.yAcceleration = 50
            snowCell.xAcceleration = 15
            snowCell.scale = 0.05
        case .heavy:
            snowCell.birthRate = 200
            snowCell.velocity = 200
            snowCell.yAcceleration = 100
            snowCell.xAcceleration = 30 // 暴雪伴随大风
            snowCell.scale = 0.08
        }
        
        snowCell.velocityRange = 50
        snowCell.scaleRange = 0.03
        snowCell.alphaRange = 0.5
        
        emitter.emitterCells = [snowCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    /// 播放雨夹雪动画 (双重粒子发射器)
    private func showSleet() {
        stopWeather()
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width / 2, y: -50)
        emitter.emitterSize = CGSize(width: bounds.width + 100, height: 1)
        emitter.emitterShape = .line
        
        // 提取中雨细胞
        let rainCell = CAEmitterCell()
        rainCell.contents = createRainDropImage()?.cgImage
        rainCell.birthRate = 80
        rainCell.lifetime = 3.0
        rainCell.velocity = 500
        rainCell.yAcceleration = 400
        rainCell.emissionLongitude = .pi
        rainCell.scale = 0.1
        
        // 提取中雪细胞
        let snowCell = CAEmitterCell()
        snowCell.contents = createSnowFlakeImage()?.cgImage
        snowCell.birthRate = 30
        snowCell.lifetime = 10.0
        snowCell.velocity = 100
        snowCell.yAcceleration = 50
        snowCell.emissionLongitude = .pi
        snowCell.scale = 0.05
        snowCell.spinRange = .pi
        
        emitter.emitterCells = [rainCell, snowCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    /// 播放雾霾动画 (水平慢速飘动的巨大柔光云团)
    private func showFog() {
        stopWeather()
        let emitter = CAEmitterLayer()
        // 发射源在屏幕右侧外部，向左侧缓慢飘动
        emitter.emitterPosition = CGPoint(x: bounds.width + 100, y: bounds.height / 2)
        emitter.emitterSize = CGSize(width: 1, height: bounds.height)
        emitter.emitterShape = .line
        
        let fogCell = CAEmitterCell()
        fogCell.contents = createFogImage(color: UIColor.white.withAlphaComponent(0.2))?.cgImage
        fogCell.birthRate = 1.5 // 每秒产生很少的雾团
        fogCell.lifetime = 30.0 // 存活时间极长，慢慢飘过屏幕
        fogCell.velocity = 40 // 缓慢向左移动
        fogCell.velocityRange = 10
        fogCell.emissionLongitude = .pi // 向左发射 (180度)
        fogCell.scale = 3.0 // 将图片放大 3 倍，显得极其庞大
        fogCell.scaleRange = 1.0
        fogCell.alphaSpeed = -0.01 // 缓慢淡出
        
        emitter.emitterCells = [fogCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    /// 播放扬沙/沙尘暴动画
    private func showSandstorm() {
        stopWeather()
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: bounds.width + 100, y: bounds.height / 2)
        emitter.emitterSize = CGSize(width: 1, height: bounds.height)
        emitter.emitterShape = .line
        
        let sandCell = CAEmitterCell()
        // 使用暗黄色调模拟沙尘
        let sandColor = UIColor(red: 0.7, green: 0.6, blue: 0.4, alpha: 0.3)
        sandCell.contents = createFogImage(color: sandColor)?.cgImage
        sandCell.birthRate = 3.0 // 沙尘比雾气更密集
        sandCell.lifetime = 20.0
        sandCell.velocity = 150 // 沙尘暴风速很快
        sandCell.velocityRange = 50
        sandCell.emissionLongitude = .pi // 向左吹
        sandCell.scale = 2.0
        sandCell.scaleRange = 1.0
        
        emitter.emitterCells = [sandCell]
        layer.addSublayer(emitter)
        self.emitterLayer = emitter
    }
    
    // MARK: - 🎨 辅助方法：代码生成粒子图片，彻底免除导入图片的麻烦
    
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
    
    /// 创建雾气/沙尘团块 (一个边缘极度模糊的巨大圆形)
    private func createFogImage(color: UIColor) -> UIImage? {
        let size = CGSize(width: 150, height: 150)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        // 绘制多层同心圆，逐渐降低透明度，模拟云雾的高斯模糊边缘
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = size.width / 2
        let step: CGFloat = 5.0
        
        for radius in stride(from: maxRadius, to: 0, by: -step) {
            let alpha = (maxRadius - radius) / maxRadius
            context.setFillColor(color.withAlphaComponent(alpha * 0.5).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

extension PTWeatherOverlayView {
    
    // MARK: - 🍎 核心路由器：根据 Apple WeatherKit 状态自动展示特效
    /// 将苹果官方的 WeatherCondition 传给此方法即可自动匹配最佳动画
    public func updateWeatherEffect(for condition: WeatherCondition) {
        
        switch condition {
        // --- 1. 晴天、多云 (关闭特效) ---
        case .clear, .mostlyClear, .cloudy, .mostlyCloudy, .breezy, .windy:
            stopWeather()
            
        // --- 2. 下雨系列 ---
        case .drizzle, .sunShowers:
            showRain(intensity: .light)
        case .rain, .isolatedThunderstorms:
            showRain(intensity: .normal)
        case .heavyRain, .thunderstorms, .scatteredThunderstorms:
            showRain(intensity: .heavy)
            
        // --- 3. 下雪系列 ---
        case .flurries, .sunFlurries: // 零星小雪
            showSnow(intensity: .light)
        case .snow:
            showSnow(intensity: .normal)
        case .heavySnow, .blizzard: // 大雪、暴风雪
            showSnow(intensity: .heavy)
            
        // --- 4. 混合冰雪系列 ---
        case .freezingDrizzle, .freezingRain, .sleet, .wintryMix:
            // 冰雨、冻雨、雨雪混合，直接调用我们炫酷的双重粒子引擎
            showSleet()
            
        // --- 5. 雾、霾系列 ---
        case .foggy, .haze, .smoky:
            showFog()
        // --- 6. 沙尘系列 ---
        case .blowingDust: // 风沙
            showSandstorm()
            
        default:
            stopWeather()
        }
    }
    
    public func updateWeatherEffect(byAppleDescription description: String) {
        // 统一转换为小写，方便英文匹配
        let lowerDesc = description.lowercased()
        
        PTNSLogConsole("🎬 [天气动画引擎] 正在通过缓存记录恢复动画: \(description)")
        
        // 1. 冰雨、雨夹雪 (优先级最高，因为它同时包含雨和雪的字眼)
        if lowerDesc.contains("sleet") || lowerDesc.contains("freezing") || lowerDesc.contains("wintry") || lowerDesc.contains("冰") || lowerDesc.contains("冻") || lowerDesc.contains("雨夹雪") {
            showSleet()
        }
        // 2. 下雪系列
        else if lowerDesc.contains("snow") || lowerDesc.contains("flurries") || lowerDesc.contains("blizzard") || lowerDesc.contains("雪") {
            if lowerDesc.contains("heavy") || lowerDesc.contains("blizzard") || lowerDesc.contains("暴") || lowerDesc.contains("大") {
                showSnow(intensity: .heavy)
            } else if lowerDesc.contains("flurries") || lowerDesc.contains("小") || lowerDesc.contains("零星") {
                showSnow(intensity: .light)
            } else {
                showSnow(intensity: .normal)
            }
        }
        // 3. 下雨系列
        else if lowerDesc.contains("rain") || lowerDesc.contains("drizzle") || lowerDesc.contains("shower") || lowerDesc.contains("thunder") || lowerDesc.contains("雨") || lowerDesc.contains("雷") {
            if lowerDesc.contains("heavy") || lowerDesc.contains("thunder") || lowerDesc.contains("storm") || lowerDesc.contains("暴") || lowerDesc.contains("大") || lowerDesc.contains("雷") {
                showRain(intensity: .heavy)
            } else if lowerDesc.contains("drizzle") || lowerDesc.contains("小") || lowerDesc.contains("毛") {
                showRain(intensity: .light)
            } else {
                showRain(intensity: .normal)
            }
        }
        // 4. 雾霾系列
        else if lowerDesc.contains("fog") || lowerDesc.contains("haze") || lowerDesc.contains("smoky") || lowerDesc.contains("雾") || lowerDesc.contains("霾") {
            showFog()
        }
        // 5. 沙尘系列
        else if lowerDesc.contains("dust") || lowerDesc.contains("sand") || lowerDesc.contains("沙") || lowerDesc.contains("尘") {
            showSandstorm()
        }
        // 6. 晴天、多云及其他 (清空动画)
        else {
            stopWeather()
        }
    }
}
