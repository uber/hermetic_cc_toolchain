package main

import "github.com/google/zopfli/go/zopfli"

// Gzip compresses a byte array with zopfli.
//
// We use a separate file, because we can make Gazelle ignore it.
func Gzip(in []byte) []byte {
	return zopfli.Gzip(in)
}
