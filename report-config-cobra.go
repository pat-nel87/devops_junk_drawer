var compareCmdReport = &cobra.Command{
    Use:   "compare-configmap-keys-report <fileA.yaml> <fileB.yaml>",
    Short: "Compare two ConfigMaps and print a report without failing on differences",
    Args:  cobra.ExactArgs(2),
    SilenceUsage: true,
    RunE: func(cmd *cobra.Command, args []string) error {
        fileA := args[0]
        fileB := args[1]

        err := CompareConfigMapKeys(fileA, fileB)
        if err != nil {
            // Print the error but exit with success
            fmt.Println(err)
            return nil
        }

        return nil
    },
}
