QT = core network testlib
CONFIG += console testcase c++17
CONFIG -= app_bundle
SOURCES += tst_controller.cpp ../../src/grinnodemanager/grinnodemanager.cpp
HEADERS += ../../src/grinnodemanager/grinnodemanager.h
INCLUDEPATH += ../../src/grinnodemanager
