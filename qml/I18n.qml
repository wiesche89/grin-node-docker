// I18n.qml
// Central translation helper (JSON-based, works on Desktop and WASM)

import QtQuick 2.15
import QtQml 2.15

QtObject {
    id: i18n

    // ------------------------------------------------------------------
    // External state
    // ------------------------------------------------------------------

    // Settings object from Main.qml (Qt.labs.settings or QtCore.Settings)
    // Used to persist the selected language between runs.
    property var settingsStore: null

    // Current language code ("en", "de", "ru", ...)
    property string language: "en"

    // Loaded translations: key -> string
    property var dict: ({})    // replaced when JSON is loaded

    // Flag: translations are loaded and ready
    property bool loaded: false

    // ------------------------------------------------------------------
    // Internal: load JSON for a language
    // ------------------------------------------------------------------
    function loadLanguage(lang) {
        if (!lang || typeof lang !== "string")
            lang = "en"

        // Beim Start: noch nicht geladen
        loaded = false
        dict = ({})

        // Relativ zu I18n.qml:
        // I18n.qml:          qrc:/qml/qml/I18n.qml
        // en.json erwartet:  qrc:/qml/qml/translation/en.json
        var url = Qt.resolvedUrl("translation/" + lang + ".json")

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (xhr.status === 200 || xhr.status === 0) {
                try {
                    var obj = JSON.parse(xhr.responseText)
                    dict = obj
                    var keyCount = Object.keys(dict).length
                    loaded = true  // <- wichtig: triggert Rebinding
                } catch (e) {
                    console.error("I18n: failed to parse JSON for", lang,
                                  "from", url, "error:", e)
                    dict = ({})
                    loaded = false
                }
            } else {
                console.warn("I18n: translation file missing or HTTP error:",
                             url, "status:", xhr.status)
                dict = ({})
                loaded = false

                // Simple fallback to English if the requested language failed
                if (lang !== "en") {
                    loadLanguage("en")
                }
            }
        }

        xhr.send()
    }

    // ------------------------------------------------------------------
    // Initialization
    // ------------------------------------------------------------------
    Component.onCompleted: {
        // Read initial language from settings if available
        if (settingsStore && settingsStore.languageCode) {
            language = settingsStore.languageCode
        }

        loadLanguage(language)
    }

    onLanguageChanged: {
        // Persist language choice to settings
        if (settingsStore) {
            settingsStore.languageCode = language
        }

        loadLanguage(language)
    }

    // ------------------------------------------------------------------
    // Public API: translate key
    // ------------------------------------------------------------------

    function t(key) {
        // Trick: Zugriff auf 'loaded', damit QML-Bindings eine
        // Abhängigkeit auf diese Property bekommen
        var _ = loaded

        if (!key || typeof key !== "string")
            return ""

        // Solange noch nicht geladen: keine Warnung spammen
        if (!loaded) {
            // optional: leeren String zurückgeben statt Key:
            // return ""
            return key
        }

        if (dict && dict.hasOwnProperty(key) && dict[key] !== undefined) {
            return String(dict[key])
        }

        console.warn("I18n: missing translation for key:", key,
                     "language:", language,
                     "(dict keys =", (dict ? Object.keys(dict).length : 0), ")")
        return key
    }

    function tf(key, fallback) {
        var value = t(key)
        if (value === key && fallback !== undefined && fallback !== null)
            return String(fallback)
        return value
    }
}
