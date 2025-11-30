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

    // Base path for JSON files
    // Project layout (from your screenshot):
    //   qml.qrc  ->  /qml/qml/translation/en.json  etc.
    //
    // Desktop / native: use qrc:
    // WASM:            use plain HTTP path served by the web server
    property string basePath: (
        Qt.platform.os === "wasm" || Qt.platform.os === "wasm-emscripten"
    ) ? "translation/"              // e.g. /translation/en.json via HTTP
      : "qrc:/qml/qml/translation/" // e.g. qrc:/qml/qml/translation/en.json

    // ------------------------------------------------------------------
    // Internal: load JSON for a language
    // ------------------------------------------------------------------
    function loadLanguage(lang) {
        if (!lang || typeof lang !== "string")
            lang = "en"

        // Resolve the full URL (handles qrc: and relative HTTP paths)
        var url = Qt.resolvedUrl(basePath + lang + ".json")

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            if (xhr.status === 200 || xhr.status === 0) {
                // status 0 can happen for qrc:/ or some embedded/WASM setups
                try {
                    dict = JSON.parse(xhr.responseText)
                    // console.log("I18n: loaded language", lang, "from", url)
                } catch (e) {
                    console.error("I18n: failed to parse JSON for", lang, e)
                    dict = ({})
                }
            } else {
                console.warn("I18n: translation file missing or HTTP error:", url,
                             "status:", xhr.status)
                dict = ({})

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
        if (settingsStore && settingsStore.languageCode)
            language = settingsStore.languageCode

        loadLanguage(language)
    }

    onLanguageChanged: {
        // Persist language choice to settings
        if (settingsStore)
            settingsStore.languageCode = language

        loadLanguage(language)
    }

    // ------------------------------------------------------------------
    // Public API: translate key
    // ------------------------------------------------------------------

    // Basic translation: returns the translated value or the key itself
    // if missing (and logs a warning to the console).
    function t(key) {
        if (!key || typeof key !== "string")
            return ""

        if (dict && dict.hasOwnProperty(key) && dict[key] !== undefined)
            return String(dict[key])

        console.warn("I18n: missing translation for key:", key,
                     "language:", language)
        return key
    }

    // Translation with explicit fallback text:
    // if the key is missing, returns the provided fallback instead.
    function tf(key, fallback) {
        var value = t(key)
        if (value === key && fallback !== undefined && fallback !== null)
            return String(fallback)
        return value
    }
}
