package main

import (
    "fmt"
    "os"
    "path/filepath"
)

// CompareConfigMapKeysInFolders compares configmap keys across two environment directories.
func CompareConfigMapKeysInFolders(env1Dir, env2Dir string) error {
    entries, err := os.ReadDir(env1Dir)
    if err != nil {
        return fmt.Errorf("failed to read directory %s: %w", env1Dir, err)
    }

    var matches, diffs, missing int

    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        appName := entry.Name()
        cm1Path := filepath.Join(env1Dir, appName, "configmap.yaml")
        cm2Path := filepath.Join(env2Dir, appName, "configmap.yaml")

        _, err1 := os.Stat(cm1Path)
        _, err2 := os.Stat(cm2Path)

        if os.IsNotExist(err1) || os.IsNotExist(err2) {
            fmt.Printf("❌ ConfigMap missing for app '%s': %s\n", appName,
                missingMsg(err1, err2, env1Dir, env2Dir))
            missing++
            continue
        }

        fmt.Printf("🔍 Comparing ConfigMap keys for app '%s'\n", appName)
        err := CompareConfigMapKeys(cm1Path, cm2Path)
        if err != nil {
            fmt.Printf("⚠️ Difference detected in '%s': %v\n", appName, err)
            diffs++
        } else {
            fmt.Printf("✅ ConfigMap keys match for app '%s'\n", appName)
            matches++
        }
    }

    fmt.Printf("\n📊 Summary: %d matches, %d differences, %d missing\n", matches, diffs, missing)

    if diffs > 0 || missing > 0 {
        return fmt.Errorf("configmap key differences or missing configmaps detected")
    }

    return nil
}

func missingMsg(err1, err2 error, env1, env2 string) string {
    if os.IsNotExist(err1) && os.IsNotExist(err2) {
        return fmt.Sprintf("missing in both %s and %s", env1, env2)
    } else if os.IsNotExist(err1) {
        return fmt.Sprintf("missing in %s", env1)
    } else {
        return fmt.Sprintf("missing in %s", env2)
    }
}

