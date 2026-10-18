package main

import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Config comes from the environment (see docker-compose.yml).
type Config struct {
	DataDir         string
	PublicAddr      string
	AdminAddr       string
	AdminBasePath   string
	JellyfinURL     string
	PublicServerURL string
	CertValidity    time.Duration
	InviteValidity  time.Duration
	TrustedProxies  []*net.IPNet
	// SecureCookies is off only for local tests over plain HTTP.
	SecureCookies bool
}

func env(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func LoadConfig() (Config, error) {
	cfg := Config{
		DataDir:         env("ENROLL_DATA_DIR", "/data"),
		PublicAddr:      env("ENROLL_PUBLIC_ADDR", ":8787"),
		AdminAddr:       env("ENROLL_ADMIN_ADDR", ":8788"),
		AdminBasePath:   strings.TrimRight(env("ENROLL_ADMIN_BASE_PATH", "/obmax-admin"), "/"),
		JellyfinURL:     strings.TrimRight(env("JELLYFIN_URL", "http://192.168.0.206:8096"), "/"),
		PublicServerURL: strings.TrimRight(env("PUBLIC_SERVER_URL", "https://jellyfin.example.com"), "/"),
		SecureCookies:   env("ENROLL_INSECURE_COOKIES", "") == "",
	}
	var err error
	if cfg.CertValidity, err = time.ParseDuration(env("ENROLL_CERT_VALIDITY", "4320h")); err != nil {
		return cfg, fmt.Errorf("ENROLL_CERT_VALIDITY: %w", err)
	}
	if cfg.InviteValidity, err = time.ParseDuration(env("ENROLL_INVITE_VALIDITY", "48h")); err != nil {
		return cfg, fmt.Errorf("ENROLL_INVITE_VALIDITY: %w", err)
	}
	for _, p := range strings.Split(env("ENROLL_TRUSTED_PROXIES", "192.168.0.101/32,127.0.0.1/32"), ",") {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if !strings.Contains(p, "/") {
			p += "/32"
		}
		_, n, err := net.ParseCIDR(p)
		if err != nil {
			return cfg, fmt.Errorf("ENROLL_TRUSTED_PROXIES: %w", err)
		}
		cfg.TrustedProxies = append(cfg.TrustedProxies, n)
	}
	return cfg, nil
}

func (c Config) trustsProxy(host string) bool {
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	for _, n := range c.TrustedProxies {
		if n.Contains(ip) {
			return true
		}
	}
	return false
}

func (c Config) statePath() string { return filepath.Join(c.DataDir, "state.json") }
func (c Config) caCertPath() string {
	return filepath.Join(c.DataDir, "ca", "obmax-enroll-ca.crt")
}
func (c Config) caKeyPath() string {
	return filepath.Join(c.DataDir, "ca", "obmax-enroll-ca.key")
}
