package main

import (
	"net/http"
	"log"
	"strconv"
	"runtime"
)

var Data = []byte("hello,world!\n")
var Data_len = strconv.Itoa(len(Data))

func handler(w http.ResponseWriter, r *http.Request) {
	var headers = w.Header()
	headers.Set("Content-Type", "text/plain")
	headers.Set("Content-Length", Data_len)
	// Can't disable generation of "Date" header.
	//headers.Set("Date", "")
	//headers.Set("Server", "Bench")
	w.Write(Data)
}

func main() {
	runtime.GOMAXPROCS(2)
	s := &http.Server{
		Addr: ":1080",
		MaxHeaderBytes: 1 << 20,
	}
	http.HandleFunc("/", handler)
	log.Fatal(s.ListenAndServe())
}
