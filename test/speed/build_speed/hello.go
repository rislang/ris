// The Go side of the head-to-head in `test/speed/build_speed.py`.
//
// Deliberately the same shape as `samples/ris/hello_iyi.ri`'s output and nothing
// more: this pair exists to time the compilers, not the programs.
package main

import "fmt"

func main() {
	fmt.Println("Hello, iyi!")
}
