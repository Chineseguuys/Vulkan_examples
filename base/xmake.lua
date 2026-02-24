-- prerequisites
-- add_requires("spdlog", {system = true})

set_project("base")
set_toolchains("gcc")

-- global definations

if is_mode("Debug") then
    set_symbols("debug")
    set_optimize("none")
    add_defines("DEBUG")
    set_strip("none")
    add_cxflags("-g")
    add_ldflags("-g")
end

target("base")
    set_kind("static")
    add_files("./*.cpp")
    add_includedirs("../external/ktx/include/")
    add_includedirs("../external/imgui/")
    add_includedirs("../external/imgui/backends/")
    add_includedirs("../external/spdlog/include/")
    add_includedirs("./", {public = true})
