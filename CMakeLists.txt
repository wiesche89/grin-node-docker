cmake_minimum_required(VERSION 3.21)

project(grin_node_docker_wasm LANGUAGES CXX)

# Qt-Module aus dem .pro:
# QT += qml quick gui core charts quickcontrols2
find_package(Qt6 6.9 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    Charts
    QuickControls2
    Network
)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# WICHTIG: Qt-Auto-Features aktivieren
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Alle Quellen & Header unter src/
file(GLOB_RECURSE PROJECT_SOURCES
    "src/*.cpp"
    "src/*.c"
)
file(GLOB_RECURSE PROJECT_HEADERS
    "src/*.h"
    "src/*.hpp"
)

# Ressourcen aus dem .pro
set(PROJECT_RESOURCES
    qml.qrc
    res.qrc
)

qt_add_executable(grin_node_docker
    ${PROJECT_SOURCES}
    ${PROJECT_HEADERS}
    ${PROJECT_RESOURCES}
)

set_target_properties(grin_node_docker PROPERTIES
    OUTPUT_NAME "grin-node-docker"
)

# Include-Pfade inkl. Submodule
target_include_directories(grin_node_docker PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/config
    ${CMAKE_CURRENT_SOURCE_DIR}/src/geo
    ${CMAKE_CURRENT_SOURCE_DIR}/src/grinnodemanager

    # grin-common-api
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-common-api/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-common-api/src/attributes
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-common-api/src/util

    # grin-node-api
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-node-api/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-node-api/src/attributes
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-node-api/src/foreign
    ${CMAKE_CURRENT_SOURCE_DIR}/src/submodules/grin-node-api/src/owner
)

target_link_libraries(grin_node_docker PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::Charts
    Qt6::QuickControls2
    Qt6::Network
)

# WASM-spezifisches Memory-Flag (entspricht deinem .pro: TOTAL_MEMORY=32MB)
if(EMSCRIPTEN)
    target_link_options(grin_node_docker PRIVATE
        "SHELL:-s INITIAL_MEMORY=33554432"
    )
endif()
