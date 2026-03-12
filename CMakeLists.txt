cmake_minimum_required(VERSION 3.23)

project(inventory_injector_known_spells_skse VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE AND DEFINED ENV{VCPKG_ROOT})
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" CACHE STRING "Vcpkg toolchain")
endif()

find_package(CommonLibSSE CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(jsoncpp CONFIG REQUIRED)

set(PLUGIN_SOURCES
    src/main.cpp
)

add_commonlibsse_plugin(${PROJECT_NAME} SOURCES ${PLUGIN_SOURCES})
target_compile_features(${PROJECT_NAME} PRIVATE cxx_std_23)
target_precompile_headers(${PROJECT_NAME} PRIVATE PCH.h)

target_include_directories(${PROJECT_NAME}
    PRIVATE
    ${CMAKE_SOURCE_DIR}
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/external/diii
)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
    spdlog::spdlog
    JsonCpp::JsonCpp
)

if(EXISTS "${CMAKE_SOURCE_DIR}/external/diii/DIII_API.h")
    target_compile_definitions(${PROJECT_NAME} PRIVATE HAS_DIII_API=1)
else()
    target_compile_definitions(${PROJECT_NAME} PRIVATE HAS_DIII_API=0)
endif()

if(DEFINED ENV{SKYRIM_MODS_FOLDER} AND IS_DIRECTORY "$ENV{SKYRIM_MODS_FOLDER}")
    set(DEPLOY_ROOT "$ENV{SKYRIM_MODS_FOLDER}/${PROJECT_NAME}")
elseif(DEFINED ENV{SKYRIM_FOLDER} AND IS_DIRECTORY "$ENV{SKYRIM_FOLDER}/Data")
    set(DEPLOY_ROOT "$ENV{SKYRIM_FOLDER}/Data")
endif()

if(DEFINED DEPLOY_ROOT)
    set(DLL_FOLDER "${DEPLOY_ROOT}/SKSE/Plugins")
    message(STATUS "Deploy folder: ${DLL_FOLDER}")

    add_custom_command(
        TARGET ${PROJECT_NAME}
        POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${DLL_FOLDER}"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "$<TARGET_FILE:${PROJECT_NAME}>"
            "${DLL_FOLDER}/$<TARGET_FILE_NAME:${PROJECT_NAME}>"
        VERBATIM
    )

    if(MSVC)
        add_custom_command(
            TARGET ${PROJECT_NAME}
            POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_PDB_FILE:${PROJECT_NAME}>"
                "${DLL_FOLDER}/$<TARGET_PDB_FILE_NAME:${PROJECT_NAME}>"
            COMMAND_EXPAND_LISTS
            VERBATIM
        )
    endif()
endif()
