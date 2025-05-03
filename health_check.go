package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type HealthResponse struct {
	Status string `json:"status"`
}

// ANSI color codes
const (
	green = "\033[32m"
	red   = "\033[31m"
	reset = "\033[0m"
)

func checkHealth(host string, wg *sync.WaitGroup, sem chan struct{}) {
	defer wg.Done()

	sem <- struct{}{} // acquire semaphore
	defer func() { <-sem }() // release semaphore

	url := fmt.Sprintf("http://%s/health", host)
	client := http.Client{Timeout: 5 * time.Second}

	resp, err := client.Get(url)
	if err != nil {
		fmt.Printf("%s❌ %s - error: %v%s\n", red, host, err, reset)
		return
	}
	defer resp.Body.Close()

	var health HealthResponse
	if err := json.NewDecoder(resp.Body).Decode(&health); err != nil {
		fmt.Printf("%s❌ %s - invalid JSON%s\n", red, host, reset)
		return
	}

	if strings.ToLower(health.Status) == "healthy" {
		fmt.Printf("%s✅ %s - healthy%s\n", green, host, reset)
	} else {
		fmt.Printf("%s❌ %s - status: %s%s\n", red, host, health.Status, reset)
	}
}

func main() {
	file, err := os.Open("hosts.txt")
	if err != nil {
		fmt.Println("Error opening file:", err)
		return
	}
	defer file.Close()

	var wg sync.WaitGroup
	sem := make(chan struct{}, 10) // limit to 10 concurrent requests

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		host := strings.TrimSpace(scanner.Text())
		if host == "" {
			continue
		}
		wg.Add(1)
		go checkHealth(host, &wg, sem)
	}

	wg.Wait()

	if err := scanner.Err(); err != nil {
		fmt.Println("Error reading file:", err)
	}
}
