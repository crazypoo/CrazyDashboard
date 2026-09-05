//
//  PTMotoTranslationViewController.swift
//  CrazyDashboard
//
//  EN: Optional iOS 18 on-device translation for repair and rider communication text.
//  ES: Traducción opcional en el dispositivo de iOS 18 para reparaciones y comunicación entre pilotos.
//  中文：可选的 iOS 18 端侧翻译，用于维修沟通和车友交流文本。
//

import UIKit
import SwiftUI
import Translation
import PooTools

@MainActor
final class PTMotoTranslationViewController: PTMotoBaseViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        pt_Title = PTDashboardConfig.languageFunc(text: "translation_title")
        view.backgroundColor = .black

        if #available(iOS 18.0, *) {
            let host = UIHostingController(
                rootView: PTMotoTranslationCard(
                    targetLanguageIdentifier: PTLanguage.share.language
                )
            )
            addChild(host)
            view.addSubview(host.view)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            host.didMove(toParent: self)
        } else {
            let label = UILabel()
            label.text = PTDashboardConfig.languageFunc(text: "translation_unavailable")
            label.textColor = .systemGray
            label.numberOfLines = 0
            label.textAlignment = .center
            view.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }
}

// EN: Translation starts only after the rider taps the button and remains a local, reversible draft.
// ES: La traducción comienza solo cuando el piloto toca el botón y sigue siendo un borrador local y reversible.
// 中文：只有骑手点击按钮后才开始翻译，结果只保留为本地可撤销草稿。
@available(iOS 18.0, *)
private struct PTMotoTranslationCard: View {
    let targetLanguageIdentifier: String
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var errorMessage = ""
    @State private var configuration: TranslationSession.Configuration?

    init(targetLanguageIdentifier: String) {
        self.targetLanguageIdentifier = targetLanguageIdentifier
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringResource("translation_hint", table: "Localizable"))
                    .font(.subheadline)
                    .foregroundStyle(.gray)

                TextEditor(text: $sourceText)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)

                Button {
                    errorMessage = ""
                    translatedText = ""
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: targetLanguageIdentifier)
                    )
                } label: {
                    Label(
                        LocalizedStringResource("translation_start", table: "Localizable"),
                        systemImage: "character.bubble"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !translatedText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringResource("translation_result", table: "Localizable"))
                            .font(.headline)
                            .foregroundStyle(.blue)
                        Text(translatedText)
                            .foregroundStyle(.white)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = translatedText
                        } label: {
                            Label(
                                LocalizedStringResource("translation_copy", table: "Localizable"),
                                systemImage: "doc.on.doc"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .translationTask(configuration) { session in
            let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            do {
                let response = try await session.translate(text)
                translatedText = response.targetText
            } catch {
                errorMessage = PTDashboardConfig.languageFunc(text: "translation_failed")
            }
        }
    }
}
