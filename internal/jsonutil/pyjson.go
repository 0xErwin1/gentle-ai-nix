// Package jsonutil reproduces the exact byte encoding CPython's
// json.dumps(value, sort_keys=True) produces for a small class of values,
// so a digest computed here matches one Python once computed for the same
// data. Go's encoding/json is not a drop-in: it omits the space Python's
// default separators (", " and ": ") put after every comma and colon, and
// it does not escape non-ASCII runes the way Python's ensure_ascii=True
// default does. Either difference would change the hash.
package jsonutil

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
)

// SHA256Hex is hashlib.sha256(data).hexdigest(): the lowercase hex
// encoding of the SHA-256 digest of data.
func SHA256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// EncodeCommands renders a list of argv-shaped string lists the same way
// lib/provision.py's digest_of renders it: as a JSON array of arrays of
// strings, using Python's default json.dumps separators and escaping.
//
// Only strings and lists of strings ever occur in a manifest's declared
// commands, so this does not need to handle numbers, booleans, or nested
// objects: a provision resource's "commands" field is always argv lists.
func EncodeCommands(commands [][]string) []byte {
	var b strings.Builder
	b.WriteByte('[')
	for i, command := range commands {
		if i > 0 {
			b.WriteString(", ")
		}
		encodeStringArray(&b, command)
	}
	b.WriteByte(']')
	return []byte(b.String())
}

func encodeStringArray(b *strings.Builder, values []string) {
	b.WriteByte('[')
	for i, value := range values {
		if i > 0 {
			b.WriteString(", ")
		}
		encodeString(b, value)
	}
	b.WriteByte(']')
}

// encodeString writes value as a JSON string literal the way Python's
// json.dumps does with its default ensure_ascii=True: a byte-value escape
// for the usual control characters, \" and \\ escaped, and every rune
// outside ASCII rendered as a \uXXXX escape (a surrogate pair above the
// Basic Multilingual Plane) rather than emitted as raw UTF-8.
func encodeString(b *strings.Builder, value string) {
	b.WriteByte('"')
	for _, r := range value {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		default:
			switch {
			case r < 0x20:
				fmt.Fprintf(b, `\u%04x`, r)
			case r < 0x7f:
				b.WriteRune(r)
			case r <= 0xffff:
				fmt.Fprintf(b, `\u%04x`, r)
			default:
				// Outside the Basic Multilingual Plane: Python encodes as a
				// UTF-16 surrogate pair, each half its own \uXXXX escape.
				r -= 0x10000
				high := 0xd800 + (r >> 10)
				low := 0xdc00 + (r & 0x3ff)
				fmt.Fprintf(b, `\u%04x\u%04x`, high, low)
			}
		}
	}
	b.WriteByte('"')
}
