"""
Learning is creating a Pkg once the code is good.
The Pkg is added to a local registry
"""
module LoopOSLearning

# todo handle fails

export newpkg, updatepkg, cppkg, mvpkg, rmpkg

using Pkg, TOML, LocalRegistry, GitHub
using Pkg.Types: PackageSpec, Context

ENV["JULIA_PKG_USE_CLI_GIT"] = true

const LOOPOSREGISTRY = "LoopOSRegistry"
const LOOPOSREGISTRYPATH = joinpath(DEPOT_PATH[1], "registries", LOOPOSREGISTRY)
const LOOPOSREGISTRYURL = "https://github.com/1m1-github/LoopOSRegistry.git"
const JULIACODEPATH = joinpath(DEPOT_PATH[1], "dev")
const PROJECTFILENAME = "Project.toml"
const LICENSEFILE = "LICENSE"
const LICENSE = """
Study it, use it, enjoy it.
Any one deriving value from this should share a fair amount >= 0.
"""
const READMEFILE = "README.md"
const README(name) = "# $name"
const GITIGNOREFILE = ".gitignore"
const GITIGNORE = """
Manifest.toml
.DS_Store
tmp*
"""

Pkg.Registry.add("General")
if !isdir(LOOPOSREGISTRYPATH)
    path = create_registry(LOOPOSREGISTRY, LOOPOSREGISTRYURL, push=false)
    write(joinpath(LOOPOSREGISTRYPATH, GITIGNOREFILE), GITIGNORE)
end
!isdir(JULIACODEPATH) && run(`mkdir $JULIACODEPATH`)

pkgdir(name) = joinpath(JULIACODEPATH, name)
projectfilepath(name) = joinpath(pkgdir(name), PROJECTFILENAME)
projectfilepath() = joinpath(LOOPOSREGISTRYPATH, PROJECTFILENAME)

gitC(name) = "git -C $(pkgname(name))"

"""
pkgs: Pkgs to be added (via name, url, path).
files: Files to be copied over.
"""
function newpkg(; name::String, files::Vector{String}, pkgs::Vector{String}=String[], pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""), mvfiles=false)
    Pkg.generate(pkgdir(name)) # todo cleanup on error
    changefiles(name, files, [], mvfiles ? mv : cp)
    changepkgs(name, pkgs, [])
    initversion(name)
    newcommit(name)
    newrepo(name, githubuser, githubauth)
    registerpkg(name, pushregistry)
end

"""
pkgs: new Pkgs to be added
rmpkgs: Pkgs to be removed
files: Files to be copied over
rmfiles: Files to be removed
"""
function updatepkg(; name::String, files::Vector{String}=String[], pkgs::Vector{String}=String[], rmfiles::Vector{String}=String[], rmpkgs::Vector{String}=String[], pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""), mvfiles=false)
    changefiles(name, files, rmfiles, mvfiles ? mv : cp)
    changepkgs(name, pkgs, rmpkgs)
    updateversion(name)
    commit(name)
    if hasremote(name)
        updateremote(name)
    else
        newrepo(name, githubuser, githubauth)
    end
    registerpkg(name, pushregistry)
end

function rmpkg(; name::String)
    projectfile = TOML.parsefile(projectfilepath())
    delete!(projectfile, name)
    open(projectfilepath(), "w") do io
        TOML.print(io, projectfile)
    end
    rm(joinpath(LOOPOSREGISTRYPATH, name), recursive=true)
    rm(joinpath(JULIACODEPATH, name), recursive=true)
end
function cppkg(; name::String, newname::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    files = readdir(joinpath(pkgdir(name), "src"))
    projectfile = TOML.parsefile(projectfilepath(name))
    pkgs = collect(keys(projectfile["deps"]))
    newpkg(name=newname, files=files, pkgs=pkgs, pushregistry=pushregistry, githubuser=githubuser, githubauth=githubauth)
end
function mvpkg(; name::String, newname::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    cppkg(name=name, newname=newname, pushregistry=pushregistry, githubuser=githubuser, githubauth=githubauth)
    rmpkg(name=name)
end

function addfile(name, file, content)
    file = joinpath(pkgdir(name), file)
    !isfile(file) && write(file, content)
end
srcfile(name, file) = joinpath(pkgdir(name), "src", basename(file))
function changefiles(name, files, rmfiles, cpmv)
    addfile(name, LICENSEFILE, LICENSE)
    addfile(name, GITIGNOREFILE, GITIGNORE)
    addfile(name, READMEFILE, README(name))
    for file = files
        cpmv(file, srcfile(name, file), force=true)
    end
    for file = rmfiles
        rm(srcfile(name, file))
    end
end

function updatecompat(pkg)
    ctx = Pkg.Types.Context()
    pkgname = pkg
    if startswith(pkg, "http")
        for (_, entry) in ctx.env.manifest
            entry.repo.source == pkg && (pkgname = entry.name)
        end
    end
    version = v"0"
    for (_, entry) in ctx.env.manifest
        entry.name == pkgname && (version = entry.version)
    end
    Pkg.compat(pkgname, ">=$version")
end

function changepkg(pkg, f)
    if startswith(pkg, "http")
        f(url=pkg)
    elseif ispath(pkg)
        f(path=pkg)
    else
        f(pkg)
    end
end

function changepkgs(name, pkgs, rmpkgs)
    cd(pkgdir(name)) do
        oldenv = Base.active_project()
        Pkg.activate(".")
        for pkg = pkgs
            changepkg(pkg, Pkg.add)
            updatecompat(pkg)
        end
        for pkg = rmpkgs
            changepkg(pkg, Pkg.rm)
        end
        Pkg.activate(oldenv)
    end
end

function newcommit(name)
    run(`$(gitC(name)) init`)
    commit(name)
end
function commit(name)
    run(`$(gitC(name)) add .`)
    run(`$(gitC(name)) commit -m .`)
end

function registerpkg(name, push=false)
    dir = pkgdir(name)
    register(
        dir;
        registry=LOOPOSREGISTRY,
        push=push,
    )
end

function changeversion(name, newversion)
    path = projectfilepath(name)
    projectfile = TOML.parsefile(path)
    version = VersionNumber(projectfile["version"])
    projectfile["version"] = string(newversion(version))
    open(path, "w") do file
        TOML.print(file, projectfile)
    end
    projectfile["version"]
end
initversion(name) = changeversion(name, _ -> v"1")
updateversion(name) = changeversion(name, v -> VersionNumber(v.major + 1))

remoteurl(name, githubuser) = """git@github.com:$githubuser/$name.git"""
hasremote(name) = !isempty(readlines(`$(gitC(name)) remote`))
addsetremote(name, githubuser, addset) = run(`$(gitC(name)) remote $addset origin $(remoteurl(name, githubuser))`)
addremote(name, githubuser) = addsetremote(name, githubuser, "add")
setremote(name, githubuser) = addsetremote(name, githubuser, "set-url")
updateremote(name) = run(`$(gitC(name)) push -f -u origin main`)
function newrepo(name, githubuser, githubauth)
    if !isempty(githubuser) && !isempty(githubauth)
        create_repo(
            GitHub.owner(githubuser),
            name;
            auth=authenticate(githubauth),
        )
        addremote(name, githubuser)
        updateremote(name)
    end
end

end
