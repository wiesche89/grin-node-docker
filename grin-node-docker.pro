QT += qml quick gui core charts quickcontrols2 network

CONFIG += c++11
CONFIG += qml_debug

INCLUDEPATH += \
    src \
    src/geo \
    src/config \
    src/grinnodemanager \
    src/priceanalysis

SOURCES += \
    src/config/config.cpp \
    src/grinnodemanager/grinnodemanager.cpp \
    src/priceanalysis/priceanalysismanager.cpp \
    src/main.cpp \
    src/geo/geolookup.cpp

wasm {
    QMAKE_LFLAGS += -s WASM=1
}

HEADERS += \
    src/config/config.h \
    src/geo/geolookup.h \
    src/grinnodemanager/grinnodemanager.h \
    src/priceanalysis/priceanalysismanager.h



RESOURCES += \
    qml.qrc \
    res.qrc

#SUBMODULES
include(src/submodules/grin-common-api/grin-common-api.pri)
include(src/submodules/grin-node-api/grin-node-api.pri)

wasm {
    # Initialen Speicher von 16 MB auf 32 MB erhöhen
    # (32 * 1024 * 1024 = 33554432)
    QMAKE_LFLAGS += -s TOTAL_MEMORY=33554432
}

