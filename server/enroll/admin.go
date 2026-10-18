package main

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"embed"
	"encoding/base64"
	"errors"
	"html/template"
	"io/fs"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
	_ "time/tzdata" // the image has no zoneinfo
)

//go:embed web/templates/*.html web/static/*
var webFS embed.FS

var paris = func() *time.Location {
	loc, err := time.LoadLocation("Europe/Paris")
	if err != nil {
		return time.UTC
	}
	return loc
}()

// ---------------------------------------------------------------- sessions

type Session struct {
	UserName      string
	JellyfinToken string
	CSRF          string
	Expires       time.Time
}

type Sessions struct {
	mu  sync.Mutex
	ttl time.Duration
	m   map[string]*Session
}

func NewSessions(ttl time.Duration) *Sessions {
	return &Sessions{ttl: ttl, m: map[string]*Session{}}
}

func randomToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

func (s *Sessions) Create(user, jfToken string, now time.Time) (string, *Session) {
	s.mu.Lock()
	defer s.mu.Unlock()
	for k, v := range s.m {
		if now.After(v.Expires) {
			delete(s.m, k)
		}
	}
	id := randomToken()
	sess := &Session{UserName: user, JellyfinToken: jfToken, CSRF: randomToken(), Expires: now.Add(s.ttl)}
	s.m[id] = sess
	return id, sess
}

func (s *Sessions) Get(id string, now time.Time) *Session {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess := s.m[id]
	if sess == nil || now.After(sess.Expires) {
		delete(s.m, id)
		return nil
	}
	return sess
}

func (s *Sessions) Delete(id string) *Session {
	s.mu.Lock()
	defer s.mu.Unlock()
	sess := s.m[id]
	delete(s.m, id)
	return sess
}

// ---------------------------------------------------------------- handler

const sessionCookie = "obmax_admin"

type adminPage struct {
	Base        string
	User        string
	CSRF        string
	Error       string
	Notice      string
	Now         time.Time
	CAExpires   time.Time
	CAWarning   bool
	Users       []JellyfinUser
	UsersError  string
	Invitations []*Invitation
	Devices     []*Device
	Events      []*Event
	// Invitation just created.
	Code       string
	Invitation *Invitation
	Message    string
}

var adminTemplates = template.Must(template.New("").Funcs(template.FuncMap{
	"date": func(t time.Time) string { return t.In(paris).Format("02/01/2006 15:04") },
	"day":  func(t time.Time) string { return t.In(paris).Format("02/01/2006") },
	"datep": func(t *time.Time) string {
		if t == nil {
			return "—"
		}
		return t.In(paris).Format("02/01/2006 15:04")
	},
	"daysLeft": func(t, now time.Time) int { return int(t.Sub(now).Hours() / 24) },
	"platform": func(p string) string {
		switch p {
		case "androidTv":
			return "Android TV"
		case "mobile":
			return "Android"
		case "ios":
			return "iPhone / iPad"
		case "tvos":
			return "Apple TV"
		}
		return "Autre"
	},
}).ParseFS(webFS, "web/templates/*.html"))

// AdminHandler serves the admin page under cfg.AdminBasePath. Caddy only
// routes it from the mTLS host, so a visitor already holds a certificate;
// a Jellyfin administrator sign-in is required on top.
func (s *Server) AdminHandler() http.Handler {
	b := s.cfg.AdminBasePath
	mux := http.NewServeMux()
	static, _ := fs.Sub(webFS, "web/static")
	mux.Handle("GET "+b+"/static/", http.StripPrefix(b+"/static/", http.FileServerFS(static)))
	mux.HandleFunc("GET "+b+"/{$}", s.handleDashboard)
	mux.HandleFunc("POST "+b+"/login", s.handleLogin)
	mux.HandleFunc("POST "+b+"/logout", s.withSession(s.handleLogout))
	mux.HandleFunc("POST "+b+"/invitations", s.withSession(s.handleInvite))
	mux.HandleFunc("POST "+b+"/invitations/{id}/cancel", s.withSession(s.handleCancel))
	mux.HandleFunc("POST "+b+"/devices/{id}/revoke", s.withSession(s.handleRevoke))
	mux.HandleFunc("POST "+b+"/devices/{id}/restore", s.withSession(s.handleRestore))
	mux.HandleFunc("GET "+b, func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, b+"/", http.StatusSeeOther)
	})
	return s.proxyOnly(adminHeaders(mux))
}

func adminHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Security-Policy", "default-src 'self'; style-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("X-Frame-Options", "DENY")
		h.Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) session(r *http.Request) (string, *Session) {
	c, err := r.Cookie(sessionCookie)
	if err != nil {
		return "", nil
	}
	return c.Value, s.sessions.Get(c.Value, s.now())
}

type sessionHandler func(w http.ResponseWriter, r *http.Request, id string, sess *Session)

// withSession requires a signed-in session and a matching CSRF token.
func (s *Server) withSession(h sessionHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, sess := s.session(r)
		if sess == nil {
			http.Redirect(w, r, s.cfg.AdminBasePath+"/", http.StatusSeeOther)
			return
		}
		if err := r.ParseForm(); err != nil ||
			subtle.ConstantTimeCompare([]byte(r.PostFormValue("csrf")), []byte(sess.CSRF)) != 1 {
			http.Error(w, "Requête refusée (jeton de formulaire invalide). Rechargez la page.", http.StatusForbidden)
			return
		}
		h(w, r, id, sess)
	}
}

func (s *Server) render(w http.ResponseWriter, name string, p *adminPage) {
	p.Base = s.cfg.AdminBasePath
	p.Now = s.now()
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := adminTemplates.ExecuteTemplate(w, name, p); err != nil {
		log.Printf("admin template %s: %v", name, err)
	}
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	_, sess := s.session(r)
	if sess == nil {
		s.render(w, "login.html", &adminPage{Error: noticeText(r.URL.Query().Get("e"))})
		return
	}
	s.render(w, "dashboard.html", s.dashboard(r.Context(), sess, noticeText(r.URL.Query().Get("n"))))
}

func (s *Server) dashboard(ctx context.Context, sess *Session, notice string) *adminPage {
	now := s.now()
	p := &adminPage{User: sess.UserName, CSRF: sess.CSRF, Notice: notice}
	p.CAExpires = s.ca.Cert.NotAfter
	p.CAWarning = s.ca.Cert.NotAfter.Sub(now) < 183*24*time.Hour
	users, err := s.jellyfin.Users(ctx, sess.JellyfinToken)
	if err != nil {
		p.UsersError = "Impossible de lire les comptes Jellyfin."
	}
	for _, u := range users {
		if !u.Policy.IsDisabled {
			p.Users = append(p.Users, u)
		}
	}
	s.store.View(func(st *state) {
		for i := len(st.Invitations) - 1; i >= 0; i-- {
			if st.Invitations[i].Pending(now) {
				p.Invitations = append(p.Invitations, st.Invitations[i])
			}
		}
		p.Devices = st.sortedDevices()
		p.Events = st.recentEvents(50)
	})
	return p
}

func noticeText(code string) string {
	switch code {
	case "login":
		return "Identifiant ou mot de passe incorrect, ou compte non administrateur."
	case "rate":
		return "Trop d'essais de connexion. Réessayez dans un quart d'heure."
	case "jellyfin":
		return "Jellyfin ne répond pas. Réessayez plus tard."
	case "canceled":
		return "Invitation annulée."
	case "revoked":
		return "Appareil révoqué : son certificat ne sera plus renouvelé. Pour couper l'accès tout de suite, supprimez aussi l'appareil dans Jellyfin (Tableau de bord > Appareils)."
	case "restored":
		return "Appareil réactivé."
	case "user":
		return "Choisissez un compte Jellyfin."
	}
	return ""
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	now := s.now()
	ip := s.clientIP(r)
	if !s.loginLim.Allowed(ip, now) {
		http.Redirect(w, r, s.cfg.AdminBasePath+"/?e=rate", http.StatusSeeOther)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Formulaire invalide", http.StatusBadRequest)
		return
	}
	user, token, err := s.jellyfin.AuthenticateAdmin(r.Context(), r.PostFormValue("username"), r.PostFormValue("password"))
	if err != nil {
		code := "login"
		if !errors.Is(err, errNotAdmin) {
			code = "jellyfin"
			log.Printf("admin login: %v", err)
		} else {
			s.loginLim.Fail(ip, now)
		}
		_ = s.store.Update(func(st *state) error {
			st.log(now, "admin_login_failed", strings.TrimSpace(r.PostFormValue("username")), ip)
			return nil
		})
		http.Redirect(w, r, s.cfg.AdminBasePath+"/?e="+code, http.StatusSeeOther)
		return
	}
	id, _ := s.sessions.Create(user.Name, token, now)
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookie,
		Value:    id,
		Path:     s.cfg.AdminBasePath + "/",
		HttpOnly: true,
		Secure:   s.cfg.SecureCookies,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(s.sessions.ttl.Seconds()),
	})
	_ = s.store.Update(func(st *state) error {
		st.log(now, "admin_login", user.Name, ip)
		return nil
	})
	http.Redirect(w, r, s.cfg.AdminBasePath+"/", http.StatusSeeOther)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request, id string, sess *Session) {
	s.sessions.Delete(id)
	s.jellyfin.Logout(r.Context(), sess.JellyfinToken)
	http.SetCookie(w, &http.Cookie{Name: sessionCookie, Value: "", Path: s.cfg.AdminBasePath + "/", MaxAge: -1, HttpOnly: true, Secure: s.cfg.SecureCookies, SameSite: http.SameSiteStrictMode})
	http.Redirect(w, r, s.cfg.AdminBasePath+"/", http.StatusSeeOther)
}

func (s *Server) handleInvite(w http.ResponseWriter, r *http.Request, _ string, sess *Session) {
	now := s.now()
	userID := r.PostFormValue("user")
	var target *JellyfinUser
	users, err := s.jellyfin.Users(r.Context(), sess.JellyfinToken)
	if err != nil {
		http.Redirect(w, r, s.cfg.AdminBasePath+"/?n=jellyfin", http.StatusSeeOther)
		return
	}
	for i := range users {
		if users[i].ID == userID && !users[i].Policy.IsDisabled {
			target = &users[i]
		}
	}
	if target == nil {
		http.Redirect(w, r, s.cfg.AdminBasePath+"/?n=user", http.StatusSeeOther)
		return
	}
	code, err := NewCode()
	if err != nil {
		http.Error(w, "Erreur interne", http.StatusInternalServerError)
		return
	}
	inv := &Invitation{
		ID:               randomID(),
		CodeHash:         HashCode(NormalizeCode(code)),
		JellyfinUserID:   target.ID,
		JellyfinUserName: target.Name,
		Label:            truncate(strings.TrimSpace(r.PostFormValue("label")), 60),
		CreatedAt:        now,
		CreatedBy:        sess.UserName,
		ExpiresAt:        now.Add(s.cfg.InviteValidity),
	}
	if err := s.store.Update(func(st *state) error {
		st.pruneInvitations(now)
		st.Invitations = append(st.Invitations, inv)
		st.log(now, "invited", inv.JellyfinUserName+labelSuffix(inv.Label)+" par "+sess.UserName, s.clientIP(r))
		return nil
	}); err != nil {
		http.Error(w, "Erreur d'enregistrement", http.StatusInternalServerError)
		return
	}
	p := s.dashboard(r.Context(), sess, "")
	p.Code = code
	p.Invitation = inv
	p.Message = inviteMessage(code, inv, s.cfg.PublicServerURL)
	s.render(w, "invite.html", p)
}

func labelSuffix(label string) string {
	if label == "" {
		return ""
	}
	return " (" + label + ")"
}

func inviteMessage(code string, inv *Invitation, _ string) string {
	return "Voici ton accès à OB Max :\n" +
		"1. Installe l'application : " + apkURL() + "\n" +
		"2. Ouvre-la et choisis « J'ai un code d'invitation ».\n" +
		"3. Saisis ce code : " + code + " (valable jusqu'au " + inv.ExpiresAt.In(paris).Format("02/01 à 15h04") + ", une seule fois).\n" +
		"4. Connecte-toi avec ton compte : " + inv.JellyfinUserName + "."
}

func apkURL() string {
	return env("ENROLL_APK_URL", "https://github.com/ollivv-hash/obmax-releases/releases/latest")
}

func (s *Server) handleCancel(w http.ResponseWriter, r *http.Request, _ string, sess *Session) {
	now := s.now()
	_ = s.store.Update(func(st *state) error {
		if inv := st.invitationByID(r.PathValue("id")); inv != nil && inv.Pending(now) {
			t := now
			inv.CanceledAt = &t
			st.log(now, "invite_canceled", inv.JellyfinUserName+labelSuffix(inv.Label)+" par "+sess.UserName, s.clientIP(r))
		}
		return nil
	})
	http.Redirect(w, r, s.cfg.AdminBasePath+"/?n=canceled", http.StatusSeeOther)
}

func (s *Server) handleRevoke(w http.ResponseWriter, r *http.Request, _ string, sess *Session) {
	now := s.now()
	_ = s.store.Update(func(st *state) error {
		if d := st.deviceByID(r.PathValue("id")); d != nil && d.RevokedAt == nil {
			t := now
			d.RevokedAt = &t
			d.RevokedBy = sess.UserName
			st.log(now, "revoked", d.JellyfinUserName+" : "+d.Name+" par "+sess.UserName, s.clientIP(r))
		}
		return nil
	})
	http.Redirect(w, r, s.cfg.AdminBasePath+"/?n=revoked", http.StatusSeeOther)
}

func (s *Server) handleRestore(w http.ResponseWriter, r *http.Request, _ string, sess *Session) {
	now := s.now()
	_ = s.store.Update(func(st *state) error {
		if d := st.deviceByID(r.PathValue("id")); d != nil && d.RevokedAt != nil {
			d.RevokedAt = nil
			d.RevokedBy = ""
			st.log(now, "restored", d.JellyfinUserName+" : "+d.Name+" par "+sess.UserName, s.clientIP(r))
		}
		return nil
	})
	http.Redirect(w, r, s.cfg.AdminBasePath+"/?n=restored", http.StatusSeeOther)
}
