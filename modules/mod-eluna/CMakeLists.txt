set(LUA_VERSION "lua52" CACHE STRING "Lua version to use")
set_property(CACHE LUA_VERSION PROPERTY STRINGS luajit lua51 lua52 lua53 lua54)
MESSAGE(STATUS "Lua version: ${LUA_VERSION}")

# Avoid warning about DOWNLOAD_EXTRACT_TIMESTAMP in CMake 3.24:
if (CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
  cmake_policy(SET CMP0135 NEW)
endif()

option(LUA_STATIC "link lua statically" ON)
if (LUA_STATIC)
  MESSAGE(STATUS "Lua linking: static")
else()
  MESSAGE(STATUS "Lua linking: dynamic")
endif()

if (LUA_VERSION MATCHES "luajit")
  add_subdirectory(src/lualib/luajit)
else()
  add_subdirectory(src/lualib/lua)
endif()

# Collect all module source files
file(GLOB_RECURSE ALE_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h"
)

# Add the module sources to the project
foreach(SOURCE_FILE ${ALE_SOURCES})
  list(APPEND PRIVATE_SOURCES_MODULES ${SOURCE_FILE})
endforeach()

# Include directories
list(APPEND PUBLIC_INCLUDES
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/LuaEngine"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/lualib"
)
