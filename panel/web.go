package main

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed web
var webFS embed.FS

func webHandler() http.Handler {
	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		panic(err)
	}
	return http.FileServer(http.FS(sub))
}

func serveLoginPage(w http.ResponseWriter, _ *http.Request) {
	data, err := webFS.ReadFile("web/login.html")
	if err != nil {
		http.Error(w, "login page missing", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write(data)
}
