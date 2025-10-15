QT += qml quick gui core charts quickcontrols2

CONFIG += c++11
CONFIG += qml_debug

INCLUDEPATH += \
    src \
    src/geo \
    src/config \
    src/grinnodemanager

SOURCES += \
    src/config/config.cpp \
    src/grinnodemanager/grinnodemanager.cpp \
    src/main.cpp \
    src/geo/geolookup.cpp

wasm {
    QMAKE_LFLAGS += -s WASM=1
}

HEADERS += \
    src/config/config.h \
    src/geo/geolookup.h \
    src/grinnodemanager/grinnodemanager.h



RESOURCES += \
    qml.qrc \
    res.qrc

#SUBMODULES
include(src/submodules/grin-common-api/grin-common-api.pri)
include(src/submodules/grin-node-api/grin-node-api.pri)

