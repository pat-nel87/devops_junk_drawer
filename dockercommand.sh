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

- name: Configure Git
  run: |
    git config user.name "${{ github.actor }}"
    git config user.email "${{ github.actor }}@users.noreply.github.com"

- name: Create new branch and commit changes
  run: |
    BRANCH="bump/${{ github.actor }}/$(date +%s)"
    git checkout -b "$BRANCH"
    git add "${{ inputs.file }}"
    git commit -m "chore: bump image versions by @${{ github.actor }}"
    git push origin "$BRANCH"
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

- name: Open Pull Request
  uses: peter-evans/create-pull-request@v5
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    title: "chore: bump image versions by @${{ github.actor }}"
    body: |
      This PR was created by **@${{ github.actor }}** using `flux-helpers`.

      It bumps image versions in:
      - `${{ inputs.file }}`
    head: bump/${{ github.actor }}/{{ github.run_id }}
    base: main
