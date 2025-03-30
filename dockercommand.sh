kubectl create secret docker-registry <secret-name> \
  --docker-server=<registry-url> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> \
  --namespace=<namespace>


kubectl patch serviceaccount default -n <namespace> -p \
  '{"imagePullSecrets": [{"name": "<secret-name>"}]}'



  apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: <namespace>
spec:
  containers:
  - name: my-container
    image: <registry-url>/<image-name>:<tag>
  imagePullSecrets:
  - name: <secret-name>



apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-deployment
  namespace: <namespace>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-container
        image: <registry-url>/<image-name>:<tag>
      imagePullSecrets:
      - name: <secret-name>


docker run --rm \
      -v "${{ github.workspace }}:/workdir" \
      your-acr.azurecr.io/flux-helpers:latest \
      bump --file "/workdir/$FILE" $SET_ARGS --dry-run="$DRY_RUN"
