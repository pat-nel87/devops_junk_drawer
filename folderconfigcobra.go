var compareFoldersCmd = &cobra.Command{
    Use:   "compare-configmap-keys-folders <env1_dir> <env2_dir>",
    Short: "Compare configmap keys across multiple applications in two environment folders",
    Args:  cobra.ExactArgs(2),
    SilenceUsage: true,
    RunE: func(cmd *cobra.Command, args []string) error {
        env1Dir := args[0]
        env2Dir := args[1]

        return CompareConfigMapKeysInFolders(env1Dir, env2Dir)
    },
}
