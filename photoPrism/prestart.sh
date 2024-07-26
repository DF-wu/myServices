#!/bin/bash
# do it before start photoPrism

rm -r ./built-ui-componets
mkdir ./built-ui-componets
rm -r ./photoprism_src
git clone --branch release https://github.com/photoprism/photoprism.git ./photoprism_src
pushd photoprism_src
sed -i '/name: "Test",/a\  sponsor: true,' ./frontend/src/common/config.js
docker run --rm \
  -v ./frontend:/workspace \
  --entrypoint /bin/sh \
  node:lts-alpine -c "cd /workspace && npm i && npm run build"
cp -r ./photoprism_src/assets/static/build ./built-ui-componets
popd

