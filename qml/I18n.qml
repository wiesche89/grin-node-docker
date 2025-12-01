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

        console.log("I18n: loadLanguage(", lang, "), resolved url =", url)

        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)

        xhr.onreadystatechange = function() {
            console.log("I18n: XHR state change for", url,
                        "readyState =", xhr.readyState,
                        "status =", xhr.status)

            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            console.log("I18n: XHR DONE for", url,
                        "status =", xhr.status,
                        "response length =",
                        xhr.responseText ? xhr.responseText.length : 0)

            if (xhr.status === 200 || xhr.status === 0) {
                try {
                    var obj = JSON.parse(xhr.responseText)
                    dict = obj
                    var keyCount = Object.keys(dict).length
                    loaded = true  // <- wichtig: triggert Rebinding
                    console.log("I18n: successfully loaded language", lang,
                                "with", keyCount, "keys from", url)
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
                    console.log("I18n: retrying with English fallback")
                    loadLanguage("en")
                }
            }
        }

        console.log("I18n: sending XHR for", url)
        xhr.send()
    }

    // ------------------------------------------------------------------
    // Initialization
    // ------------------------------------------------------------------
    Component.onCompleted: {
        console.log("I18n: Component.onCompleted, initial language =", language)

        // Read initial language from settings if available
        if (settingsStore && settingsStore.languageCode) {
            language = settingsStore.languageCode
            console.log("I18n: language restored from settings:", language)
        }

        loadLanguage(language)
    }

    onLanguageChanged: {
        console.log("I18n: language changed to", language)

        // Persist language choice to settings
        if (settingsStore) {
            settingsStore.languageCode = language
            console.log("I18n: language stored to settings:", language)
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
