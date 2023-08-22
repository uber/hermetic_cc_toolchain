// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

package main

// #include <stdio.h>
// char* hello() { return "hello, world"; }
// void phello() { printf("%s\n", hello()); }
import "C"

func main() {
	C.phello()
}

func Chello() string {
	return C.GoString(C.hello())
}
