// obmax-enroll: issues OB Max device certificates from one-time invitation
// codes, renews them, and gives the administrator a page to manage both.
// See docs/obmax/V2_SPEC.md and server/enroll/README.md.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
)

func healthcheck() int {
	addr := env("ENROLL_PUBLIC_ADDR", ":8787")
	if strings.HasPrefix(addr, ":") {
		addr = "127.0.0.1" + addr
	}
	c := &http.Client{Timeout: 3 * time.Second}
	resp, err := c.Get("http://" + addr + "/v1/health")
	if err != nil {
		return 1
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC)
	// The image has no shell or curl: the container healthcheck runs this.
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(healthcheck())
	}
	cfg, err := LoadConfig()
	if err != nil {
		log.Fatal(err)
	}
	ca, err := LoadCA(cfg.caCertPath(), cfg.caKeyPath())
	if err != nil {
		log.Fatalf("CA: %v (expected %s and %s)", err, cfg.caCertPath(), cfg.caKeyPath())
	}
	store, err := OpenStore(cfg.statePath())
	if err != nil {
		log.Fatalf("state: %v", err)
	}
	srv := NewServer(cfg, ca, store)

	public := &http.Server{
		Addr:              cfg.PublicAddr,
		Handler:           srv.PublicHandler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       20 * time.Second,
		WriteTimeout:      20 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	admin := &http.Server{
		Addr:              cfg.AdminAddr,
		Handler:           srv.AdminHandler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	log.Printf("obmax-enroll: CA %q valid until %s; public %s, admin %s%s",
		ca.Cert.Subject.CommonName, ca.Cert.NotAfter.Format(time.DateOnly),
		cfg.PublicAddr, cfg.AdminAddr, cfg.AdminBasePath)

	errs := make(chan error, 2)
	for _, s := range []*http.Server{public, admin} {
		go func(s *http.Server) {
			if err := s.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				errs <- err
			}
		}(s)
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	select {
	case err := <-errs:
		log.Printf("server: %v", err)
	case <-stop:
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = public.Shutdown(ctx)
	_ = admin.Shutdown(ctx)
}
