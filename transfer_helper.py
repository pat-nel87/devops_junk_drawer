import subprocess
import requests
import json

HARBOR_REGISTRY_URL = "your-harbor-registry.com"
ACR_REGISTRY_URL = "your-acr-registry.azurecr.io"
HARBOR_PROJECT = "your-harbor-project"
ACR_PROJECT = "your-acr-project"
HARBOR_USERNAME = "your-harbor-username"
HARBOR_PASSWORD = "your-harbor-password"

# Function to run shell commands
def run_command(command):
    result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout.decode().strip()

# Login to Harbor
run_command(f'echo "{HARBOR_PASSWORD}" | docker login {HARBOR_REGISTRY_URL} -u {HARBOR_USERNAME} --password-stdin')

# Login to ACR (assumes you've logged in via `az acr login`)
run_command(f'az acr login --name {ACR_REGISTRY_URL}')

# Get the list of images in the Harbor project
response = requests.get(f'https://{HARBOR_REGISTRY_URL}/api/v2.0/projects/{HARBOR_PROJECT}/repositories', auth=(HARBOR_USERNAME, HARBOR_PASSWORD))
images = json.loads(response.text)

for image_info in images:
    image_name = image_info['name']
    
    # Get the list of tags for each image
    response = requests.get(f'https://{HARBOR_REGISTRY_URL}/api/v2.0/projects/{HARBOR_PROJECT}/repositories/{image_name}/tags', auth=(HARBOR_USERNAME, HARBOR_PASSWORD))
    tags = json.loads(response.text)
    
    for tag_info in tags:
        tag = tag_info['name']
        harbor_image = f"{HARBOR_REGISTRY_URL}/{HARBOR_PROJECT}/{image_name}:{tag}"
        acr_image = f"{ACR_REGISTRY_URL}/{ACR_PROJECT}/{image_name}:{tag}"
        
        # Pull the image from Harbor
        run_command(f'docker pull {harbor_image}')
        
        # Retag the image for ACR
        run_command(f'docker tag {harbor_image} {acr_image}')
        
        # Push the image to ACR
        run_command(f'docker push {acr_image}')
        
        # Optional: Remove local images to save space
        run_command(f'docker rmi {harbor_image} {acr_image}')
