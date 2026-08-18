#!/usr/bin/env python3
"""Regenerate python-packages.nix for the ESP-IDF environment.

The pins come from the ESP-IDF checkout itself: the requirements list in
tools/requirements/requirements.core.txt and the matching constraints
file at https://dl.espressif.com/dl/esp-idf/espidf.constraints.<ver>.txt
(see esp-idf.nix for how the result is used).

Only packages that nixpkgs does not provide at a compatible version are
pinned here; the rest come from nixpkgs' pythonPackages.

Usage:
    ./update-python-packages.py [esp-idf-rev] > python-packages.nix
"""
import base64
import hashlib
import json
import re
import sys
import urllib.request

# ESP-IDF versions are released as v<major>.<minor>.<patch>; the
# constraints file is named after the first two components.
DEFAULT_REV = "v6.0.2"

# pypi distribution name -> nix attribute name, for the packages pinned
# here because nixpkgs does not provide them (or provides an incompatible
# version). Keep this in sync with the requirement list in esp-idf.nix.
CUSTOM = {
    "esp-pylib": "esp-pylib",
    "idf-component-manager": "idf-component-manager",
    "esp-coredump": "esp-coredump",
    "esptool": "esptool",
    "esp-idf-kconfig": "esp-idf-kconfig",
    "esp-idf-monitor": "esp-idf-monitor",
    "esp-idf-nvs-partition-gen": "esp-idf-nvs-partition-gen",
    "esp-idf-panic-decoder": "esp-idf-panic-decoder",
    "pyclang": "pyclang",
    "freertos-gdb": "freertos_gdb",
}

# pypi distribution name -> (github org/repo, latest-tag URL pattern) for
# packages that are not published on PyPI.
GITHUB_SRC = {
    "esp-idf-diag": ("espressif/esp-idf-diag", "https://github.com/{repo}/archive/refs/tags/{tag}.tar.gz"),
}

# Undeclared runtime requirements found empirically (the upstream
# dependency declarations are incomplete); see the history of
# mirrexagon/nixpkgs-esp-dev pkgs/esp-idf/python-packages.nix.
EXTRA_DEPS = {
    "esp-idf-kconfig": ["intelhex", "rich"],
}

# pypi distribution name -> nixpkgs pythonPackages attribute for the
# non-pinned dependencies referenced in requires_dist.
ATTR_MAP = {
    "pyyaml": "pyyaml",
    "ruamel.yaml": "ruamel-yaml",
    "typing-extensions": "typing-extensions",
    "rich-click": "rich-click",
    "rich_click": "rich-click",
    "esp-idf-size": "esp-idf-size",
    "idf-component-manager": "idf-component-manager",
    "esp-coredump": "esp-coredump",
    "esptool": "esptool",
    "freertos-gdb": "freertos_gdb",
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "curl/8.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def constraints_url(rev):
    mm = ".".join(rev.removeprefix("v").split(".")[:2])
    return f"https://dl.espressif.com/dl/esp-idf/espidf.constraints.v{mm}.txt"


def parse_constraints(text):
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "--" in line:  # e.g. "--only-binary cryptography"
            continue
        m = re.match(r"([A-Za-z0-9_.-]+)\s*(.*)", line)
        if m:
            out[m.group(1).lower()] = m.group(2).strip()
    return out


def satisfies(version, spec):
    """Minimal version-specifier handling for the constraints file:
    ==, >=, <, ~= and comma-separated combinations. Prereleases are only
    matched when the spec asks for them explicitly (e.g. >=5.3.0.dev0)."""
    def parts(v):
        return [int(p) for p in re.findall(r"\d+", v)[:3]]

    def as_tuple(v):
        v = re.match(r"(\d+(\.\d+)*)", v).group(1)
        return tuple(parts(v))

    def is_prerelease(v):
        return bool(re.search(r"[a-zA-Z]", v))

    vp, vpr = as_tuple(version), is_prerelease(version)
    for clause in spec.split(","):
        clause = clause.strip()
        if not clause:
            continue
        m = re.match(r"(~=|==|>=|<=|>|<)\s*(.*)", clause)
        if not m:
            return False
        op, target = m.group(1), m.group(2).strip()
        tp = as_tuple(target)
        if op == "==":
            if not re.match(r"\d+(\.\d+)*$", target) and re.search(r"[a-zA-Z]", target):
                if version != target:
                    return False
            elif vp != tp:
                return False
        elif op == "~=":
            # ~=X.Y.Z means >=X.Y.Z, ==X.Y.*
            t = parts(target)
            if not (len(t) >= 2 and vp[:2] == tuple(t[:2])):
                return False
            if len(t) == 3 and vp < tuple(t):
                return False
        elif op == ">=":
            if vpr and not is_prerelease(target):
                return False
            if vp < tp:
                return False
        elif op == "<=":
            if vp > tp:
                return False
        elif op == ">":
            if vp <= tp:
                return False
        elif op == "<":
            if vp >= tp:
                return False
    return True


def latest_satisfying(dist, spec):
    data = json.loads(get(f"https://pypi.org/pypi/{dist}/json"))
    candidates = []
    for version, files in data["releases"].items():
        if not files:  # yanked or deleted release
            continue
        if not satisfies(version, spec):
            continue
        candidates.append(version)
    # Sort as tuples of ints, stable-ish ordering by version parts.
    def key(v):
        return [int(p) for p in re.findall(r"\d+", v)]
    return max(candidates, key=key)


def sdist_sha256(dist, version):
    data = json.loads(get(f"https://pypi.org/pypi/{dist}/{version}/json"))
    for url in data["urls"]:
        if url["packagetype"] == "sdist":
            sha = url.get("sha256")
            if sha is None:  # ancient uploads lack digests; hash the file
                sha = hashlib.sha256(get(url["url"])).hexdigest()
            return sha, url["url"]
    raise SystemExit(f"no sdist for {dist} {version}")


def nix_attr(dist_name):
    if dist_name in CUSTOM:
        return CUSTOM[dist_name]
    if dist_name in ATTR_MAP:
        return ATTR_MAP[dist_name]
    return dist_name  # assume nixpkgs attr == pypi dist name


def map_deps(requires_dist):
    """requires_dist entries -> nix propagatedBuildInputs names. Entries
    with environment markers are skipped (the Nix build is Linux-only)."""
    deps, skipped = [], []
    for entry in requires_dist or []:
        if ";" in entry:
            skipped.append(entry.split(";")[0].strip())
            continue
        name = entry.split("[")[0].split(">")[0].split("=")[0].split("<")[0].split("~")[0].split("!")[0].strip().lower()
        if not name:
            continue
        attr = nix_attr(name)
        if attr not in deps:
            deps.append(attr)
    return deps, skipped


def sri(hex_hash):
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_hash)).decode()


def emit(dist, attr, version, sha, deps, url):
    # Use the exact sdist URL from PyPI rather than fetchPypi: espressif
    # uploads sdists with underscore filenames (esp_idf_nvs_partition_gen-0.1.9.tar.gz)
    # that fetchPypi's pname+version URL construction cannot express.
    print(f"  {attr} = buildPythonPackage rec {{")
    print(f'    pname = "{dist}";')
    print(f'    version = "{version}";')
    print("    pyproject = true;")
    print("")
    print("    build-system = [")
    print("      setuptools")
    print("    ];")
    print("")
    print("    src = fetchurl {")
    print(f'      url = "{url}";')
    print(f'      sha256 = "{sri(sha)}";')
    print("    };")
    print("")
    print("    doCheck = false;")
    print("")
    if deps:
        print("    propagatedBuildInputs = [")
        for d in deps:
            print(f"      {d}")
        print("    ];")
        print("")
    print("    meta = {")
    print(f'      homepage = "https://pypi.org/project/{dist}/";')
    print("    };")
    print("  };")
    print("")


def main():
    rev = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_REV
    reqs = get(f"https://raw.githubusercontent.com/espressif/esp-idf/{rev}/tools/requirements/requirements.core.txt").decode()
    constraints = parse_constraints(get(constraints_url(rev)).decode())

    print(f"# Generated by update-python-packages.py {rev} — do not edit by hand.")
    print("#")
    print("# Pins are resolved from")
    print(f"#   tools/requirements/requirements.core.txt @ {rev}")
    print(f"#   {constraints_url(rev)}")
    print("# plus per-package metadata (dependencies, sdist hashes) from PyPI.")
    print("{")
    print("  fetchPypi,")
    print("  fetchurl,")
    print("  pythonPackages,")
    print("}:")
    print("with pythonPackages;")
    print("rec {")

    emitted = set()

    def emit_github(dist):
        repo, urlpat = GITHUB_SRC[dist]
        tags = json.loads(get(f"https://api.github.com/repos/{repo}/tags"))
        tag = tags[0]["name"]
        url = urlpat.format(repo=repo, tag=tag)
        sha = hashlib.sha256(get(url)).hexdigest()
        attr = dist
        print(f"  {attr} = buildPythonPackage {{")
        print(f'    pname = "{dist}";')
        print(f'    version = "{tag.removeprefix("v")}";')
        print("    pyproject = true;")
        print("")
        print("    src = fetchurl {")
        print(f'      url = "{url}";')
        print(f'      sha256 = "{sri(sha)}";')
        print("    };")
        print("")
        print("    build-system = [")
        print("      setuptools")
        print("    ];")
        print("")
        print("    doCheck = false;")
        print("")
        extra = EXTRA_DEPS.get(attr, [])
        info = json.loads(get(f"https://pypi.org/pypi/{attr}/json"))["info"]
        deps, _ = map_deps(info.get("requires_dist"))
        deps = deps + [d for d in extra if d not in deps]
        if deps:
            print("    propagatedBuildInputs = [")
            for d in deps:
                print(f"      {d}")
            print("    ];")
            print("")
        print("    meta = {")
        print(f'      homepage = "https://github.com/{repo}";')
        print("    };")
        print("  };")
        print("")

    def emit_pypi(dist):
        spec = constraints.get(dist, "")
        version = latest_satisfying(dist, spec)
        sha, url = sdist_sha256(dist, version)
        info = json.loads(get(f"https://pypi.org/pypi/{dist}/{version}/json"))["info"]
        deps, skipped = map_deps(info.get("requires_dist"))
        extra = EXTRA_DEPS.get(CUSTOM[dist], [])
        deps = deps + [d for d in extra if d not in deps]
        for s in skipped:
            print(f"    # skipped marker-gated dep: {s}", file=sys.stderr)
        emit(dist, CUSTOM[dist], version, sha, deps, url)

    for line in reqs.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        dist = line.split(">")[0].split("<")[0].split("=")[0].split("~")[0].split("!")[0].split("[")[0].strip().lower()
        dist = dist.replace("_", "-")
        if dist in GITHUB_SRC:
            emit_github(dist)
            emitted.add(dist)
            continue
        if dist not in CUSTOM:
            continue
        emit_pypi(dist)
        emitted.add(dist)

    # Transitive-only pins (dependencies of the packages above that nixpkgs
    # does not provide), pinned at their latest release.
    for dist in CUSTOM:
        if dist not in emitted:
            emit_pypi(dist)
            emitted.add(dist)

    print("}")


if __name__ == "__main__":
    main()
