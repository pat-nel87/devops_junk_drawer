package main

import (
    "context"
    "fmt"
    "log"
    "strings"

    "github.com/Azure/azure-sdk-for-go/sdk/azidentity"
    "github.com/Azure/azure-sdk-for-go/sdk/keyvault/azsecrets"
)

func main() {
    // Replace these with your vault URLs
    sourceVaultURL := "https://<source-vault-name>.vault.azure.net/"
    destVaultURL := "https://<dest-vault-name>.vault.azure.net/"

    // Exclusion list
    exclusions := []string{"SecretToSkip1", "AnotherSecretToSkip"}

    ctx := context.Background()

    // Authenticate
    cred, err := azidentity.NewDefaultAzureCredential(nil)
    if err != nil {
        log.Fatalf("Failed to obtain credentials: %v", err)
    }

    // Clients
    sourceClient, err := azsecrets.NewClient(sourceVaultURL, cred, nil)
    if err != nil {
        log.Fatalf("Failed to create source client: %v", err)
    }
    destClient, err := azsecrets.NewClient(destVaultURL, cred, nil)
    if err != nil {
        log.Fatalf("Failed to create destination client: %v", err)
    }

    // List secrets from source vault
    pager := sourceClient.NewListSecretsPager(nil)
    for pager.More() {
        page, err := pager.NextPage(ctx)
        if err != nil {
            log.Fatalf("Failed to get next page: %v", err)
        }

        for _, secretItem := range page.Value {
            name := parseSecretName(*secretItem.ID)
            // Skip exclusions
            if contains(exclusions, name) {
                fmt.Printf("Skipping excluded secret: %s\n", name)
                continue
            }

            // Fetch the actual secret value
            secretResp, err := sourceClient.GetSecret(ctx, name, nil)
            if err != nil {
                log.Printf("Failed to get secret '%s': %v", name, err)
                continue
            }

            // Set it in destination vault
            _, err = destClient.SetSecret(ctx, name, secretResp.Value, nil)
            if err != nil {
                log.Printf("Failed to set secret '%s': %v", name, err)
                continue
            }

            fmt.Printf("Copied secret: %s\n", name)
        }
    }

    fmt.Println("Secrets copy complete!")
}

// Helper: Parse the secret name from its ID
func parseSecretName(id string) string {
    // Example ID: https://vaultname.vault.azure.net/secrets/secretname/version
    parts := strings.Split(id, "/")
    if len(parts) >= 5 {
        return parts[4]
    }
    return ""
}

// Helper: Check if a slice contains a string
func contains(slice []string, item string) bool {
    for _, v := range slice {
        if v == item {
            return true
        }
    }
    return false
}
