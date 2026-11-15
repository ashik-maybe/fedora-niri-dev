#!/usr/bin/env python3
"""Write the kickstart used by the offline ISO.

Two things change, and nothing else:

  * the repository list becomes the package tree embedded on the ISO, and
  * %packages becomes the explicit list that tree was downloaded for.

Everything else is shared with the online image, including %post and the
verification gates, so the two ISOs cannot drift apart in behaviour.
"""

import sys

kickstart, package_list, output = sys.argv[1:4]

packages = [line.strip() for line in open(package_list) if line.strip()]
if not packages:
    raise SystemExit(f"{package_list} is empty")

source = open(kickstart).read().splitlines()
result = []
inside_packages = False
repo_written = False

for line in source:
    stripped = line.strip()

    if stripped.startswith("%packages"):
        # Keep the section's options (`--ignoremissing` and friends) so the two
        # ISOs differ only in where the packages come from.
        result.append(stripped)
        result.extend(packages)
        inside_packages = True
        continue

    if inside_packages:
        if stripped == "%end":
            result.append("%end")
            inside_packages = False
        continue

    if stripped.startswith("repo "):
        # Every remote repository is replaced by the one on the ISO. The
        # installer only needs this; the installed system gets its repository
        # files from the shipped packages and repo files in %post.
        if not repo_written:
            result.append(
                'repo --name="ks-offline" --baseurl="file:///run/install/repo/packages"'
            )
            repo_written = True
        continue

    result.append(line)

if inside_packages:
    raise SystemExit("unterminated %packages section")
if not repo_written:
    raise SystemExit("no repo line to replace")

with open(output, "w") as handle:
    handle.write("\n".join(result) + "\n")

print(f"wrote {output}: {len(packages)} explicit packages, local repository only")
