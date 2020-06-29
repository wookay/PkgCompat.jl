#!/usr/bin/env julia

# based on https://github.com/JuliaLang/Pkg.jl/blob/v1.3.0/bin/gen_project.jl

import Pkg
import Pkg.Types: VersionSpec, VersionRange, VersionBound, semver_spec
import Base: thismajor, thisminor, thispatch, nextmajor, nextminor, nextpatch

const STDLIBS = [
    "Base64"
    "CRC32c"
    "Dates"
    "DelimitedFiles"
    "Distributed"
    "FileWatching"
    "Future"
    "InteractiveUtils"
    "Libdl"
    "LibGit2"
    "LinearAlgebra"
    "Logging"
    "Markdown"
    "Mmap"
    "Pkg"
    "Printf"
    "Profile"
    "Random"
    "REPL"
    "Serialization"
    "SHA"
    "SharedArrays"
    "Sockets"
    "SparseArrays"
    "Statistics"
    "SuiteSparse"
    "Test"
    "Unicode"
    "UUIDs"
]

function uuid(name::AbstractString)
    ctx = Pkg.Types.Context() 
    uuid = Pkg.Types.registered_uuid(ctx, name)
    if uuid === nothing
        eval(Expr(:using, Expr(:., Symbol(name))))
        pkg = Base.identify_package(name)
        return string(pkg.uuid)
    else
        return string(uuid)
    end
end

function uses(repo::AbstractString, lib::AbstractString)
    pattern = string(raw"\b(import|using)\s+((\w|\.)+\s*,\s*)*", lib, raw"\b")
    success(`git -C $repo grep -Eq $pattern -- '*.jl'`)
end

function semver(intervals)
    spec = String[]
    for ival in intervals
        if ival.upper == v"∞"
            push!(spec, "≥ $(thispatch(ival.lower))")
        else
            lo, hi = ival.lower, ival.upper
            if lo.major < hi.major
                push!(spec, "^$(lo.major).$(lo.minor).$(lo.patch)")
                for major = lo.major+1:hi.major-1
                    push!(spec, "~$major")
                end
                for minor = 0:hi.minor-1
                    push!(spec, "~$(hi.major).$minor")
                end
                for patch = 0:hi.patch-1
                    push!(spec, "=$(hi.major).$(hi.minor).$patch")
                end
            elseif lo.minor < hi.minor
                push!(spec, "~$(lo.major).$(lo.minor).$(lo.patch)")
                for minor = lo.minor+1:hi.minor-1
                    push!(spec, "~$(hi.major).$minor")
                end
                for patch = 0:hi.patch-1
                    push!(spec, "=$(hi.major).$(hi.minor).$patch")
                end
            else
                for patch = lo.patch:hi.patch-1
                    push!(spec, "=$(hi.major).$(hi.minor).$patch")
                end
            end
        end
    end
    return join(spec, ", ")
end

if !isempty(ARGS) && ARGS[1] == "-f"
    const force = true
    popfirst!(ARGS)
else
    const force = false
end
isempty(ARGS) && (push!(ARGS, pwd()))

for arg in ARGS
    dir = abspath(expanduser(arg))
    isdir(dir) ||
        error("$arg does not appear to be a package (not a directory)")

    name = basename(dir)
    if isempty(name)
        dir = dirname(dir)
        name = basename(dir)
    end
    endswith(name, ".jl") && (name = chop(name, tail=3))

    project_file = joinpath(dir, "Project.toml")
    !force && isfile(project_file) &&
        error("$arg already has a project file")

    require_file = joinpath(dir, "REQUIRE")
    isfile(require_file) ||
        error("$arg does not appear to be a package (no REQUIRE file)")

    project = Dict(
        "name" => name,
        "uuid" => uuid(name),
        "deps" => Dict{String,String}(),
        "compat" => Dict{String,String}(),
        "extras" => Dict{String,String}(),
    )

    test_require_file = joinpath(dir, "test", "REQUIRE")

    for (srcdir, section) in (("src" => "deps"), ("test", "extras"))
        for stdlib in STDLIBS
            if uses(joinpath(dir, srcdir), stdlib)
                project[section][stdlib] = uuid(stdlib)
            end
        end
    end

    if !isempty(project["extras"])
        project["targets"] = Dict("test" => collect(keys(project["extras"])))
    end

    println(stderr, "Generating project file for $name: $project_file")
    open(project_file, "w") do io
        Pkg.TOML.print(io, project, sorted=true)
    end
    project = Pkg.Types.read_project(project_file)
    Pkg.Types.write_project(project, project_file)
end
