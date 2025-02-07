kubectl patch deployment <deployment-name> -n cluster-config --patch '{
  "spec": {
    "template": {
      "spec": {
        "serviceAccountName": "my-workload-sa"
      }
    }
  }
}'
