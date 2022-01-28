package main

// #include <stdio.h>
// char* hello() { return "hello, world"; }
// void printhello() { printf("%s\n", hello()); }
import "C"

func main() {
	C.printhello()
}

func chello() string {
	return C.GoString(C.hello())
}
