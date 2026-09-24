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
        "settings.login": "Start at Login",
        "settings.quit": "Quit Miqat",
        "language.system": "System",
        "nav.settings": "Settings",
        "settings.title": "Settings",
        "settings.section.calculation": "Calculation",
        "settings.section.appearance": "Menu Bar Appearance",
        "settings.section.general": "General",
        "settings.hijriOffset": "Hijri Date",
        "settings.offlineNote": "Miqat calculates prayer times 100% offline using local astronomical algorithms.",

        // Hero & Schedule
        "hero.nextPrayer": "Next Prayer",
        "prayer.passed": "Passed",

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

        // Adhan
        "settings.section.adhan": "Adhan",
        "settings.adhan.master": "Adhan notifications",
        "adhan.preview.play": "Preview",
        "adhan.preview.stop": "Stop",
        "adhan.banners.denied": "Banners are turned off for Miqat — the adhan sound still plays. Allow banners in System Settings › Notifications.",
        "adhan.banners.openSettings": "Open Notification Settings",
        "adhan.notification.title": "It's time for %@",
        // Fajr-variant tracks render without any "Fajr" postfix — they only
        // ever appear in Fajr's picker, so the suffix would be noise.
        "adhan.track.makkah-fajr": "Al-Haram al-Makki",
        "adhan.track.madinah-fajr": "Al-Haram al-Madani",
        "adhan.track.makkah": "Al-Haram al-Makki",
        "adhan.track.madinah": "Al-Haram al-Madani",
        "adhan.track.aqsa": "Al-Aqsa, Jerusalem",
        "adhan.track.alafasy": "Mishary Alafasy",

        // Redesign
        "hero.tomorrow": "Tomorrow",
        "hero.accessibility": "Next prayer %@ at %@, in %@",
        "schedule.next": "Next prayer",
        "adhan.toggle.on": "Adhan on — click to mute",
        "adhan.toggle.off": "Adhan muted — click to turn on",
        "footer.localTime": "Times shown in %@ local time",
        "location.change": "Change location",
        "location.selected": "Current",
        "location.detect.subtitle": "Uses Wi-Fi positioning — needs internet",
        "settings.adhan.subtitle": "Sound and a banner at each prayer",
        "settings.hijriOffset.hint": "Adjust to match your local moon sighting",
        "settings.menubar.preview": "Preview",
        "settings.version": "Version %@",
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
        "settings.login": "التشغيل عند تسجيل الدخول",
        "settings.quit": "إغلاق التطبيق",
        "language.system": "حسب النظام",
        "nav.settings": "الإعدادات",
        "settings.title": "الإعدادات",
        "settings.section.calculation": "طريقة الحساب",
        "settings.section.appearance": "مظهر شريط القائمة",
        "settings.section.general": "عام",
        "settings.hijriOffset": "التاريخ الهجري",
        "settings.offlineNote": "يحسب مِيقَات مواقيت الصلاة دون اتصال بالإنترنت بنسبة 100٪ باستخدام خوارزميات فلكية محلية.",

        // Hero & Schedule
        "hero.nextPrayer": "الصلاة القادمة",
        "prayer.passed": "مضت",

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

        // Adhan
        "settings.section.adhan": "الأذان",
        "settings.adhan.master": "إشعارات الأذان",
        "adhan.preview.play": "معاينة",
        "adhan.preview.stop": "إيقاف",
        "adhan.banners.denied": "الإشعارات (البانرات) معطلة لمِيقَات — سيبقى صوت الأذان مسموعاً. فعّل الإشعارات من إعدادات النظام › الإشعارات.",
        "adhan.banners.openSettings": "افتح إعدادات الإشعارات",
        "adhan.notification.title": "حان وقت %@",
        "adhan.track.makkah-fajr": "الحرم المكي",
        "adhan.track.madinah-fajr": "الحرم المدني",
        "adhan.track.makkah": "الحرم المكي",
        "adhan.track.madinah": "الحرم المدني",
        "adhan.track.aqsa": "المسجد الأقصى، القدس",
        "adhan.track.alafasy": "مشاري راشد العفاسي",

        // Redesign
        "hero.tomorrow": "غداً",
        "hero.accessibility": "الصلاة القادمة %@ عند %@، بعد %@",
        "schedule.next": "الصلاة القادمة",
        "adhan.toggle.on": "الأذان مفعّل — انقر للكتم",
        "adhan.toggle.off": "الأذان مكتوم — انقر للتفعيل",
        "footer.localTime": "الأوقات معروضة بالتوقيت المحلي لـ %@",
        "location.change": "تغيير الموقع",
        "location.selected": "الحالي",
        "location.detect.subtitle": "عبر شبكات Wi-Fi — يتطلب اتصالاً بالإنترنت",
        "settings.adhan.subtitle": "صوت وإشعار عند كل صلاة",
        "settings.hijriOffset.hint": "اضبطه ليطابق رؤية الهلال في بلدك",
        "settings.menubar.preview": "معاينة",
        "settings.version": "الإصدار %@",
    ]
}
