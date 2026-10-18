package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Invitation is a one-time code for one device of one Jellyfin account.
// Only the code's hash is kept.
type Invitation struct {
	ID               string     `json:"id"`
	CodeHash         string     `json:"codeHash"`
	JellyfinUserID   string     `json:"jellyfinUserId"`
	JellyfinUserName string     `json:"jellyfinUserName"`
	Label            string     `json:"label"`
	CreatedAt        time.Time  `json:"createdAt"`
	CreatedBy        string     `json:"createdBy"`
	ExpiresAt        time.Time  `json:"expiresAt"`
	UsedAt           *time.Time `json:"usedAt,omitempty"`
	DeviceID         string     `json:"deviceId,omitempty"`
	CanceledAt       *time.Time `json:"canceledAt,omitempty"`
}

func (i *Invitation) Pending(now time.Time) bool {
	return i.UsedAt == nil && i.CanceledAt == nil && now.Before(i.ExpiresAt)
}

// Device is one enrolled device and its current certificate.
type Device struct {
	ID               string     `json:"id"`
	JellyfinUserID   string     `json:"jellyfinUserId"`
	JellyfinUserName string     `json:"jellyfinUserName"`
	Label            string     `json:"label"`
	Name             string     `json:"name"`
	Platform         string     `json:"platform"`
	AppVersion       string     `json:"appVersion"`
	PublicKeyHash    string     `json:"publicKeyHash"`
	Serial           string     `json:"serial"`
	PreviousSerial   string     `json:"previousSerial,omitempty"`
	NotAfter         time.Time  `json:"notAfter"`
	EnrolledAt       time.Time  `json:"enrolledAt"`
	LastRenewedAt    *time.Time `json:"lastRenewedAt,omitempty"`
	RevokedAt        *time.Time `json:"revokedAt,omitempty"`
	RevokedBy        string     `json:"revokedBy,omitempty"`
}

// Event is one line of the admin journal.
type Event struct {
	At     time.Time `json:"at"`
	Kind   string    `json:"kind"`
	Detail string    `json:"detail"`
	IP     string    `json:"ip,omitempty"`
}

type state struct {
	Invitations []*Invitation `json:"invitations"`
	Devices     []*Device     `json:"devices"`
	Events      []*Event      `json:"events"`
}

const maxEvents = 500

// Store keeps the state in one JSON file, rewritten atomically on every
// change. A few dozen devices make a database pointless.
type Store struct {
	mu   sync.Mutex
	path string
	s    state
}

func OpenStore(path string) (*Store, error) {
	st := &Store{path: path}
	data, err := os.ReadFile(path)
	switch {
	case errors.Is(err, os.ErrNotExist):
		return st, nil
	case err != nil:
		return nil, err
	}
	if err := json.Unmarshal(data, &st.s); err != nil {
		return nil, err
	}
	return st, nil
}

// Update runs fn under the lock and saves if it returns nil.
func (st *Store) Update(fn func(s *state) error) error {
	st.mu.Lock()
	defer st.mu.Unlock()
	if err := fn(&st.s); err != nil {
		return err
	}
	return st.saveLocked()
}

// View runs fn under the lock, read-only.
func (st *Store) View(fn func(s *state)) {
	st.mu.Lock()
	defer st.mu.Unlock()
	fn(&st.s)
}

func (st *Store) saveLocked() error {
	if len(st.s.Events) > maxEvents {
		st.s.Events = st.s.Events[len(st.s.Events)-maxEvents:]
	}
	data, err := json.MarshalIndent(&st.s, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(st.path), ".state-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), st.path)
}

func (s *state) invitationByHash(hash string) *Invitation {
	for _, inv := range s.Invitations {
		if inv.CodeHash == hash {
			return inv
		}
	}
	return nil
}

func (s *state) invitationByID(id string) *Invitation {
	for _, inv := range s.Invitations {
		if inv.ID == id {
			return inv
		}
	}
	return nil
}

func (s *state) deviceByID(id string) *Device {
	for _, d := range s.Devices {
		if d.ID == id {
			return d
		}
	}
	return nil
}

func (s *state) log(now time.Time, kind, detail, ip string) {
	s.Events = append(s.Events, &Event{At: now, Kind: kind, Detail: detail, IP: ip})
}

// pruneInvitations drops invitations that ended more than 30 days ago.
func (s *state) pruneInvitations(now time.Time) {
	keep := s.Invitations[:0]
	for _, inv := range s.Invitations {
		end := inv.ExpiresAt
		if inv.UsedAt != nil {
			end = *inv.UsedAt
		}
		if inv.CanceledAt != nil {
			end = *inv.CanceledAt
		}
		if now.Sub(end) < 30*24*time.Hour {
			keep = append(keep, inv)
		}
	}
	s.Invitations = keep
}

func (s *state) recentEvents(n int) []*Event {
	out := make([]*Event, 0, n)
	for i := len(s.Events) - 1; i >= 0 && len(out) < n; i-- {
		out = append(out, s.Events[i])
	}
	return out
}

func (s *state) sortedDevices() []*Device {
	out := append([]*Device(nil), s.Devices...)
	sort.Slice(out, func(i, j int) bool {
		if out[i].JellyfinUserName != out[j].JellyfinUserName {
			return out[i].JellyfinUserName < out[j].JellyfinUserName
		}
		return out[i].EnrolledAt.Before(out[j].EnrolledAt)
	})
	return out
}

func randomID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
