cmake_minimum_required(VERSION 3.21)
project(TacitMailEditorEngine LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Quick Qml)
qt_policy(SET QTP0001 NEW)
set(CMAKE_AUTOMOC ON)
set(MAIL_QML_IMPORT_DIR "${CMAKE_BINARY_DIR}/qml" CACHE PATH "Tacit Mail QML module output")

qt_add_qml_module(TacitMailEditorEngine
    URI Tacit.MailEditor
    OUTPUT_DIRECTORY "${MAIL_QML_IMPORT_DIR}/Tacit/MailEditor"
    SOURCES mailrichtext.h
)
set_target_properties(TacitMailEditorEngine PROPERTIES AUTOMOC ON)
target_compile_features(TacitMailEditorEngine PRIVATE cxx_std_17)
target_link_libraries(TacitMailEditorEngine PRIVATE Qt6::Quick Qt6::Qml)
