#!/bin/bash
# do it before start photoPrism

sudo rm -rf ./built-ui-componets
mkdir ./built-ui-componets
sudo rm -rf ./photoprism_src
git clone --branch release https://github.com/photoprism/photoprism.git ./photoprism_src
pushd photoprism_src
sed -i '/name: "Test",/a\  sponsor: true,' ./frontend/src/common/config.js
popd
docker run --rm \
  -v ./photoprism_src:/workspace \
  --entrypoint /bin/sh \
  node:lts-alpine -c "cd /workspace/frontend && npm i && npm run build"
sudo rm -rf /mnt/appdata/photoprism/df-built-ui-componets
cp -r ./photoprism_src/assets/static/build /mnt/appdata/photoprism/df-built-ui-componets 


