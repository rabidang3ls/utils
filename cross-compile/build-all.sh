#!/bin/bash
ALL_ARCH=( linux-x86 linux-x64 )
BASE=$(basename $(cd $1 && pwd -P))

if [[ $# -ne 1 ]]; then echo "Usage: $0 <directory with makefile>"; exit 0; fi

if [[ ! -d dockcross ]]; then echo "Install dockcross: $ git clone https://github.com/dockcross/dockcross dockcross"; exit 1; fi

# DO all the arch's
for arch in "${ALL_ARCH[@]}"; do
  dest="${BASE}.${arch}"

  rm -rf "$dest"
  cp -rv "$1" "$dest"

  # Build docker helper script
  docker run --rm dockcross/$arch >dockcross-$arch
  chmod +x dockcross-$arch

  # Build project
  ./dockcross-$arch bash -c "cd $dest; make clean; make; cd .."
done
