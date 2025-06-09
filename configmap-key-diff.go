package main

import (
    "fmt"
    "os"
    "sigs.k8s.io/yaml"
)

// ConfigMap represents a simplified K8s ConfigMap structure.
type ConfigMap struct {
    Data map[string]string `yaml:"data"`
}

// CompareConfigMapKeys compares the keys of two configmaps from YAML files.
func CompareConfigMapKeys(fileA, fileB string) error {
    cmA, err := readConfigMap(fileA)
    if err != nil {
        return fmt.Errorf("failed to read %s: %w", fileA, err)
    }

    cmB, err := readConfigMap(fileB)
    if err != nil {
        return fmt.Errorf("failed to read %s: %w", fileB, err)
    }

    keysA := mapKeys(cmA.Data)
    keysB := mapKeys(cmB.Data)

    missingInB := diffKeys(keysA, keysB)
    missingInA := diffKeys(keysB, keysA)

    if len(missingInA) == 0 && len(missingInB) == 0 {
        fmt.Println("✅ Keys match between the two configmaps.")
    } else {
        fmt.Println("⚠️ Key differences detected:")
        if len(missingInB) > 0 {
            fmt.Printf("  - Keys present in %s but missing in %s:\n", fileA, fileB)
            for _, key := range missingInB {
                fmt.Printf("    • %s\n", key)
            }
        }
        if len(missingInA) > 0 {
            fmt.Printf("  - Keys present in %s but missing in %s:\n", fileB, fileA)
            for _, key := range missingInA {
                fmt.Printf("    • %s\n", key)
            }
        }
    }

    return nil
}

func readConfigMap(filePath string) (*ConfigMap, error) {
    data, err := os.ReadFile(filePath)
    if err != nil {
        return nil, err
    }

    var cm ConfigMap
    if err := yaml.Unmarshal(data, &cm); err != nil {
        return nil, err
    }

    return &cm, nil
}

func mapKeys(data map[string]string) map[string]struct{} {
    keys := make(map[string]struct{})
    for k := range data {
        keys[k] = struct{}{}
    }
    return keys
}

func diffKeys(a, b map[string]struct{}) []string {
    var diff []string
    for key := range a {
        if _, ok := b[key]; !ok {
            diff = append(diff, key)
        }
    }
    return diff
}
