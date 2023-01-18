package main

// #define _FILE_OFFSET_BITS 64
// #include <unistd.h>
// #include <fcntl.h>
// #include <stdio.h>
// #include <resolv.h>
// char* hello() { return "hello, world"; }
// void phello() { printf("%s, your lucky numbers are %p and %p\n", hello(), fcntl, res_search); }
import "C"

func main() {
	C.phello()
}

func Chello() string {
	return C.GoString(C.hello())
}
