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
    sourceVaultURL := "https://<source-vault-name>.vault.azure.net/"
    destVaultURL := "https://<dest-vault-name>.vault.azure.net/"

    // Define the patterns (suffixes) to match
    patterns := []string{"-dev-id", "-test-id"}

    ctx := context.Background()

    cred, err := azidentity.NewDefaultAzureCredential(nil)
    if err != nil {
        log.Fatalf("Failed to obtain credentials: %v", err)
    }

    sourceClient, err := azsecrets.NewClient(sourceVaultURL, cred, nil)
    if err != nil {
        log.Fatalf("Failed to create source client: %v", err)
    }
    destClient, err := azsecrets.NewClient(destVaultURL, cred, nil)
    if err != nil {
        log.Fatalf("Failed to create destination client: %v", err)
    }

    pager := sourceClient.NewListSecretsPager(nil)
    for pager.More() {
        page, err := pager.NextPage(ctx)
        if err != nil {
            log.Fatalf("Failed to get next page: %v", err)
        }

        for _, secretItem := range page.Value {
            name := parseSecretName(*secretItem.ID)

            // Check if name matches any pattern
            if !matchesAnyPattern(name, patterns) {
                fmt.Printf("Skipping secret not matching patterns: %s\n", name)
                continue
            }

            // Fetch the actual secret value
            secretResp, err := sourceClient.GetSecret(ctx, name, nil)
            if err != nil {
                log.Printf("Failed to get secret '%s': %v", name, err)
                continue
            }

            // Set it in the destination vault
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

// Helper: Check if a secret name matches any of the patterns
func matchesAnyPattern(name string, patterns []string) bool {
    for _, pattern := range patterns {
        if strings.HasSuffix(name, pattern) {
            return true
        }
    }
    return false
}
