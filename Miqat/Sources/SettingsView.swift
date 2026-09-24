import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: PrayerScheduleStore
    @ObservedObject private var localization = Localization.shared
    var onDismiss: () -> Void

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { LoginItemManager.isEnabled },
            set: { enabled in
                _ = LoginItemManager.setEnabled(enabled)
            }
        )
    }

    private func directionalIcon(ltr: String, rtl: String) -> String {
        localization.isRTL ? rtl : ltr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            ZStack {
                Text(localization.string("settings.title"))
                    .font(.headline)

                HStack {
                    Button(action: onDismiss) {
                        Label(
                            localization.string("location.back"),
                            systemImage: directionalIcon(ltr: "chevron.left", rtl: "chevron.right")
                        )
                    }
                    .controlSize(.small)

                    Spacer()
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Calculation section
                    sectionBox(title: localization.string("settings.section.calculation")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(localization.string("settings.method"), selection: $store.method) {
                                ForEach(CalculationMethodChoice.allCases) { method in
                                    Text(method.displayName).tag(method)
                                }
                            }

                            Picker(localization.string("settings.asr"), selection: $store.madhab) {
                                ForEach(AsrMadhab.allCases) { madhab in
                                    Text(madhab.displayName).tag(madhab)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Appearance section
                    sectionBox(title: localization.string("settings.section.appearance")) {
                        Picker(localization.string("settings.menubar"), selection: $store.titleStyle) {
                            ForEach(TitleStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // General section
                    sectionBox(title: localization.string("settings.section.general")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(localization.string("settings.language"), selection: $localization.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.displayName).tag(language)
                                }
                            }

                            Divider()

                            Toggle(localization.string("settings.login"), isOn: loginBinding)
                        }
                    }

                    // About & Actions
                    sectionBox(title: localization.string("settings.section.about")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(localization.string("settings.offlineNote"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            HStack {
                                Text("Miqat \(versionString)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)

                                Spacer()

                                Button(role: .destructive) {
                                    NSApplication.shared.terminate(nil)
                                } label: {
                                    Text(localization.string("settings.quit"))
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(maxHeight: 460)
        }
    }

    private func sectionBox<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}
