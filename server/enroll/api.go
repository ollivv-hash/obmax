package main

import (
	"bytes"
	"crypto/x509"
	"encoding/json"
	"errors"
	"log"
	"net"
	"net/http"
	"strings"
	"time"
	"unicode"
)

// Server holds everything both listeners share.
type Server struct {
	cfg       Config
	ca        *CA
	store     *Store
	now       func() time.Time
	enrollLim *FailureLimiter
	renewLim  *FailureLimiter
	loginLim  *FailureLimiter
	jellyfin  *JellyfinClient
	sessions  *Sessions
}

func NewServer(cfg Config, ca *CA, store *Store) *Server {
	return &Server{
		cfg:   cfg,
		ca:    ca,
		store: store,
		now:   time.Now,
		// Spec §3: 5 failed codes per IP per hour; 50 overall pauses
		// enrollment for 15 minutes.
		enrollLim: NewFailureLimiter(time.Hour, 5, 50, 15*time.Minute),
		renewLim:  NewFailureLimiter(time.Hour, 20, 0, 0),
		loginLim:  NewFailureLimiter(15*time.Minute, 5, 0, 0),
		jellyfin:  NewJellyfinClient(cfg.JellyfinURL),
		sessions:  NewSessions(12 * time.Hour),
	}
}

// PublicHandler serves enroll.example.com.
func (s *Server) PublicHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/enroll", s.handleEnroll)
	mux.HandleFunc("POST /v1/renew", s.handleRenew)
	mux.HandleFunc("GET /v1/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})
	return securityHeaders(mux)
}

type apiError struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, apiError{Error: code, Message: message})
}

func decodeJSON(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 64<<10))
	return dec.Decode(v)
}

// clientIP is the caller's address: the one Caddy forwarded when the
// request comes from a trusted proxy, the socket's otherwise.
func (s *Server) clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if s.cfg.trustsProxy(host) {
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			parts := strings.Split(fwd, ",")
			return strings.TrimSpace(parts[len(parts)-1])
		}
	}
	return host
}

type deviceInfo struct {
	Name       string `json:"name"`
	Platform   string `json:"platform"`
	AppVersion string `json:"appVersion"`
}

type enrollRequest struct {
	Code   string     `json:"code"`
	CSR    string     `json:"csr"`
	Device deviceInfo `json:"device"`
}

type certResponse struct {
	CertificateChain string    `json:"certificateChain"`
	DeviceID         string    `json:"deviceId"`
	JellyfinUserName string    `json:"jellyfinUsername"`
	ServerURL        string    `json:"serverUrl"`
	NotAfter         time.Time `json:"notAfter"`
}

const msgInvalidCode = "Ce code n'est pas valide ou a expiré."
const msgRateLimited = "Trop d'essais. Réessayez dans une heure."

func (s *Server) handleEnroll(w http.ResponseWriter, r *http.Request) {
	now := s.now()
	ip := s.clientIP(r)
	if !s.enrollLim.Allowed(ip, now) {
		fail(w, http.StatusTooManyRequests, "rate_limited", msgRateLimited)
		return
	}
	var req enrollRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, http.StatusBadRequest, "invalid_request", "Requête invalide.")
		return
	}
	csr, err := ParseCSR(req.CSR)
	if err != nil {
		fail(w, http.StatusBadRequest, "invalid_request", "Demande de certificat invalide.")
		return
	}
	normalized := NormalizeCode(req.Code)
	device := sanitizeDevice(req.Device)

	var resp certResponse
	err = s.store.Update(func(st *state) error {
		var inv *Invitation
		if normalized != "" {
			inv = st.invitationByHash(HashCode(normalized))
		}
		if inv == nil || !inv.Pending(now) {
			return errInvalidCode
		}
		cn := inv.JellyfinUserName + "/" + device.Name
		leaf, err := s.ca.Issue(csr, truncate(cn, 64), s.cfg.CertValidity, now)
		if err != nil {
			return err
		}
		keyHash, err := SPKIHash(csr.PublicKey)
		if err != nil {
			return err
		}
		d := &Device{
			ID:               randomID(),
			JellyfinUserID:   inv.JellyfinUserID,
			JellyfinUserName: inv.JellyfinUserName,
			Label:            inv.Label,
			Name:             device.Name,
			Platform:         device.Platform,
			AppVersion:       device.AppVersion,
			PublicKeyHash:    keyHash,
			Serial:           serialHex(leaf),
			NotAfter:         leaf.NotAfter,
			EnrolledAt:       now,
		}
		st.Devices = append(st.Devices, d)
		used := now
		inv.UsedAt = &used
		inv.DeviceID = d.ID
		st.log(now, "enrolled", d.JellyfinUserName+" : "+d.Name+" ("+d.Platform+")", ip)
		resp = certResponse{
			CertificateChain: s.ca.ChainPEM(leaf),
			DeviceID:         d.ID,
			JellyfinUserName: d.JellyfinUserName,
			ServerURL:        s.cfg.PublicServerURL,
			NotAfter:         leaf.NotAfter,
		}
		return nil
	})
	switch {
	case errors.Is(err, errInvalidCode):
		s.enrollLim.Fail(ip, now)
		_ = s.store.Update(func(st *state) error {
			st.log(now, "enroll_failed", "code refusé", ip)
			return nil
		})
		fail(w, http.StatusForbidden, "invalid_code", msgInvalidCode)
	case err != nil:
		log.Printf("enroll: %v", err)
		fail(w, http.StatusInternalServerError, "server_error", "Erreur du service d'activation.")
	default:
		writeJSON(w, http.StatusOK, resp)
	}
}

var (
	errInvalidCode = errors.New("invalid code")
	errInvalidCert = errors.New("invalid certificate")
	errRevoked     = errors.New("revoked")
)

type renewRequest struct {
	DeviceID         string `json:"deviceId"`
	CertificateChain string `json:"certificateChain"`
	CSR              string `json:"csr"`
	AppVersion       string `json:"appVersion"`
}

func (s *Server) handleRenew(w http.ResponseWriter, r *http.Request) {
	now := s.now()
	ip := s.clientIP(r)
	if !s.renewLim.Allowed(ip, now) {
		fail(w, http.StatusTooManyRequests, "rate_limited", msgRateLimited)
		return
	}
	var req renewRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, http.StatusBadRequest, "invalid_request", "Requête invalide.")
		return
	}
	// The CSR's self-signature proves the caller holds the private key; the
	// key must be the one in the current certificate.
	csr, err := ParseCSR(req.CSR)
	if err != nil {
		fail(w, http.StatusBadRequest, "invalid_request", "Demande de certificat invalide.")
		return
	}
	leaf, err := s.ca.VerifyLeaf(req.CertificateChain, now)
	if err != nil {
		s.renewLim.Fail(ip, now)
		fail(w, http.StatusForbidden, "invalid_certificate", "Certificat invalide ou expiré.")
		return
	}
	if !samePublicKey(leaf, csr) {
		s.renewLim.Fail(ip, now)
		fail(w, http.StatusForbidden, "invalid_certificate", "La clé ne correspond pas au certificat.")
		return
	}

	var resp certResponse
	err = s.store.Update(func(st *state) error {
		d := st.deviceByID(req.DeviceID)
		serial := serialHex(leaf)
		if d == nil || (serial != d.Serial && serial != d.PreviousSerial) {
			return errInvalidCert
		}
		if d.RevokedAt != nil {
			return errRevoked
		}
		newLeaf, err := s.ca.Issue(csr, truncate(d.JellyfinUserName+"/"+d.Name, 64), s.cfg.CertValidity, now)
		if err != nil {
			return err
		}
		// Keep the serial just replaced: if this response never reaches the
		// device, it renews again with it.
		if serial == d.Serial {
			d.PreviousSerial = d.Serial
		}
		d.Serial = serialHex(newLeaf)
		d.NotAfter = newLeaf.NotAfter
		renewed := now
		d.LastRenewedAt = &renewed
		if v := strings.TrimSpace(req.AppVersion); v != "" {
			d.AppVersion = truncate(v, 32)
		}
		st.log(now, "renewed", d.JellyfinUserName+" : "+d.Name, ip)
		resp = certResponse{
			CertificateChain: s.ca.ChainPEM(newLeaf),
			DeviceID:         d.ID,
			JellyfinUserName: d.JellyfinUserName,
			ServerURL:        s.cfg.PublicServerURL,
			NotAfter:         newLeaf.NotAfter,
		}
		return nil
	})
	switch {
	case errors.Is(err, errRevoked):
		fail(w, http.StatusForbidden, "revoked", "Cet appareil a été révoqué.")
	case errors.Is(err, errInvalidCert):
		s.renewLim.Fail(ip, now)
		fail(w, http.StatusForbidden, "invalid_certificate", "Certificat inconnu.")
	case err != nil:
		log.Printf("renew: %v", err)
		fail(w, http.StatusInternalServerError, "server_error", "Erreur du service d'activation.")
	default:
		writeJSON(w, http.StatusOK, resp)
	}
}

func samePublicKey(leaf *x509.Certificate, csr *x509.CertificateRequest) bool {
	a, err1 := x509.MarshalPKIXPublicKey(leaf.PublicKey)
	b, err2 := x509.MarshalPKIXPublicKey(csr.PublicKey)
	return err1 == nil && err2 == nil && bytes.Equal(a, b)
}

func sanitizeDevice(d deviceInfo) deviceInfo {
	clean := func(s string, max int) string {
		s = strings.Map(func(r rune) rune {
			if r == '/' || unicode.IsControl(r) {
				return ' '
			}
			return r
		}, s)
		return truncate(strings.Join(strings.Fields(s), " "), max)
	}
	d.Name = clean(d.Name, 40)
	if d.Name == "" {
		d.Name = "Appareil"
	}
	switch d.Platform {
	case "mobile", "androidTv", "ios", "tvos":
	default:
		d.Platform = "autre"
	}
	d.AppVersion = clean(d.AppVersion, 32)
	return d
}

func truncate(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max])
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-Frame-Options", "DENY")
		next.ServeHTTP(w, r)
	})
}
