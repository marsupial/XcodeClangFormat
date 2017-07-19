#!/usr/bin/env bash

set -e
set -o pipefail
set -u

LLVM_VERSION=4.0.1
LLVM_HASH=191ad414d37fc16626bb289e5359f0eca53ab03bb7200b279d3f98a7a2e3578e
LLVM_CONFIG=${LLVM_CONFIG:-llvm-config}

command -v "${LLVM_CONFIG}" >/dev/null 2>&1 || {
    PREFIX="${PROJECT_DIR}/deps/clang-${LLVM_VERSION}"
    if [ ! -f "${PREFIX}/bin/llvm-config" ]; then
        mkdir -p "deps"
        FILE="${PREFIX}.tar.xz"
        if [ ! -f "${FILE}" ]; then
            URL="http://llvm.org/releases/${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-x86_64-apple-darwin.tar.xz"
            echo "Downloading ${URL}..."
            curl --retry 3 -# -S -L "${URL}" -o "${FILE}.tmp" && mv "${FILE}.tmp" "${FILE}"
        fi
        if [ ! -d ${PROJECT_DIR} ]; then
            echo -n "Checking file... "
            echo "${LLVM_HASH}  ${FILE}"
            echo "${LLVM_HASH}  ${FILE}" | shasum -a 512256 -c
            rm -rf "${PREFIX}"
            mkdir -p "${PREFIX}"
            echo -n "Unpacking archive... "
            tar xf "${FILE}" -C "${PREFIX}" --strip-components 1
            echo "done."
          fi
    fi
    LLVM_CONFIG="${PREFIX}/bin/llvm-config"
}

PREFIX="$("${LLVM_CONFIG}" --prefix)"
case "${PREFIX}" in
  *\ *) (>&2 echo "Error: Path to LLVM may not contain spaces: '${PREFIX}'"); exit 1 ;;
esac

echo "// Do not modify this file. Instead, rerun ./configure"
echo "LLVM_LIBDIR=$(${LLVM_CONFIG} --libdir)"
echo "LLVM_INCLUDES=$(${LLVM_CONFIG} --includedir)"
echo "LLVM_CXXFLAGS=$(${LLVM_CONFIG} --cxxflags)"
