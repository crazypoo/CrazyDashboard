//
//  PTWidgetSharedStatus.swift
//  CrazyDashboard
//
//  EN: Shared read-only vehicle status used by the iOS app, Widget extension and Watch app.
//  ES: Estado compartido de solo lectura usado por la app iOS, el Widget y la app Watch.
//  中文：iOS App、Widget 扩展和 Watch App 共用的只读车辆状态。
//  EN: Keep the keys stable because older installed versions already use them in App Group defaults.
//  ES: Mantén estables las claves porque las versiones instaladas anteriores ya las usan en App Group.
//  中文：必须保持键名稳定，因为已安装的旧版本已经在 App Group 默认值中使用它们。
//

import Foundation

public enum PTWidgetDataKeys {
    // EN: Keep the App Group identifier beside the shared keys used by every status consumer.
    // ES: Conserva el identificador del App Group junto a las claves compartidas de todos los consumidores.
    // 中文：将所有状态消费者共用的 App Group 标识与共享键集中维护。
    nonisolated public static let appGroupID = "group.com.yd.PTSpeed.xp400"
    nonisolated public static let fuelLevel = "widget_fuelLevel"
    nonisolated public static let tripKm = "widget_tripKm"
    nonisolated public static let isConnected = "widget_isConnected"
    nonisolated public static let parkedLat = "widget_parkedLat"
    nonisolated public static let parkedLon = "widget_parkedLon"
    nonisolated public static let address = "widget_parkedAddress"
    nonisolated public static let lastUpdateTime = "widget_lastUpdateTime"
    nonisolated public static let languageIdentifier = "widget_languageIdentifier"
}

public struct PTWidgetSharedStatus: Codable, Equatable, Sendable {
    public let fuelLevel: Int
    public let tripKm: Double
    public let isConnected: Bool
    public let parkedLat: Double
    public let parkedLon: Double
    public let address: String
    public let lastUpdateTime: Date
    /// EN: Optional for backward compatibility with snapshots written before app-language sync.
    /// ES: Opcional para mantener la compatibilidad con instantáneas anteriores a la sincronización del idioma.
    /// 中文：为兼容语言同步之前写入的快照，该字段必须允许缺失。
    public let languageIdentifier: String?

    nonisolated public init(
        fuelLevel: Int,
        tripKm: Double,
        isConnected: Bool,
        parkedLat: Double,
        parkedLon: Double,
        address: String,
        lastUpdateTime: Date,
        languageIdentifier: String? = nil
    ) {
        self.fuelLevel = fuelLevel
        self.tripKm = tripKm
        self.isConnected = isConnected
        self.parkedLat = parkedLat
        self.parkedLon = parkedLon
        self.address = address
        self.lastUpdateTime = lastUpdateTime
        self.languageIdentifier = languageIdentifier
    }

    nonisolated public static let placeholder = PTWidgetSharedStatus(
        fuelLevel: 0,
        tripKm: 0,
        isConnected: false,
        parkedLat: 0,
        parkedLon: 0,
        address: "",
        lastUpdateTime: .distantPast,
        languageIdentifier: nil
    )

    nonisolated public init?(applicationContext: [String: Any]) {
        guard
            let fuelLevel = Self.intValue(applicationContext[PTWidgetDataKeys.fuelLevel]),
            let tripKm = Self.doubleValue(applicationContext[PTWidgetDataKeys.tripKm]),
            let isConnected = Self.boolValue(applicationContext[PTWidgetDataKeys.isConnected]),
            let parkedLat = Self.doubleValue(applicationContext[PTWidgetDataKeys.parkedLat]),
            let parkedLon = Self.doubleValue(applicationContext[PTWidgetDataKeys.parkedLon]),
            let address = applicationContext[PTWidgetDataKeys.address] as? String,
            let timestamp = Self.doubleValue(applicationContext[PTWidgetDataKeys.lastUpdateTime])
        else {
            return nil
        }

        self.init(
            fuelLevel: fuelLevel,
            tripKm: tripKm,
            isConnected: isConnected,
            parkedLat: parkedLat,
            parkedLon: parkedLon,
            address: address,
            lastUpdateTime: Date(timeIntervalSince1970: timestamp),
            languageIdentifier: applicationContext[PTWidgetDataKeys.languageIdentifier] as? String
        )
    }

    nonisolated public init?(defaults: UserDefaults?) {
        guard let defaults,
              defaults.object(forKey: PTWidgetDataKeys.lastUpdateTime) != nil else {
            return nil
        }

        self.init(
            fuelLevel: defaults.integer(forKey: PTWidgetDataKeys.fuelLevel),
            tripKm: defaults.double(forKey: PTWidgetDataKeys.tripKm),
            isConnected: defaults.bool(forKey: PTWidgetDataKeys.isConnected),
            parkedLat: defaults.double(forKey: PTWidgetDataKeys.parkedLat),
            parkedLon: defaults.double(forKey: PTWidgetDataKeys.parkedLon),
            address: defaults.string(forKey: PTWidgetDataKeys.address) ?? PTWidgetSharedStatus.placeholder.address,
            lastUpdateTime: Date(timeIntervalSince1970: defaults.double(forKey: PTWidgetDataKeys.lastUpdateTime)),
            languageIdentifier: defaults.string(forKey: PTWidgetDataKeys.languageIdentifier)
        )
    }

    nonisolated public static func read(from defaults: UserDefaults?) -> PTWidgetSharedStatus {
        PTWidgetSharedStatus(defaults: defaults) ?? .placeholder
    }

    nonisolated public func write(to defaults: UserDefaults) {
        defaults.set(fuelLevel, forKey: PTWidgetDataKeys.fuelLevel)
        defaults.set(tripKm, forKey: PTWidgetDataKeys.tripKm)
        defaults.set(isConnected, forKey: PTWidgetDataKeys.isConnected)
        defaults.set(parkedLat, forKey: PTWidgetDataKeys.parkedLat)
        defaults.set(parkedLon, forKey: PTWidgetDataKeys.parkedLon)
        defaults.set(address, forKey: PTWidgetDataKeys.address)
        defaults.set(lastUpdateTime.timeIntervalSince1970, forKey: PTWidgetDataKeys.lastUpdateTime)
        if let languageIdentifier {
            defaults.set(languageIdentifier, forKey: PTWidgetDataKeys.languageIdentifier)
        } else {
            defaults.removeObject(forKey: PTWidgetDataKeys.languageIdentifier)
        }
    }

    nonisolated public var applicationContext: [String: Any] {
        var values: [String: Any] = [
            PTWidgetDataKeys.fuelLevel: fuelLevel,
            PTWidgetDataKeys.tripKm: tripKm,
            PTWidgetDataKeys.isConnected: isConnected,
            PTWidgetDataKeys.parkedLat: parkedLat,
            PTWidgetDataKeys.parkedLon: parkedLon,
            PTWidgetDataKeys.address: address,
            PTWidgetDataKeys.lastUpdateTime: lastUpdateTime.timeIntervalSince1970
        ]
        if let languageIdentifier {
            values[PTWidgetDataKeys.languageIdentifier] = languageIdentifier
        }
        return values
    }

    nonisolated private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    nonisolated private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}

// EN: Resolve Widget and Watch copy independently from the selected iPhone locale.
// ES: Resuelve el texto del Widget y del Watch independientemente del locale seleccionado en el iPhone.
// 中文：让 Widget 和 Watch 根据 iPhone 选择的语言独立解析界面文案。
public enum PTWidgetLocalized {
    nonisolated public static func string(_ key: String, languageIdentifier: String?) -> String {
        let identifier = languageIdentifier.flatMap { normalized($0) }

        // EN: Read the selected locale's concrete resource before Foundation can fall back to the source locale.
        // ES: Lee primero el recurso concreto del locale elegido antes de que Foundation vuelva al locale de origen.
        // 中文：先读取当前选择语言的具体资源，避免 Foundation 提前回退到源语言（尤其是繁体中文回退为简体中文）。
        if let identifier,
           let value = legacyValue(for: key, languageIdentifier: identifier) {
            return value
        }

        // EN: Japanese, Russian and Traditional Chinese may have staged or missing Catalog entries, so use the app fallback map.
        // ES: Japonés, ruso y chino tradicional pueden tener entradas de Catalog parciales, así que usan el mapa de respaldo de la app.
        // 中文：日语、俄语和繁体中文可能存在分阶段或缺失的 Catalog 条目，因此使用 App 自己的回退映射。
        if let identifier, identifier == "ja" || identifier == "ru" || identifier == "zh-Hant" {
            if let value = PTLocalizationFallback.value(for: key, languageIdentifier: identifier) {
                return value
            }
            return englishValue(for: key) ?? key
        }

        let locale = identifier.map(Locale.init(identifier:)) ?? .current
        let catalogValue = String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
        if catalogValue != key { return catalogValue }
        if let value = PTLocalizationFallback.value(for: key, languageIdentifier: identifier) {
            return value
        }
        return englishValue(for: key) ?? key
    }

    nonisolated private static func normalized(_ identifier: String) -> String? {
        // EN: Accept underscore-style locale identifiers left by older builds.
        // ES: Acepta identificadores de locale con guion bajo guardados por versiones anteriores.
        // 中文：兼容旧版本保存的下划线格式语言标识。
        let value = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
        return value.isEmpty ? nil : value
    }

    // EN: Read a concrete lproj first so runtime language switching does not depend
    // on the device's system language or on Bundle.preferredLocalizations.
    // ES: Lee primero el lproj concreto para que el cambio de idioma no dependa del
    // idioma del sistema ni de Bundle.preferredLocalizations.
    // 中文：优先读取明确的 lproj，避免运行时切换依赖系统语言或 preferredLocalizations。
    nonisolated private static func legacyValue(for key: String, languageIdentifier: String) -> String? {
        guard let path = Bundle.main.path(forResource: languageIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        let value = bundle.localizedString(forKey: key, value: key, table: "Localizable")
        return value == key ? nil : value
    }

    nonisolated private static func englishValue(for key: String) -> String? {
        if let value = legacyValue(for: key, languageIdentifier: "en") {
            return value
        }
        let value = String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: Locale(identifier: "en")
        )
        return value == key ? nil : value
    }
}

// EN: Build 49 fallback copy keeps new screens readable while staged locale coverage is completed.
// ES: El texto de respaldo de Build 49 mantiene legibles las pantallas nuevas mientras se completa la cobertura gradual de locales.
// 中文：在分阶段补齐各语言目录期间，Build49 回退文案保证新增页面仍然可读。
enum PTLocalizationFallback {
    nonisolated static func value(for key: String, languageIdentifier: String?) -> String? {
        let normalized = languageIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseLanguage = normalized?.split(separator: "-").first.map(String.init)
        return normalized.flatMap { values[$0]?[key] }
            ?? baseLanguage.flatMap { values[$0]?[key] }
            ?? values["en"]?[key]
    }

    nonisolated private static let values: [String: [String: String]] = [
        "en": [
            "garage_documents": "Vehicle documents",
            "garage_document_import": "Import document",
            "garage_document_scan": "Scan document",
            "garage_document_empty": "No documents yet",
            "garage_document_share": "Share",
            "garage_document_delete": "Delete",
            "garage_document_failed": "Document could not be saved.",
            "ride_replay_photos": "Ride photos",
            "ride_photo_add": "Add photos",
            "ride_photo_empty": "No ride photos yet",
            "ride_photo_failed": "Photo could not be saved.",
            "roadbook_shareplay": "Share Roadbook with SharePlay",
            "roadbook_shareplay_unavailable": "SharePlay is not available right now.",
            "app_intent_open_readiness_title": "Open ride readiness",
            "app_intent_open_garage_title": "Open motorcycle garage",
            "app_intent_open_roadbooks_title": "Open Roadbooks",
            "app_intent_open_description": "Open a read-only motorcycle workspace.",
            "app_intent_readiness_opened": "Ride readiness opened.",
            "app_intent_garage_opened": "Motorcycle garage opened.",
            "app_intent_roadbooks_opened": "Roadbooks opened.",
            "dev_firmware_inspection_file": "Select firmware file",
            "dev_firmware_inspection_failed": "Firmware file inspection failed.",
            "can_lab_capture_failed": "Capture could not start"
        ],
        "zh": [
            "garage_documents": "车辆资料",
            "garage_document_import": "导入资料",
            "garage_document_scan": "扫描资料",
            "garage_document_empty": "暂无车辆资料",
            "garage_document_share": "分享",
            "garage_document_delete": "删除",
            "garage_document_failed": "资料保存失败。",
            "ride_replay_photos": "骑行照片",
            "ride_photo_add": "添加照片",
            "ride_photo_empty": "暂无骑行照片",
            "ride_photo_failed": "照片保存失败。",
            "roadbook_shareplay": "使用 SharePlay 分享路线",
            "roadbook_shareplay_unavailable": "SharePlay 当前不可用。",
            "app_intent_open_readiness_title": "打开出发检查",
            "app_intent_open_garage_title": "打开摩托车车库",
            "app_intent_open_roadbooks_title": "打开路线簿",
            "app_intent_open_description": "打开只读摩托车工作区。",
            "app_intent_readiness_opened": "已打开出发检查。",
            "app_intent_garage_opened": "已打开摩托车车库。",
            "app_intent_roadbooks_opened": "已打开路线簿。",
            "dev_firmware_inspection_file": "选择固件文件",
            "dev_firmware_inspection_failed": "固件文件检查失败。",
            "can_lab_capture_failed": "抓包启动失败"
        ],
        "ja": [
            // EN: These high-traffic strings make a language change visible immediately on the existing screens.
            // ES: Estas cadenas de uso frecuente hacen visible de inmediato el cambio en las pantallas actuales.
            // 中文：这些高频文案确保在现有页面上切换语言后能立即看到变化。
            "dashboard_color_set_title": "メーターパネルの色設定",
            "button_cancel": "キャンセル",
            "dashboard_set_title": "メーターパネルの距離単位",
            "casa_card_lan": "メーターパネルの言語",
            "language_set_title": "言語設定",
            "ptt_restore_on_launch": "起動時にPTTを復元",
            "dashboard_notification_title": "電話・メッセージ・通知",
            "dashboard_notification_setup": "設定 / テスト",
            "button_dis_connect": "Bluetooth接続を解除",
            "button_confirm": "確認",
            "garage_open": "ガレージを開く",
            "automation_guide_open": "Siriと自動化のガイドを表示",
            "set_success": "設定しました",
            "set_bad": "設定に失敗しました",
            "dashboard_config_sent": "メーターパネルへの指示を送信しました",
            "dashboard_config_unconfirmed": "メーターパネルの確認を受信できませんでした",
            "shortcuts_title": "Siriとショートカット",
            "tab_navigation": "ナビゲーション",
            "Data": "データ",
            "PTT": "PTT",
            "tab_setting": "設定",
            "button_done": "完了",
            "alert_title": "お知らせ",
            "alert_loading": "読み込み中…",
            "Delete": "削除",
            "Connect option": "接続オプション",
            "OBD": "OBD",
            "OBD info": "OBD情報",
            "obd_diagnostic_center": "読み取り専用診断センター",
            "can_lab_title": "CANキャプチャラボ",
            "obd_disconnect": "接続を解除",
            "Motion device": "モーションデバイス",
            "ride_center": "ライドコックピット",
            "Dashboard": "ダッシュボード",
            "connect_success": "接続しました",
            "ride_not_available": "データなし",
            "casa_card_little_trip": "小計距離",
            "casa_card_odo_trip": "総走行距離",
            "casa_card_engine": "エンジン状態",
            "casa_card_tem": "温度",
            "casa_batt": "電圧",
            "casa_dist_to_maintenance": "メンテナンスまでの距離",
            "ptt_resume_audio": "音声を再開",
            "ptt_change_hand_free": "ハンズフリー音声モードに切替",
            "ptt_in": "グループ通話に参加",
            "Edit name": "名前を編集",
            "ptt_ready_connect": "接続準備中…",
            "ptt_push": "押して話す",
            "ptt_change_ptt": "プッシュトゥトークに切替",
            "ptt_hand_free_listening": "ハンズフリーモードで監視中…",
            "ptt_release": "離して終了",
            "ptt_out": "グループ通話を退出",
            "ptt_ready_connect_count": "現在接続中のライダー: %d人",
            "route_plan1": "渋滞を避ける",
            "route_plan2": "有料道路を避ける",
            "route_plan3": "高速道路を避ける",
            "route_plan4": "高速道路を優先",
            "search_placeholder": "住所を検索…",
            "roadbook_normal_navigation_conflict": "通常のナビゲーションを開始する前に、現在のルートを終了してください。",
            "garage_title": "バイクガレージ",
            "garage_current_vehicle": "現在のバイク",
            "garage_add_vehicle": "バイクを追加",
            "garage_vehicle_name": "バイク名",
            "garage_edit_vehicle_name": "バイク名を編集",
            "garage_maintenance": "メンテナンス",
            "garage_maintenance_title": "メンテナンス項目",
            "garage_maintenance_remaining": "残りメンテナンス距離",
            "garage_maintenance_status": "メンテナンス状態",
            "garage_no_vehicle": "バイクが登録されていません",
            "garage_no_live_data": "ライブデータなし",
            "garage_sync_waiting": "車両データを同期しています…",
            "garage_documents": "車両書類",
            "garage_document_import": "書類を読み込む",
            "garage_document_scan": "書類をスキャン",
            "garage_document_empty": "車両書類はありません",
            "garage_document_share": "共有",
            "garage_document_delete": "削除",
            "garage_document_failed": "書類を保存できませんでした。",
            "ride_replay_photos": "走行写真",
            "ride_photo_add": "写真を追加",
            "ride_photo_empty": "走行写真はありません",
            "ride_photo_failed": "写真を保存できませんでした。",
            "roadbook_shareplay": "SharePlayでルートを共有",
            "roadbook_shareplay_unavailable": "現在SharePlayを利用できません。",
            "app_intent_open_readiness_title": "出発チェックを開く",
            "app_intent_open_garage_title": "バイクガレージを開く",
            "app_intent_open_roadbooks_title": "ルートブックを開く",
            "app_intent_open_description": "読み取り専用のバイクワークスペースを開きます。",
            "app_intent_readiness_opened": "出発チェックを開きました。",
            "app_intent_garage_opened": "バイクガレージを開きました。",
            "app_intent_roadbooks_opened": "ルートブックを開きました。",
            "dev_firmware_inspection_file": "ファームウェアを選択",
            "dev_firmware_inspection_failed": "ファームウェアの検査に失敗しました。",
            "can_lab_capture_failed": "キャプチャを開始できませんでした"
        ],
        "ru": [
            // EN: These high-traffic strings make a language change visible immediately on the existing screens.
            // ES: Estas cadenas de uso frecuente hacen visible de inmediato el cambio en las pantallas actuales.
            // 中文：这些高频文案确保在现有页面上切换语言后能立即看到变化。
            "dashboard_color_set_title": "Цвет панели приборов",
            "button_cancel": "Отмена",
            "dashboard_set_title": "Единица расстояния на панели",
            "casa_card_lan": "Язык панели приборов",
            "language_set_title": "Настройки языка",
            "ptt_restore_on_launch": "Восстанавливать PTT при запуске",
            "dashboard_notification_title": "Звонки, сообщения и уведомления",
            "dashboard_notification_setup": "Настроить / Проверить",
            "button_dis_connect": "Отключить Bluetooth",
            "button_confirm": "Подтвердить",
            "garage_open": "Открыть гараж",
            "automation_guide_open": "Открыть руководство Siri и автоматизаций",
            "set_success": "Настройка выполнена",
            "set_bad": "Не удалось применить настройку",
            "dashboard_config_sent": "Команда панели приборов отправлена",
            "dashboard_config_unconfirmed": "Подтверждение панели приборов не получено",
            "shortcuts_title": "Siri и быстрые команды",
            "tab_navigation": "Навигация",
            "Data": "Данные",
            "PTT": "PTT",
            "tab_setting": "Настройки",
            "button_done": "Готово",
            "alert_title": "Уведомление",
            "alert_loading": "Загрузка…",
            "Delete": "Удалить",
            "Connect option": "Вариант подключения",
            "OBD": "OBD",
            "OBD info": "Информация OBD",
            "obd_diagnostic_center": "Центр диагностики только для чтения",
            "can_lab_title": "Лаборатория захвата CAN",
            "obd_disconnect": "Отключить",
            "Motion device": "Датчик движения",
            "ride_center": "Кабина поездки",
            "Dashboard": "Панель приборов",
            "connect_success": "Подключено",
            "ride_not_available": "Нет данных",
            "casa_card_little_trip": "Суточный пробег",
            "casa_card_odo_trip": "Общий пробег",
            "casa_card_engine": "Состояние двигателя",
            "casa_card_tem": "Температура",
            "casa_batt": "Напряжение",
            "casa_dist_to_maintenance": "Пробег до обслуживания",
            "ptt_resume_audio": "Возобновить звук",
            "ptt_change_hand_free": "Переключить на громкую связь",
            "ptt_in": "Войти в групповой интерком",
            "Edit name": "Изменить имя",
            "ptt_ready_connect": "Подготовка к подключению…",
            "ptt_push": "Нажмите, чтобы говорить",
            "ptt_change_ptt": "Переключить на режим PTT",
            "ptt_hand_free_listening": "Прослушивание в режиме громкой связи…",
            "ptt_release": "Отпустите для завершения",
            "ptt_out": "Выйти из группового интеркома",
            "ptt_ready_connect_count": "Сейчас подключено райдеров: %d",
            "route_plan1": "Избегать пробок",
            "route_plan2": "Избегать платных дорог",
            "route_plan3": "Избегать автомагистралей",
            "route_plan4": "Предпочитать автомагистрали",
            "search_placeholder": "Поиск адреса…",
            "roadbook_normal_navigation_conflict": "Завершите текущий маршрут перед запуском обычной навигации.",
            "garage_title": "Гараж мотоцикла",
            "garage_current_vehicle": "Текущий мотоцикл",
            "garage_add_vehicle": "Добавить мотоцикл",
            "garage_vehicle_name": "Название мотоцикла",
            "garage_edit_vehicle_name": "Изменить название мотоцикла",
            "garage_maintenance": "Обслуживание",
            "garage_maintenance_title": "Обслуживание",
            "garage_maintenance_remaining": "Пробег до обслуживания",
            "garage_maintenance_status": "Состояние обслуживания",
            "garage_no_vehicle": "Мотоцикл не добавлен",
            "garage_no_live_data": "Нет оперативных данных",
            "garage_sync_waiting": "Синхронизация данных мотоцикла…",
            "garage_documents": "Документы мотоцикла",
            "garage_document_import": "Импортировать документ",
            "garage_document_scan": "Сканировать документ",
            "garage_document_empty": "Документов пока нет",
            "garage_document_share": "Поделиться",
            "garage_document_delete": "Удалить",
            "garage_document_failed": "Не удалось сохранить документ.",
            "ride_replay_photos": "Фотографии поездки",
            "ride_photo_add": "Добавить фото",
            "ride_photo_empty": "Фотографий поездки пока нет",
            "ride_photo_failed": "Не удалось сохранить фото.",
            "roadbook_shareplay": "Поделиться маршрутом через SharePlay",
            "roadbook_shareplay_unavailable": "SharePlay сейчас недоступен.",
            "app_intent_open_readiness_title": "Открыть проверку поездки",
            "app_intent_open_garage_title": "Открыть гараж мотоциклов",
            "app_intent_open_roadbooks_title": "Открыть маршруты",
            "app_intent_open_description": "Открывает рабочее пространство мотоцикла только для чтения.",
            "dev_firmware_inspection_file": "Выбрать файл прошивки",
            "dev_firmware_inspection_failed": "Не удалось проверить файл прошивки.",
            "can_lab_capture_failed": "Не удалось начать захват"
        ],
        "fr": [
            "garage_documents": "Documents du véhicule",
            "garage_document_import": "Importer un document",
            "garage_document_scan": "Scanner un document",
            "garage_document_empty": "Aucun document",
            "garage_document_share": "Partager",
            "garage_document_delete": "Supprimer",
            "garage_document_failed": "Impossible d’enregistrer le document.",
            "ride_replay_photos": "Photos de trajet",
            "ride_photo_add": "Ajouter des photos",
            "ride_photo_empty": "Aucune photo de trajet",
            "ride_photo_failed": "Impossible d’enregistrer la photo.",
            "roadbook_shareplay": "Partager le Roadbook avec SharePlay",
            "roadbook_shareplay_unavailable": "SharePlay est indisponible.",
            "app_intent_open_readiness_title": "Ouvrir la vérification de départ",
            "app_intent_open_garage_title": "Ouvrir le garage moto",
            "app_intent_open_roadbooks_title": "Ouvrir les Roadbooks",
            "app_intent_open_description": "Ouvrir l’espace moto en lecture seule.",
            "dev_firmware_inspection_file": "Choisir le firmware",
            "dev_firmware_inspection_failed": "Échec de l’inspection du firmware."
        ],
        "de": [
            "garage_documents": "Fahrzeugdokumente",
            "garage_document_import": "Dokument importieren",
            "garage_document_scan": "Dokument scannen",
            "garage_document_empty": "Noch keine Dokumente",
            "garage_document_share": "Teilen",
            "garage_document_delete": "Löschen",
            "garage_document_failed": "Dokument konnte nicht gespeichert werden.",
            "ride_replay_photos": "Fahrtfotos",
            "ride_photo_add": "Fotos hinzufügen",
            "ride_photo_empty": "Noch keine Fahrtfotos",
            "ride_photo_failed": "Foto konnte nicht gespeichert werden.",
            "roadbook_shareplay": "Roadbook mit SharePlay teilen",
            "roadbook_shareplay_unavailable": "SharePlay ist derzeit nicht verfügbar.",
            "app_intent_open_readiness_title": "Fahrtcheck öffnen",
            "app_intent_open_garage_title": "Motorradgarage öffnen",
            "app_intent_open_roadbooks_title": "Roadbooks öffnen",
            "app_intent_open_description": "Schreibgeschützten Motorradbereich öffnen.",
            "dev_firmware_inspection_file": "Firmware-Datei auswählen",
            "dev_firmware_inspection_failed": "Firmware-Prüfung fehlgeschlagen."
        ],
        "es": [
            "garage_documents": "Documentos de la moto",
            "garage_document_import": "Importar documento",
            "garage_document_scan": "Escanear documento",
            "garage_document_empty": "Aún no hay documentos",
            "garage_document_share": "Compartir",
            "garage_document_delete": "Eliminar",
            "garage_document_failed": "No se pudo guardar el documento.",
            "ride_replay_photos": "Fotos de la ruta",
            "ride_photo_add": "Añadir fotos",
            "ride_photo_empty": "Aún no hay fotos de la ruta",
            "ride_photo_failed": "No se pudo guardar la foto.",
            "roadbook_shareplay": "Compartir Roadbook con SharePlay",
            "roadbook_shareplay_unavailable": "SharePlay no está disponible ahora.",
            "app_intent_open_readiness_title": "Abrir revisión de salida",
            "app_intent_open_garage_title": "Abrir garaje de motos",
            "app_intent_open_roadbooks_title": "Abrir Roadbooks",
            "app_intent_open_description": "Abrir el espacio de moto en modo lectura.",
            "dev_firmware_inspection_file": "Elegir archivo de firmware",
            "dev_firmware_inspection_failed": "Falló la inspección del firmware."
        ],
        "it": [
            "garage_documents": "Documenti della moto",
            "garage_document_import": "Importa documento",
            "garage_document_scan": "Scansiona documento",
            "garage_document_empty": "Nessun documento",
            "garage_document_share": "Condividi",
            "garage_document_delete": "Elimina",
            "garage_document_failed": "Impossibile salvare il documento.",
            "ride_replay_photos": "Foto del viaggio",
            "ride_photo_add": "Aggiungi foto",
            "ride_photo_empty": "Nessuna foto del viaggio",
            "ride_photo_failed": "Impossibile salvare la foto.",
            "roadbook_shareplay": "Condividi Roadbook con SharePlay",
            "roadbook_shareplay_unavailable": "SharePlay non è disponibile.",
            "app_intent_open_readiness_title": "Apri controllo partenza",
            "app_intent_open_garage_title": "Apri garage moto",
            "app_intent_open_roadbooks_title": "Apri Roadbook",
            "app_intent_open_description": "Apri lo spazio moto in sola lettura.",
            "dev_firmware_inspection_file": "Scegli firmware",
            "dev_firmware_inspection_failed": "Ispezione firmware non riuscita."
        ],
        "tr": [
            "garage_documents": "Motosiklet belgeleri",
            "garage_document_import": "Belge içe aktar",
            "garage_document_scan": "Belge tara",
            "garage_document_empty": "Henüz belge yok",
            "garage_document_share": "Paylaş",
            "garage_document_delete": "Sil",
            "garage_document_failed": "Belge kaydedilemedi.",
            "ride_replay_photos": "Sürüş fotoğrafları",
            "ride_photo_add": "Fotoğraf ekle",
            "ride_photo_empty": "Henüz sürüş fotoğrafı yok",
            "ride_photo_failed": "Fotoğraf kaydedilemedi.",
            "roadbook_shareplay": "Roadbook'u SharePlay ile paylaş",
            "roadbook_shareplay_unavailable": "SharePlay şu anda kullanılamıyor.",
            "app_intent_open_readiness_title": "Sürüş kontrolünü aç",
            "app_intent_open_garage_title": "Motosiklet garajını aç",
            "app_intent_open_roadbooks_title": "Roadbook'ları aç",
            "app_intent_open_description": "Salt okunur motosiklet çalışma alanını açar.",
            "dev_firmware_inspection_file": "Donanım yazılımı seç",
            "dev_firmware_inspection_failed": "Donanım yazılımı incelenemedi."
        ],
        "zh-Hant": [
            // EN: Keep the visible settings and vehicle screens usable even when a new key is not yet in the compiled catalog.
            // ES: Mantén utilizables las pantallas visibles de ajustes y vehículo aunque una clave nueva aún no esté en el catálogo compilado.
            // 中文：即使新增 key 尚未进入编译后的 Catalog，也保证设置和车辆主要页面可用。
            "dashboard_color_set_title": "儀表板顏色設定",
            "button_cancel": "取消",
            "dashboard_set_title": "儀表板的里程單位",
            "casa_card_lan": "儀表板語言",
            "language_set_title": "語言設定",
            "ptt_restore_on_launch": "啟動時恢復 PTT",
            "dashboard_notification_title": "電話、簡訊與通知",
            "dashboard_notification_setup": "設定／測試",
            "button_dis_connect": "解除 Bluetooth 連線",
            "button_confirm": "確認",
            "garage_open": "開啟車庫",
            "automation_guide_open": "查看 Siri 與自動化指南",
            "set_success": "設定成功",
            "set_bad": "設定失敗",
            "dashboard_config_sent": "儀表指令已傳送",
            "dashboard_config_unconfirmed": "未收到儀表確認",
            "shortcuts_title": "Siri 與捷徑",
            "tab_navigation": "導航",
            "Data": "資料",
            "PTT": "PTT",
            "tab_setting": "設定",
            "button_done": "完成",
            "alert_title": "提示",
            "alert_loading": "載入中…",
            "Delete": "刪除",
            "Connect option": "連線選項",
            "OBD": "OBD",
            "OBD info": "OBD 資訊",
            "obd_diagnostic_center": "唯讀診斷中心",
            "can_lab_title": "CAN 擷取實驗室",
            "obd_disconnect": "中斷連線",
            "Motion device": "動作裝置",
            "ride_center": "騎行駕駛艙",
            "Dashboard": "儀表板",
            "connect_success": "連線成功",
            "ride_not_available": "沒有資料",
            "casa_card_little_trip": "小計里程數",
            "casa_card_odo_trip": "總里程數",
            "casa_card_engine": "發動機狀態",
            "casa_card_tem": "溫度",
            "casa_batt": "電壓",
            "casa_dist_to_maintenance": "距離保養里程",
            "ptt_resume_audio": "恢復音訊",
            "ptt_change_hand_free": "切換至免持語音模式",
            "ptt_in": "加入群組通話",
            "Edit name": "編輯名稱",
            "ptt_ready_connect": "準備連線中…",
            "ptt_push": "按住說話",
            "ptt_change_ptt": "切換至 PTT 模式",
            "ptt_hand_free_listening": "免持模式監聽中…",
            "ptt_release": "放開以結束",
            "ptt_out": "離開群組通話",
            "ptt_ready_connect_count": "目前連線中的騎士：%d 人",
            "route_plan1": "避開塞車",
            "route_plan2": "避開收費道路",
            "route_plan3": "避開高速公路",
            "route_plan4": "優先使用高速公路",
            "search_placeholder": "搜尋地址…",
            "roadbook_normal_navigation_conflict": "開始一般導航前，請先結束目前的路線。",
            "garage_title": "車庫",
            "garage_current_vehicle": "目前摩托車",
            "garage_add_vehicle": "新增摩托車",
            "garage_vehicle_name": "摩托車名稱",
            "garage_edit_vehicle_name": "編輯摩托車名稱",
            "garage_maintenance": "保養",
            "garage_maintenance_title": "保養項目",
            "garage_maintenance_remaining": "剩餘保養里程",
            "garage_maintenance_status": "保養狀態",
            "garage_no_vehicle": "尚未新增摩托車",
            "garage_no_live_data": "沒有即時資料",
            "garage_sync_waiting": "正在同步車輛資料…",
            "can_lab_capture_failed": "無法開始擷取",
            "garage_documents": "車輛資料",
            "garage_document_import": "匯入資料",
            "garage_document_scan": "掃描資料",
            "garage_document_empty": "尚無車輛資料",
            "garage_document_share": "分享",
            "garage_document_delete": "刪除",
            "garage_document_failed": "資料儲存失敗。",
            "ride_replay_photos": "騎行照片",
            "ride_photo_add": "加入照片",
            "ride_photo_empty": "尚無騎行照片",
            "ride_photo_failed": "照片儲存失敗。",
            "roadbook_shareplay": "使用 SharePlay 分享路線",
            "roadbook_shareplay_unavailable": "SharePlay 目前無法使用。",
            "app_intent_open_readiness_title": "開啟出發檢查",
            "app_intent_open_garage_title": "開啟摩托車車庫",
            "app_intent_open_roadbooks_title": "開啟路線簿",
            "app_intent_open_description": "開啟唯讀摩托車工作區。",
            "dev_firmware_inspection_file": "選擇韌體檔案",
            "dev_firmware_inspection_failed": "韌體檔案檢查失敗。"
        ]
    ]
}
