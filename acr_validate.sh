IMAGE_TAG="mytag"

if az acr repository show-tags --name myregistry --repository myapp --query "[?@=='$IMAGE_TAG']" -o tsv | grep -q "$IMAGE_TAG"; then
  echo "Image tag '$IMAGE_TAG' exists."
else
  echo "Image tag '$IMAGE_TAG' does not exist."
  exit 1
fi
