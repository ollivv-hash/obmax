package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"math/big"
	"strings"
)

// Crockford base32: no I, L, O or U, so a code read out or typed on a TV
// remote has nothing ambiguous in it.
const codeAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const codeLength = 12 // 60 bits

// NewCode returns a code formatted XXXX-XXXX-XXXX.
func NewCode() (string, error) {
	var b strings.Builder
	max := big.NewInt(int64(len(codeAlphabet)))
	for i := 0; i < codeLength; i++ {
		if i > 0 && i%4 == 0 {
			b.WriteByte('-')
		}
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b.WriteByte(codeAlphabet[n.Int64()])
	}
	return b.String(), nil
}

// NormalizeCode uppercases, drops separators and maps the letters people
// type for the missing ones (O→0, I/L→1), as Crockford intends.
func NormalizeCode(code string) string {
	var b strings.Builder
	for _, r := range strings.ToUpper(code) {
		switch {
		case r == 'O':
			b.WriteByte('0')
		case r == 'I' || r == 'L':
			b.WriteByte('1')
		case r == '-' || r == ' ' || r == '_':
			continue
		case strings.ContainsRune(codeAlphabet, r):
			b.WriteRune(r)
		default:
			return "" // anything else cannot be a code
		}
	}
	if b.Len() != codeLength {
		return ""
	}
	return b.String()
}

func HashCode(normalized string) string {
	sum := sha256.Sum256([]byte("obmax-invite:" + normalized))
	return hex.EncodeToString(sum[:])
}
