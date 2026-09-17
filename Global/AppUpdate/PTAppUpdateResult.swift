//
//  PTAppUpdateResult.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 17/9/2026.
//

enum PTAppUpdateResult {

    case latest

    case optional(
        manifest: PTAppUpdateManifest
    )

    case required(
        manifest: PTAppUpdateManifest
    )

    case unavailable
}
