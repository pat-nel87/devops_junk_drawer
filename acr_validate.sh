IMAGE_TAG="mytag"
ACR_NAME=$(echo "$IMAGE_REF" | cut -d'.' -f1)  # "myregistry"
REPO_NAME=$(echo "$IMAGE_REF" | cut -d'/' -f2 | cut -d':' -f1)  # "myapp"
IMAGE_TAG=$(echo "$IMAGE_REF" | cut -d':' -f2)  # "mytag"

if az acr repository show-tags --name myregistry --repository myapp --query "[?@=='$IMAGE_TAG']" -o tsv | grep -q "$IMAGE_TAG"; then
  echo "Image tag '$IMAGE_TAG' exists."
else
  echo "Image tag '$IMAGE_TAG' does not exist."
  exit 1
fi
