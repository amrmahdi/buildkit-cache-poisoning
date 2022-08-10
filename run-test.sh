#!/bin/bash
set -e

IMAGE=moby/buildkit:master-rootless
TMP=$(mktemp -d)
info() {
  echo $'=== \e[1m'$@$'\e[0m' >&2
}

error() {
  echo $'\e[1;31m'$@$'\e[0m' >&2
}

success() {
  echo $'\e[1;32m'$@$'\e[0m' >&2
}

buildctl-daemonless() {
    docker run \
    --security-opt seccomp=unconfined \
    --security-opt apparmor=unconfined \
    -v $(pwd)/context:/context \
    -v ${TMP}:${TMP} \
    --rm \
    -ti \
    --entrypoint buildctl-daemonless.sh \
    ${IMAGE} \
    "$@"
}

trap "rm -rf ${TMP}" EXIT ERR


info "Building and exporting image"
buildctl-daemonless build . \
  --frontend dockerfile.v0 \
  --local context=/context \
  --local dockerfile=/context \
  --export-cache=type=local,dest=${TMP}/image  \
  -t registry-cache:5000/leaf:debug \
  --progress=plain



manifest_digest=$(cat ${TMP}/image/index.json  | jq -r .manifests[0].digest | cut -d ':' -f 2)
smallest_layer=$(cat ${TMP}/image/blobs/sha256/${manifest_digest} | jq -r ".manifests |= sort_by(.size) | .manifests[0].digest" | cut -d ':' -f 2)

info "tampering smallest layer"

sudo chmod 600 ${TMP}/image/blobs/sha256/${smallest_layer}
echo "foo" > ${TMP}/image/blobs/sha256/${smallest_layer}

info "Building (with import-from) image"
buildctl-daemonless build . \
  --frontend dockerfile.v0 \
  --local context=/context \
  --local dockerfile=/context \
  --import-cache=type=local,src=${TMP}/image \
  -t registry-cache:5000/image:debug \
  --progress=plain


