#!/bin/bash
# do it before start photoPrism

# Remove old build directory
echo "Removing old build directory..." | lolcat
sudo rm -rf ./built-ui-componets
mkdir ./built-ui-componets

# Remove old source code directory
echo "Removing old source code directory..." | lolcat
sudo rm -rf ./photoprism_src

# Clone the photoprism repository from the release branch
echo "Cloning photoprism repository..." | lolcat
git clone --branch release https://github.com/photoprism/photoprism.git ./photoprism_src

# Change to the photoprism_src directory
echo "Changing to photoprism_src directory..." | lolcat
pushd photoprism_src

# Modify the configuration file to insert sponsor: true
echo "Modifying configuration file..."　| lolcat
sed -i '/name: "Test",/a\  sponsor: true,' ./frontend/src/common/config.js


# Return to the previous directory
echo "Returning to previous directory..."   | lolcat
popd

# Build the front-end application using Docker
echo "Building front-end application with Docker..."　| lolcat
docker run --rm \
  -v ./photoprism_src:/workspace \
  --entrypoint /bin/sh \
  node:lts-alpine -c "cd /workspace/frontend && npm ci --no-update-notifier --no-audit && env NODE_ENV=production npm run build"

# Remove old build results
echo "Removing old build results..."         | lolcat
sudo rm -rf /mnt/appdata/photoprism/df-built-ui-componets

# Copy new build results to the destination directory
echo "Copying new build results..."　| lolcat
cp -r ./photoprism_src/assets/static/build /mnt/appdata/photoprism/df-built-ui-componets 

echo "Script execution completed." | lolcat

