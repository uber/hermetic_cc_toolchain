package main

import (
	_ "github.com/mattn/go-sqlite3"
)

// #include <stdio.h>
// char* hello() { return "hello, world\n"; }
// void printhello() { printf(hello()); }
import "C"

func main() {
	C.printhello()
}

func chello() string {
	return C.GoString(C.hello())
}
