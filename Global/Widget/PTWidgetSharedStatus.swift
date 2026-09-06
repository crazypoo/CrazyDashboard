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
        let locale = identifier.map(Locale.init(identifier:)) ?? .current
        let value = String(
            localized: String.LocalizationValue(key),
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
        if value != key { return value }
        return PTLocalizationFallback.value(for: key, languageIdentifier: identifier) ?? key
    }

    nonisolated private static func normalized(_ identifier: String) -> String? {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// EN: Build 48 fallback copy keeps new screens readable until every String Catalog locale is exported.
// ES: El texto de respaldo de Build 48 mantiene legibles las pantallas nuevas hasta exportar todos los locales del catálogo.
// 中文：在完整导出 String Catalog 各语言之前，Build48 回退文案保证新增页面仍然可读。
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
            "dev_firmware_inspection_failed": "Firmware file inspection failed."
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
            "dev_firmware_inspection_failed": "固件文件检查失败。"
        ],
        "ja": [
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
            "dev_firmware_inspection_failed": "ファームウェアの検査に失敗しました。"
        ],
        "ru": [
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
            "dev_firmware_inspection_failed": "Не удалось проверить файл прошивки."
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
