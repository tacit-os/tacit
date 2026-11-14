cmake_minimum_required(VERSION 3.21)
project(TacitMailMacPreview LANGUAGES CXX OBJCXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick QuickControls2 Widgets WebEngineQuick)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

qt_standard_project_setup()
qt_add_executable(TacitMailMacPreview MACOSX_BUNDLE main.cpp MacWindowMaterial.mm)
target_compile_features(TacitMailMacPreview PRIVATE cxx_std_17)
target_link_libraries(TacitMailMacPreview PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Widgets Qt6::WebEngineQuick)
add_subdirectory(../html-engine html-engine)
add_subdirectory(../editor-engine editor-engine)
add_subdirectory(../mailbox-engine mailbox-engine)
target_link_libraries(TacitMailMacPreview PRIVATE TacitMailMailboxEngine)
add_dependencies(TacitMailMacPreview TacitMailMailboxEngineplugin)
add_dependencies(TacitMailMacPreview TacitMailHtmlEngineplugin TacitMailEditorEngineplugin)
find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
target_link_libraries(TacitMailMacPreview PRIVATE "${APPKIT_FRAMEWORK}" "${QUARTZCORE_FRAMEWORK}")
target_compile_definitions(TacitMailMacPreview PRIVATE
    PREVIEW_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
    PREVIEW_IMPORT_DIR="${CMAKE_CURRENT_BINARY_DIR}/qml"
)
set_target_properties(TacitMailMacPreview PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER co.tacitos.mail.local-preview
    MACOSX_BUNDLE_BUNDLE_NAME "Tacit Mail Preview"
)

add_custom_target(stagePreview
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py"
        "${CMAKE_CURRENT_BINARY_DIR}/qml"
    VERBATIM
)
add_dependencies(TacitMailMacPreview stagePreview)


find_package(Qt6 6.8 QUIET COMPONENTS QuickTest)
if(TARGET Qt6::QuickTest)
    qt_add_executable(TacitMailIntegrationTest ../tests/maild_frontend_main.cpp)
    target_link_libraries(TacitMailIntegrationTest PRIVATE Qt6::QuickTest Qt6::WebEngineQuick TacitMailMailboxEngine)
    target_include_directories(TacitMailIntegrationTest PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    add_dependencies(TacitMailIntegrationTest TacitMailMacPreview)
endif()
