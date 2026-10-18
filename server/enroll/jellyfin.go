package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"time"
)

// JellyfinClient is the little of the Jellyfin API the admin page needs:
// sign in an administrator and list the accounts invitations can target.
type JellyfinClient struct {
	base string
	http *http.Client
}

func NewJellyfinClient(base string) *JellyfinClient {
	return &JellyfinClient{base: base, http: &http.Client{Timeout: 15 * time.Second}}
}

const jellyfinAuthHeader = `MediaBrowser Client="OB Max Enroll", Device="Service d'activation", DeviceId="obmax-enroll", Version="1.0"`

type JellyfinUser struct {
	ID     string `json:"Id"`
	Name   string `json:"Name"`
	Policy struct {
		IsAdministrator bool `json:"IsAdministrator"`
		IsDisabled      bool `json:"IsDisabled"`
	} `json:"Policy"`
}

var errNotAdmin = errors.New("not an administrator")

// AuthenticateAdmin signs in and returns the user and an access token, only
// for an enabled administrator.
func (c *JellyfinClient) AuthenticateAdmin(ctx context.Context, username, password string) (*JellyfinUser, string, error) {
	body, _ := json.Marshal(map[string]string{"Username": username, "Pw": password})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/Users/AuthenticateByName", bytes.NewReader(body))
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", jellyfinAuthHeader)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
		return nil, "", errNotAdmin
	}
	if resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("jellyfin: HTTP %d", resp.StatusCode)
	}
	var out struct {
		User        JellyfinUser `json:"User"`
		AccessToken string       `json:"AccessToken"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, "", err
	}
	if !out.User.Policy.IsAdministrator || out.User.Policy.IsDisabled {
		c.Logout(ctx, out.AccessToken)
		return nil, "", errNotAdmin
	}
	return &out.User, out.AccessToken, nil
}

// Users lists the Jellyfin accounts, sorted by name.
func (c *JellyfinClient) Users(ctx context.Context, token string) ([]JellyfinUser, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.base+"/Users", nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", jellyfinAuthHeader+`, Token="`+token+`"`)
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("jellyfin: HTTP %d", resp.StatusCode)
	}
	var users []JellyfinUser
	if err := json.NewDecoder(resp.Body).Decode(&users); err != nil {
		return nil, err
	}
	sort.Slice(users, func(i, j int) bool { return users[i].Name < users[j].Name })
	return users, nil
}

// Logout ends the Jellyfin session the admin page opened.
func (c *JellyfinClient) Logout(ctx context.Context, token string) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base+"/Sessions/Logout", nil)
	if err != nil {
		return
	}
	req.Header.Set("Authorization", jellyfinAuthHeader+`, Token="`+token+`"`)
	if resp, err := c.http.Do(req); err == nil {
		resp.Body.Close()
	}
}
