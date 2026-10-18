package main

import (
	"sync"
	"time"
)

// FailureLimiter counts failed attempts in a sliding window, per key and
// overall. A key over its limit is refused until its oldest failure leaves
// the window; past the global limit everything is refused for a cool-down.
type FailureLimiter struct {
	mu           sync.Mutex
	window       time.Duration
	perKey       int
	global       int
	globalPause  time.Duration
	failures     map[string][]time.Time
	all          []time.Time
	pausedUntil  time.Time
}

func NewFailureLimiter(window time.Duration, perKey, global int, globalPause time.Duration) *FailureLimiter {
	return &FailureLimiter{
		window:      window,
		perKey:      perKey,
		global:      global,
		globalPause: globalPause,
		failures:    map[string][]time.Time{},
	}
}

func prune(ts []time.Time, cutoff time.Time) []time.Time {
	i := 0
	for i < len(ts) && !ts[i].After(cutoff) {
		i++
	}
	return ts[i:]
}

// Allowed reports whether key may try now.
func (l *FailureLimiter) Allowed(key string, now time.Time) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	if now.Before(l.pausedUntil) {
		return false
	}
	cutoff := now.Add(-l.window)
	l.failures[key] = prune(l.failures[key], cutoff)
	if len(l.failures[key]) == 0 {
		delete(l.failures, key)
	}
	return len(l.failures[key]) < l.perKey
}

// Fail records a failed attempt for key.
func (l *FailureLimiter) Fail(key string, now time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	cutoff := now.Add(-l.window)
	l.failures[key] = append(prune(l.failures[key], cutoff), now)
	l.all = append(prune(l.all, cutoff), now)
	if l.global > 0 && len(l.all) >= l.global {
		l.pausedUntil = now.Add(l.globalPause)
		l.all = nil
	}
}
