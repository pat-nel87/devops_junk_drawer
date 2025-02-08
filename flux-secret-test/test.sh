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
