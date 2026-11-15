#!/usr/bin/env python3
"""Expand a kickstart %packages section into a flat package list.

This mirrors what Anaconda does with the section:

  @^environment   the environment's groups, mandatory and default members
  @group          that group's mandatory and default members
  -@group         drop all of that group's default members
  -package        never select it (passed to dnf as an exclude, so weak
                  dependencies cannot drag it back either)
  package         select it

The result is used twice: to download the closure that becomes the embedded
repository of the offline ISO, and to write that ISO's explicit %packages list.
It is not used for the online ISO, where Anaconda resolves the section itself.
"""

import sys
import xml.etree.ElementTree as ET

# Packages that must survive an exclusion because a kept package requires them
# outright. Anaconda's negative entries mean "do not select"; dnf's --exclude
# means "make the transaction unresolvable". These are dropped from the exclude
# list so the two agree.
KEEP = {"colord", "cups-pk-helper", "libglvnd-gles"}


def tag(element):
    return element.tag.split("}")[-1]


def load_comps(path):
    groups, envs = {}, {}
    for element in ET.parse(path).getroot().iter():
        if tag(element) == "group":
            ident = element.find("id")
            name = ident.text if ident is not None else "?"
            groups[name] = [
                (req.text or "").strip()
                for req in element.iter()
                if tag(req) == "packagereq"
                and (req.get("type") or "default") in ("mandatory", "default")
            ]
        elif tag(element) == "environment":
            ident = element.find("id")
            name = ident.text if ident is not None else "?"
            envs[name] = [
                (group.text or "").strip()
                for group in element.iter()
                if tag(group) == "groupid"
            ]
    return groups, envs


def main():
    kickstart, comps, out_list, out_excludes = sys.argv[1:5]
    groups, envs = load_comps(comps)

    environment, add, drop_groups, excludes = None, [], set(), []
    in_packages = False
    for raw in open(kickstart):
        line = raw.strip()
        if line.startswith("%packages"):
            in_packages = True
            continue
        if in_packages and line == "%end":
            break
        if not in_packages or not line or line.startswith("#"):
            continue
        if line.startswith("@^"):
            environment = line[2:]
        elif line.startswith("-@"):
            drop_groups.add(line[2:])
        elif line.startswith("-"):
            excludes.append(line[1:])
        elif line.startswith("@"):
            add.extend(groups.get(line[1:], []))
        else:
            add.append(line)

    if environment is not None and environment not in envs:
        raise SystemExit(f"environment {environment!r} is not in comps")

    install = []
    if environment is not None:
        for group in envs[environment]:
            if group in drop_groups:
                continue
            install.extend(groups.get(group, []))
    install.extend(add)

    exclude_set = {package for package in excludes if package not in KEEP}
    install = [
        package for package in dict.fromkeys(install) if package not in exclude_set
    ]

    with open(out_list, "w") as handle:
        handle.write("\n".join(install) + "\n")
    with open(out_excludes, "w") as handle:
        handle.write("\n".join(sorted(exclude_set)) + "\n")
    print(
        f"environment={environment} packages={len(install)} excludes={len(exclude_set)}"
    )


if __name__ == "__main__":
    main()
