import Foundation
import SwiftUI

/// The interface language. `.system` follows the user's preferred languages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case arabic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return Localization.shared.string("language.system")
        case .english: return "English"
        case .arabic: return "العربية"
        }
    }

    /// Explicit language code, or nil for `.system`.
    var code: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .arabic: return "ar"
        }
    }
}

/// In-app localization: string tables for English and Arabic with instant
/// switching (no relaunch), plus the locale/layout direction the UI should use.
///
/// Deliberately hand-rolled rather than `.strings` bundles: the app builds
/// through both SPM and XcodeGen, and Swift tables keep the two languages
/// testable for key parity (see LocalizationTests).
final class Localization: ObservableObject {

    static let shared = Localization()
    static let storageKey = "miqat.language"

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.storageKey),
           let restored = AppLanguage(rawValue: stored) {
            language = restored
        } else {
            language = .system
        }
    }

    /// "ar" / "en" after resolving `.system` against preferred languages.
    var effectiveCode: String {
        if let code = language.code { return code }
        return Locale.preferredLanguages.first?.hasPrefix("ar") == true ? "ar" : "en"
    }

    var isArabic: Bool { effectiveCode == "ar" }
    var isRTL: Bool { isArabic }

    var locale: Locale { Locale(identifier: effectiveCode) }

    var layoutDirection: LayoutDirection { isRTL ? .rightToLeft : .leftToRight }

    /// Lookup with optional format arguments: `string("next.prefix", "43m")`.
    func string(_ key: String, _ args: CVarArg...) -> String {
        let template = Self.tables[effectiveCode]?[key]
            ?? Self.tables["en"]?[key]
            ?? key
        guard !args.isEmpty else { return template }
        return String(format: template, locale: locale, arguments: args)
    }

    // MARK: - Tables

    /// Internal for the key-parity test — do not read directly; use `string(_:).
    static let tables: [String: [String: String]] = [
        "en": en,
        "ar": ar,
    ]

    private static let en: [String: String] = [
        // Prayers
        "prayer.fajr": "Fajr",
        "prayer.sunrise": "Shuruq",
        "prayer.dhuhr": "Dhuhr",
        "prayer.asr": "Asr",
        "prayer.maghrib": "Maghrib",
        "prayer.isha": "Isha",
        "next.prefix": "in %@",

        // Onboarding
        "welcome.title": "Welcome to Miqat",
        "welcome.subtitle": "Pick your city to see today's prayer times and a live countdown. Everything works offline.",
        "onboarding.or": "or",

        // Location
        "location.title": "Location",
        "location.back": "Back",
        "location.search": "Search city…",
        "location.offlineHint": "Offline search · %@ cities bundled",
        "location.noMatches": "No cities match “%@”",
        "location.detect": "Use My Location",
        "location.locating": "Locating…",
        "location.manual": "Enter coordinates manually",
        "location.latitude": "Latitude",
        "location.longitude": "Longitude",
        "location.nameOptional": "Name (optional)",
        "location.useCoordinates": "Use Coordinates",

        // Errors
        "error.latitude": "Latitude must be a number between -90 and 90.",
        "error.longitude": "Longitude must be a number between -180 and 180.",
        "error.network": "Network unavailable — Macs locate via Wi-Fi positioning, which needs an internet connection. Try again once you're online.",
        "error.denied": "Location access was denied — search for a city instead.",
        "error.deniedSettings": "Location access is denied — search for a city instead. You can change this in System Settings › Privacy & Security › Location Services.",

        // Settings
        "settings.language": "Language",
        "settings.method": "Method",
        "settings.asr": "Asr",
        "settings.menubar": "Menu Bar",
        "settings.login": "Start at Login",
        "settings.quit": "Quit Miqat",
        "language.system": "System",

        // Menu bar themes
        "theme.icon": "Icon",
        "theme.countdown": "Countdown",
        "theme.labeled": "Labeled",

        // Madhab
        "madhab.shafi": "Shafi",
        "madhab.hanafi": "Hanafi",

        // Calculation methods
        "method.muslimWorldLeague": "Muslim World League",
        "method.egyptian": "Egyptian General Authority",
        "method.karachi": "Karachi (Islamic Sciences)",
        "method.ummAlQura": "Umm al-Qura, Makkah",
        "method.dubai": "Dubai (UAE)",
        "method.qatar": "Qatar",
        "method.kuwait": "Kuwait",
        "method.moonsightingCommittee": "Moonsighting Committee",
        "method.singapore": "Singapore & Malaysia",
        "method.turkey": "Turkey (Diyanet)",
        "method.tehran": "Tehran",
        "method.northAmerica": "ISNA (North America)",

        // Tooltip
        "tooltip.base": "Miqat — prayer times",
    ]

    private static let ar: [String: String] = [
        // Prayers
        "prayer.fajr": "الفجر",
        "prayer.sunrise": "الشروق",
        "prayer.dhuhr": "الظهر",
        "prayer.asr": "العصر",
        "prayer.maghrib": "المغرب",
        "prayer.isha": "العشاء",
        "next.prefix": "بعد %@",

        // Onboarding
        "welcome.title": "مرحباً بك في مِيقَات",
        "welcome.subtitle": "اختر مدينتك لعرض مواقيت الصلاة اليومية والعدّ التنازلي. كل شيء يعمل دون اتصال بالإنترنت.",
        "onboarding.or": "أو",

        // Location
        "location.title": "الموقع",
        "location.back": "رجوع",
        "location.search": "ابحث عن مدينة…",
        "location.offlineHint": "بحث دون اتصال · %@ مدينة",
        "location.noMatches": "لا توجد مدن مطابقة لـ «%@»",
        "location.detect": "استخدم موقعي",
        "location.locating": "جارٍ تحديد الموقع…",
        "location.manual": "إدخال الإحداثيات يدوياً",
        "location.latitude": "خط العرض",
        "location.longitude": "خط الطول",
        "location.nameOptional": "الاسم (اختياري)",
        "location.useCoordinates": "استخدم الإحداثيات",

        // Errors
        "error.latitude": "خط العرض يجب أن يكون رقماً بين ‎-90‎ و 90.",
        "error.longitude": "خط الطول يجب أن يكون رقماً بين ‎-180‎ و 180.",
        "error.network": "لا يوجد اتصال بالإنترنت — تحدد أجهزة Mac موقعها عبر شبكات Wi-Fi ويتطلب ذلك اتصالاً بالإنترنت. أعد المحاولة عند الاتصال.",
        "error.denied": "تم رفض الوصول إلى الموقع — ابحث عن مدينة بدلاً من ذلك.",
        "error.deniedSettings": "تم رفض الوصول إلى الموقع — ابحث عن مدينة بدلاً من ذلك. يمكنك التغيير من إعدادات النظام › الخصوصية والأمان › خدمات الموقع.",

        // Settings
        "settings.language": "اللغة",
        "settings.method": "طريقة الحساب",
        "settings.asr": "العصر",
        "settings.menubar": "شريط القائمة",
        "settings.login": "التشغيل عند تسجيل الدخول",
        "settings.quit": "إنهاء مِيقَات",
        "language.system": "حسب النظام",

        // Menu bar themes
        "theme.icon": "أيقونة",
        "theme.countdown": "عدّ تنازلي",
        "theme.labeled": "بالاسم",

        // Madhab
        "madhab.shafi": "شافعي",
        "madhab.hanafi": "حنفي",

        // Calculation methods
        "method.muslimWorldLeague": "رابطة العالم الإسلامي",
        "method.egyptian": "الهيئة المصرية العامة للمساحة",
        "method.karachi": "جامعة العلوم الإسلامية بكراتشي",
        "method.ummAlQura": "أم القرى، مكة المكرمة",
        "method.dubai": "دبي، الإمارات",
        "method.qatar": "قطر",
        "method.kuwait": "الكويت",
        "method.moonsightingCommittee": "لجنة رؤية الهلال",
        "method.singapore": "سنغافورة وماليزيا",
        "method.turkey": "تركيا (ديانت)",
        "method.tehran": "طهران",
        "method.northAmerica": "ISNA (أمريكا الشمالية)",

        // Tooltip
        "tooltip.base": "مِيقَات — مواقيت الصلاة",
    ]
}
