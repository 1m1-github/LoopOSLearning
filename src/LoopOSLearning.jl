"""
Learning is creating a Pkg once the code is good.
The Pkg is added to a local registry
"""
module LoopOSLearning

# todo handle fails

export newpkg, updatepkg

using Pkg, TOML, LocalRegistry, GitHub
using Pkg.Types: PackageSpec, Context

ENV["JULIA_PKG_USE_CLI_GIT"] = true

const LOOPOSREGISTRY = "LoopOSRegistry"
const LOOPOSREGISTRYPATH = joinpath(DEPOT_PATH[1], "registries", LOOPOSREGISTRY)
const LOOPOSREGISTRYURL = "https://github.com/1m1-github/LoopOSRegistry.git"
const JULIACODEPATH = joinpath(DEPOT_PATH[1], "dev")
const PROJECTFILE = "Project.toml"
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

"""
pkgs: Pkgs to be added (via name, url, path).
files: Files to be copied over.
"""
function newpkg(; name::String, files::Vector{String}, pkgs::Vector{String}=String[], pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    Pkg.generate(pkgdir(name))
    changefiles(name, files, [])
    changepkgs(name, pkgs, [])
    commitpkg(name)
    newrepo(name, githubuser, githubauth)
    registerpkg(name, pushregistry)
end

"""
pkgs: new Pkgs to be added
rmpkgs: Pkgs to be removed
files: Files to be copied over
rmfiles: Files to be removed
"""
function updatepkg(; name::String, files::Vector{String}=String[], pkgs::Vector{String}=String[], rmfiles::Vector{String}=String[], rmpkgs::Vector{String}=String[], pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    changefiles(name, files, rmfiles)
    changepkgs(name, pkgs, rmpkgs)
    commitpkg(name)
    if hasremote(name)
        updateremote(name)
    else
        newrepo(name, githubuser, githubauth)
    end
    registerpkg(name, pushregistry)
end

function addfile(name, file, content)
    file = joinpath(pkgdir(name), file)
    !isfile(file) && write(file, content)
end
srcfile(name, file) = joinpath(pkgdir(name), "src", basename(file))
function changefiles(name, files, rmfiles)
    addfile(name, LICENSEFILE, LICENSE)
    addfile(name, GITIGNOREFILE, GITIGNORE)
    addfile(name, READMEFILE, README(name))
    for file = files
        cp(file, srcfile(name, file), force=true)
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
        Pkg.activate(".")
        for pkg = pkgs
            changepkg(pkg, Pkg.add)
            updatecompat(pkg)
        end
        for pkg = rmpkgs
            changepkg(pkg, Pkg.rm)
        end
    end
    Pkg.activate(".")
end

function commitpkg(name)
    cd(pkgdir(name)) do
        commitmessage = if isdir(".git")
            updateversion()
            "update"
        else
            run(`git init`)
            initversion()
            "."
        end
        run(`git add .`)
        run(`git commit -m $commitmessage`)
    end
end

function registerpkg(name, push=false)
    dir = pkgdir(name)
    register(
        dir;
        registry=LOOPOSREGISTRY,
        push=push,
    )
end

function changeversion(newversion)
    projectfile = TOML.parsefile(PROJECTFILE)
    version = VersionNumber(projectfile["version"])
    projectfile["version"] = string(newversion(version))
    open(PROJECTFILE, "w") do file
        TOML.print(file, projectfile)
    end
    projectfile["version"]
end
initversion() = changeversion(_ -> v"1")
updateversion() = changeversion(v -> VersionNumber(v.major + 1))

remoteurl(name, githubuser) = """git@github.com:$githubuser/$name.git"""
hasremote(name) = cd(pkgdir(name)) do
        !isempty(readlines(`git remote`))
    end
addsetremote(name, githubuser, addset) =
    cd(pkgdir(name)) do
        run(`git remote $addset origin $(remoteurl(name, githubuser))`)
    end
addremote(name, githubuser) = addsetremote(name, githubuser, "add")
setremote(name, githubuser) = addsetremote(name, githubuser, "set-url")
updateremote(name) =
    cd(pkgdir(name)) do
        run(`git push -f -u origin main`)
    end
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
