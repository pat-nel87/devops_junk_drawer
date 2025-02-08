kubectl patch deployment <deployment-name> -n cluster-config --patch '{
  "spec": {
    "template": {
      "spec": {
        "serviceAccountName": "my-workload-sa"
      }
    }
  }
}'

kubectl patch deployment my-deployment -n cluster-config --type merge -p '{"spec": {"template": {"spec": {"serviceAccountName": "my-workload-sa"}}}}'

kubectl patch secretproviderclass azure-kv -n cluster-config --type merge -p '{"metadata": {"annotations": {"resync-timestamp": "'$(date +%s)'"}}}'
kubectl run test-imds --rm -it --image=busybox -- /bin/sh -c "apk add --no-cache curl && curl -H Metadata:true 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net'"
