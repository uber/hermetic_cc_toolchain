package main

import (
	_ "github.com/DataDog/zstd"
	_ "github.com/mattn/go-sqlite3"
)

// #include <stdio.h>
// void helloworld() { printf("hello, world\n"); }
import "C"

func main() {
	C.helloworld()
}
