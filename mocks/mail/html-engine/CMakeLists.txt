cmake_minimum_required(VERSION 3.21)
project(TacitMailHtmlEngine LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Qml WebEngineCore WebEngineQuick)
qt_policy(SET QTP0001 NEW)
set(CMAKE_AUTOMOC ON)

set(MAIL_QML_IMPORT_DIR "${CMAKE_BINARY_DIR}/qml" CACHE PATH "Tacit Mail QML module output")
qt_add_qml_module(TacitMailHtmlEngine
    URI Tacit.MailHtml
    OUTPUT_DIRECTORY "${MAIL_QML_IMPORT_DIR}/Tacit/MailHtml"
    SOURCES mailwebprofile.h
)
set_target_properties(TacitMailHtmlEngine PROPERTIES AUTOMOC ON)
target_compile_features(TacitMailHtmlEngine PRIVATE cxx_std_17)
target_link_libraries(TacitMailHtmlEngine PRIVATE Qt6::Qml Qt6::WebEngineCore Qt6::WebEngineQuick)
