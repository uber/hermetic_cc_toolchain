package main

// #include <stdio.h>
// void helloworld() { printf("hello, world\n"); }
import "C"

func main() {
	C.helloworld()
}
