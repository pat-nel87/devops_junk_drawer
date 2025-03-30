// fluxgen.go
package main

import (
	"encoding/json"
	"fmt"
	"strconv"
    "strings"
	helmv2 "github.com/fluxcd/helm-controller/api/v2beta1"
	apiextv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"os"
	"sigs.k8s.io/yaml"
)

// GenerateFluxHelmRelease writes a basic HelmRelease manifest to a file
func GenerateFluxHelmRelease(appName, namespace, chartName, chartVersion, repoName, repoNamespace string, values map[string]interface{}) error {
	valuesBytes, _ := json.Marshal(values)
	valuesJSON := &apiextv1.JSON{Raw: valuesBytes}

	hr := helmv2.HelmRelease{
		TypeMeta: metav1.TypeMeta{
			APIVersion: helmv2.GroupVersion.String(),
			Kind:       "HelmRelease",
		},
		ObjectMeta: metav1.ObjectMeta{
			Name:      appName,
			Namespace: namespace,
		},
		Spec: helmv2.HelmReleaseSpec{
			Interval: metav1.Duration{Duration: 300_000_000_000}, // 5m
			Chart: &helmv2.HelmChartTemplate{
				Spec: helmv2.HelmChartTemplateSpec{
					Chart:   chartName,
					Version: chartVersion,
					SourceRef: helmv2.CrossNamespaceObjectReference{
						Kind:      "HelmRepository",
						Name:      repoName,
						Namespace: repoNamespace,
					},
				},
			},
			Values: valuesJSON,
		},
	}

	out, err := yaml.Marshal(&hr)
	if err != nil {
		return fmt.Errorf("failed to marshal HelmRelease: %w", err)
	}

	err = os.MkdirAll("render", 0755)
	if err != nil {
		return err
	}

	path := "render/helmrelease.yaml"
	if err := os.WriteFile(path, out, 0644); err != nil {
		return fmt.Errorf("failed to write file: %w", err)
	}

	fmt.Println("✅ Flux HelmRelease written to", path)
	return nil
}

func BumpHelmReleaseImageTag(filePath, imageName string) error {
    data, err := os.ReadFile(filePath)
    if err != nil {
        return fmt.Errorf("failed to read file: %w", err)
    }

    var hr helmv2.HelmRelease
    if err := yaml.Unmarshal(data, &hr); err != nil {
        return fmt.Errorf("failed to unmarshal HelmRelease: %w", err)
    }

    var values map[string]interface{}
    if err := json.Unmarshal(hr.Spec.Values.Raw, &values); err != nil {
        return fmt.Errorf("failed to parse .spec.values: %w", err)
    }

    image, ok := values["image"].(map[string]interface{})
    if !ok {
        return fmt.Errorf("missing or invalid image block in values")
    }

    repo, _ := image["repository"].(string)
    tag, _ := image["tag"].(string)

    if repo != imageName {
        return fmt.Errorf("image %q not found (found: %q)", imageName, repo)
    }

    parts := strings.Split(tag, ".")
    lastIndex := len(parts) - 1
    lastNum, err := strconv.Atoi(parts[lastIndex])
    if err != nil {
        return fmt.Errorf("cannot increment tag %q: %w", tag, err)
    }

    parts[lastIndex] = strconv.Itoa(lastNum + 1)
    newTag := strings.Join(parts, ".")
    image["tag"] = newTag

    fmt.Printf("🔁 Bumped %s:%s → %s:%s\n", repo, tag, repo, newTag)

    // Re-encode and write updated file
    newRaw, _ := json.Marshal(values)
    hr.Spec.Values = &apiextv1.JSON{Raw: newRaw}

    newYAML, _ := yaml.Marshal(&hr)
    if err := os.WriteFile(filePath, newYAML, 0644); err != nil {
        return fmt.Errorf("failed to write updated file: %w", err)
    }

    return nil
}
