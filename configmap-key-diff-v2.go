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
        return nil
    }

    fmt.Println("⚠️ Key differences detected:")
    var allDifferences []string

    if len(missingInB) > 0 {
        fmt.Printf("  - Keys present in %s but missing in %s:\n", fileA, fileB)
        for _, key := range missingInB {
            fmt.Printf("    • %s\n", key)
            allDifferences = append(allDifferences, fmt.Sprintf("%s (missing in %s)", key, fileB))
        }
    }
    if len(missingInA) > 0 {
        fmt.Printf("  - Keys present in %s but missing in %s:\n", fileB, fileA)
        for _, key := range missingInA {
            fmt.Printf("    • %s\n", key)
            allDifferences = append(allDifferences, fmt.Sprintf("%s (missing in %s)", key, fileA))
        }
    }

    // Compose the error with all differences
    return fmt.Errorf("configmap key differences detected: %s", strings.Join(allDifferences, ", "))
}
