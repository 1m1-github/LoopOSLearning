"""
Learning is creating a Pkg once the code is good.
The Pkg is added to a local registry
"""
module LoopOSLearning

# todo handle fails

export update, newpkg, updatepkg, cppkg

using Pkg, TOML, LocalRegistry, GitHub
using Pkg.Types: PackageSpec, Context

ENV["JULIA_PKG_USE_CLI_GIT"] = true

const LOOPOSREGISTRY = "LoopOSRegistry"
const LOOPOSREGISTRYPATH = joinpath(DEPOT_PATH[1], "registries", LOOPOSREGISTRY)
const LOOPOSREGISTRYURL = "https://github.com/1m1-github/LoopOSRegistry.git"
const JULIACODEPATH = joinpath(DEPOT_PATH[1], "dev")
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
projecttoml(name) = joinpath(pkgdir(name), "Project.toml")
registrytoml() = joinpath(LOOPOSREGISTRYPATH, "Registry.toml")

"""
After adding or changing a Pkg, run `update` to have it loaded.
"""
function update()

end

"""
pkgs: Pkgs to be added (via name, url, path).
files: Files to be copied over.
"""
function newpkg(; name::String, files=String[], pkgs=String[], pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""), mvfiles=false)
    path = pkgdir(name)
    Pkg.generate(path) # todo cleanup on error
    changefiles(name, files, [], mvfiles ? mv : cp)
    changepkgs(name, pkgs, [])
    initversion(name)
    addcommitpush(path, new=true)
    newrepo(name, githubuser, githubauth)
    registerpkg(name, pushregistry)
end

"""
pkgs: new Pkgs to be added
rmpkgs: Pkgs to be removed
files: Files to be copied over
rmfiles: Files to be removed
"""
function updatepkg(; name::String, files=String[], pkgs=String[], rmfiles=String[], rmpkgs=String[], pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""), mvfiles=false)
    changefiles(name, files, rmfiles, mvfiles ? mv : cp)
    changepkgs(name, pkgs, rmpkgs)
    updateversion(name)
    path = pkgdir(name)
    addcommitpush(path)
    if hasremote(path)
        updateremote(path)
    else
        newrepo(name, githubuser, githubauth)
    end
    registerpkg(name, pushregistry)
end
# function rmpkg(; name::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    # rmdir(joinpath(JULIACODEPATH, name))
    # path = registrytoml()
    # registry = TOML.parsefile(path)
    # pkgkeys = filter(k -> registry["packages"][k]["name"] == name, keys(registry["packages"]))
    # if !isempty(pkgkeys)
        # pkgkey = only(pkgkeys)
        # rmdir(joinpath(LOOPOSREGISTRYPATH, registry["packages"][pkgkey]["path"]))
        # delete!(registry["packages"], pkgkey)
        # open(path, "w") do io
            # TOML.print(io, registry)
        # end
        # addcommitpush(LOOPOSREGISTRYPATH, push=pushregistry)
    # end
    # rmrepo(name, githubuser, githubauth)
# end
function cppkg(; name::String, newname::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
    files = readdir(joinpath(pkgdir(name), "src"), join=true)
    project = TOML.parsefile(projecttoml(name))
    pkgs = haskey(project, "deps") ? collect(keys(project["deps"])) : String[]
    newpkg(name=newname, files=files, pkgs=pkgs, pushregistry=pushregistry, githubuser=githubuser, githubauth=githubauth)
end
# function mvpkg(; name::String, newname::String, pushregistry=false, githubuser=get(ENV, "GITHUB_USER", ""), githubauth=get(ENV, "GITHUB_AUTH", ""))
#     cppkg(name=name, newname=newname, pushregistry=pushregistry, githubuser=githubuser, githubauth=githubauth)
#     rmpkg(name=name)
# end

# rmdir(path) = isdir(path) && rm(path, recursive=true)
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

function registerpkg(name, push=false)
    register(
        pkgdir(name),
        registry=LOOPOSREGISTRY,
        push=push,
    )
end

function changeversion(name, newversion)
    path = projecttoml(name)
    project = TOML.parsefile(path)
    version = VersionNumber(project["version"])
    project["version"] = string(newversion(version))
    open(path, "w") do file
        TOML.print(file, project)
    end
    project["version"]
end
initversion(name) = changeversion(name, _ -> v"1")
updateversion(name) = changeversion(name, v -> VersionNumber(v.major + 1))

isdirty(path) =
    cd(path) do
        !isempty(read(`git status --porcelain`))
    end
remoteurl(name, githubuser) = """git@github.com:$githubuser/$name.git"""
hasremote(path) =
    cd(path) do
        !isempty(readlines(`git remote`))
    end
addsetremote(name, githubuser, addset) =
    cd(pkgdir(name)) do
        run(`git remote $addset origin $(remoteurl(name, githubuser))`)
    end
addremote(name, githubuser) = addsetremote(name, githubuser, "add")
setremote(name, githubuser) = addsetremote(name, githubuser, "set-url")
updateremote(path) =
    cd(path) do
        run(`git push -f -u origin main`)
    end
function addcommitpush(path; new=false, push=false)
    cd(path) do
        new && run(`git init`)
        run(`git add .`)
        if new || isdirty(".")
            run(`git commit -m .`)
            push && run(`git push`)
        end
    end
end
function newrepo(name, githubuser, githubauth)
    if !isempty(githubuser) && !isempty(githubauth)
        create_repo(
            GitHub.owner(githubuser),
            name,
            auth=authenticate(githubauth),
        )
        addremote(name, githubuser)
        updateremote(pkgdir(name))
    end
end
remoteexists(name, githubuser) = try
        true, repo("$githubuser/$name")
    catch
        false, nothing
    end
function rmrepo(name, githubuser, githubauth)
    if !isempty(githubuser) && !isempty(githubauth)
        exists, repo = remoteexists(name, githubuser)
        exists && delete_repo(
            repo,
            auth=authenticate(githubauth),
        )
    end
end

end
