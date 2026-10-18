package main

import (
	"bytes"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"
)

// CA is the OB Max Enrollment CA: the intermediate that signs device
// certificates. The root stays offline.
type CA struct {
	Cert    *x509.Certificate
	key     crypto.Signer
	certPEM []byte
	pool    *x509.CertPool
}

// LoadCA reads the intermediate certificate and its private key (PEM, EC
// in SEC 1 or PKCS#8).
func LoadCA(certPath, keyPath string) (*CA, error) {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("read CA certificate: %w", err)
	}
	block, _ := pem.Decode(certPEM)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, errors.New("CA certificate: no PEM certificate block")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("parse CA certificate: %w", err)
	}
	if !cert.IsCA {
		return nil, errors.New("CA certificate is not a CA (basicConstraints CA:true missing)")
	}

	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("read CA key: %w", err)
	}
	key, err := parsePrivateKey(keyPEM)
	if err != nil {
		return nil, err
	}
	pub, ok := key.Public().(*ecdsa.PublicKey)
	certPub, ok2 := cert.PublicKey.(*ecdsa.PublicKey)
	if !ok || !ok2 || !pub.Equal(certPub) {
		return nil, errors.New("CA key does not match the CA certificate")
	}

	pool := x509.NewCertPool()
	pool.AddCert(cert)
	return &CA{
		Cert:    cert,
		key:     key,
		certPEM: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw}),
		pool:    pool,
	}, nil
}

func parsePrivateKey(data []byte) (crypto.Signer, error) {
	for {
		var block *pem.Block
		block, data = pem.Decode(data)
		if block == nil {
			return nil, errors.New("CA key: no PEM private key block")
		}
		switch block.Type {
		case "EC PRIVATE KEY":
			return x509.ParseECPrivateKey(block.Bytes)
		case "PRIVATE KEY":
			k, err := x509.ParsePKCS8PrivateKey(block.Bytes)
			if err != nil {
				return nil, err
			}
			s, ok := k.(crypto.Signer)
			if !ok {
				return nil, errors.New("CA key: unsupported key type")
			}
			return s, nil
		}
		// "EC PARAMETERS" and the like come first in openssl output: skip.
	}
}

// ParseCSR decodes a PEM certificate request, checks its self-signature
// (the proof the requester holds the private key) and requires EC P-256.
func ParseCSR(csrPEM string) (*x509.CertificateRequest, error) {
	block, _ := pem.Decode([]byte(strings.TrimSpace(csrPEM)))
	if block == nil || block.Type != "CERTIFICATE REQUEST" {
		return nil, errors.New("csr: no PEM certificate request")
	}
	csr, err := x509.ParseCertificateRequest(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("csr: %w", err)
	}
	if err := csr.CheckSignature(); err != nil {
		return nil, fmt.Errorf("csr signature: %w", err)
	}
	pub, ok := csr.PublicKey.(*ecdsa.PublicKey)
	if !ok || pub.Curve != elliptic.P256() {
		return nil, errors.New("csr: EC P-256 key required")
	}
	return csr, nil
}

// Issue signs a device certificate for the CSR's public key. The subject is
// set here, never taken from the CSR.
func (ca *CA) Issue(csr *x509.CertificateRequest, commonName string, validity time.Duration, now time.Time) (*x509.Certificate, error) {
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, err
	}
	notBefore := now.Add(-5 * time.Minute) // TV clocks drift
	notAfter := now.Add(validity)
	if notAfter.After(ca.Cert.NotAfter) {
		notAfter = ca.Cert.NotAfter
	}
	tmpl := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: commonName, Organization: []string{"OB Max"}},
		NotBefore:             notBefore,
		NotAfter:              notAfter,
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
		BasicConstraintsValid: true,
		IsCA:                  false,
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, ca.Cert, csr.PublicKey, ca.key)
	if err != nil {
		return nil, err
	}
	return x509.ParseCertificate(der)
}

// ChainPEM is the device certificate followed by the intermediate, as the
// app presents it.
func (ca *CA) ChainPEM(leaf *x509.Certificate) string {
	var b bytes.Buffer
	_ = pem.Encode(&b, &pem.Block{Type: "CERTIFICATE", Bytes: leaf.Raw})
	b.Write(ca.certPEM)
	return b.String()
}

// VerifyLeaf parses a PEM chain and checks that its first certificate was
// issued by this CA, for client authentication, and is valid at now.
func (ca *CA) VerifyLeaf(chainPEM string, now time.Time) (*x509.Certificate, error) {
	block, _ := pem.Decode([]byte(strings.TrimSpace(chainPEM)))
	if block == nil || block.Type != "CERTIFICATE" {
		return nil, errors.New("certificate: no PEM certificate")
	}
	leaf, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, err
	}
	_, err = leaf.Verify(x509.VerifyOptions{
		Roots:       ca.pool,
		CurrentTime: now,
		KeyUsages:   []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	})
	if err != nil {
		return nil, err
	}
	return leaf, nil
}

// SPKIHash identifies a public key (SHA-256 of its SubjectPublicKeyInfo).
func SPKIHash(pub any) (string, error) {
	der, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(der)
	return hex.EncodeToString(sum[:]), nil
}

func serialHex(c *x509.Certificate) string { return c.SerialNumber.Text(16) }
