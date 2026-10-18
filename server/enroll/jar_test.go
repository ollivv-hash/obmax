package main

import (
	"net/http"
	"net/http/cookiejar"
)

// newJar keeps the admin session cookie. Test servers run over plain HTTP,
// so the cookie's Secure flag is dropped by the config (SecureCookies false).
func newJar() http.CookieJar {
	j, _ := cookiejar.New(nil)
	return j
}
