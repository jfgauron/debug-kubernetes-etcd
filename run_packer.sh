#!/bin/bash
set -e

cd "$(dirname "$0")"

for D in `find packer/* -maxdepth 0 -type d`;
do
  echo "Checking $(basename "$D").";

  # fix template for backward incompatibilities
  packer fix "$D"/image.json > "$D/image_fixed.json"

  # Validate template file
  packer validate -syntax-only "$D"/image_fixed.json

  hash=`tar --sort=name --owner=root:0 --group=root:0 --mtime='UTC 2019-01-01' -c "$D" | sha1sum | head -c 40`;
  
  ami=`aws ec2 describe-images \
          --filters Name="tag:source_hash",Values="$hash" \
          --query "Images[*].[ImageId]" \
          --output text`;

  # Only build image if it doesn't exist yet
  if [ -z "$ami" ]
  then
    echo "Building $(basename "$D") ($hash)...";
    packer build -var source_hash=$hash "$D"/image_fixed.json
  else
    echo "$(basename "$D") is already built. ($hash)";
  fi

  # cleanup
  rm "$D/image_fixed.json"
  printf "Done.\n\n";
done
