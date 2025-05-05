package main

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"strings"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Println("Usage: go run main.go <variables.tf>")
		os.Exit(1)
	}

	inputFile := os.Args[1]
	outputFile := "terraform.tfvars"

	file, err := os.Open(inputFile)
	if err != nil {
		fmt.Printf("Failed to open input file: %v\n", err)
		os.Exit(1)
	}
	defer file.Close()

	out, err := os.Create(outputFile)
	if err != nil {
		fmt.Printf("Failed to create tfvars file: %v\n", err)
		os.Exit(1)
	}
	defer out.Close()

	scanner := bufio.NewScanner(file)

	varNameRegex := regexp.MustCompile(`variable\s+"([^"]+)"`)
	defaultValueRegex := regexp.MustCompile(`default\s+=\s+(.*)`)

	var currentVar string
	inBlock := false

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		if matches := varNameRegex.FindStringSubmatch(line); matches != nil {
			currentVar = matches[1]
			inBlock = true
			continue
		}

		if inBlock {
			if matches := defaultValueRegex.FindStringSubmatch(line); matches != nil {
				defaultVal := matches[1]
				fmt.Fprintf(out, "%s = %s\n", currentVar, defaultVal)
				inBlock = false
				continue
			}
			// No default provided
			if strings.HasPrefix(line, "}") {
				fmt.Fprintf(out, "%s = \"<REQUIRED>\"\n", currentVar)
				inBlock = false
			}
		}
	}

	fmt.Printf("✅ tfvars file written to: %s\n", outputFile)
}
