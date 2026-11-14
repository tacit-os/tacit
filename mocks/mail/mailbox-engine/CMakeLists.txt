cmake_minimum_required(VERSION 3.21)
project(TacitMailMailboxEngine LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Qml)
qt_policy(SET QTP0001 NEW)
set(CMAKE_AUTOMOC ON)
set(MAIL_QML_IMPORT_DIR "${CMAKE_BINARY_DIR}/qml" CACHE PATH "Tacit Mail QML module output")

qt_add_qml_module(TacitMailMailboxEngine
    URI Tacit.Mailbox
    OUTPUT_DIRECTORY "${MAIL_QML_IMPORT_DIR}/Tacit/Mailbox"
    SOURCES PreviewMailbox.h
)
set_target_properties(TacitMailMailboxEngine PROPERTIES AUTOMOC ON)
target_compile_features(TacitMailMailboxEngine PUBLIC cxx_std_17)
target_include_directories(TacitMailMailboxEngine PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(TacitMailMailboxEngine PUBLIC Qt6::Qml)
