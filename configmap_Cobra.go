var compareCmd = &cobra.Command{
    Use:   "compare-configmaps <fileA.yaml> <fileB.yaml>",
    Short: "Compare the keys of two ConfigMaps and report any differences",
    Args:  cobra.ExactArgs(2),
    RunE: func(cmd *cobra.Command, args []string) error {
        fileA := args[0]
        fileB := args[1]

        if err := CompareConfigMapKeys(fileA, fileB); err != nil {
            return fmt.Errorf("failed to compare configmaps: %w", err)
        }

        return nil
    },
}
