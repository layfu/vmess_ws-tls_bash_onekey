package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

var version = "dev"

func main() {
	configPath := flag.String("c", "/etc/panel/config.json", "config file path")
	showVersion := flag.Bool("v", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}

	cfg, err := loadConfig(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	st, err := openStore(cfg.DBPath)
	if err != nil {
		log.Fatalf("open store: %v", err)
	}
	defer st.Close()

	col, err := newCollector(st, cfg, cfg.OnlineWindowSec)
	if err != nil {
		log.Fatalf("collector: %v", err)
	}
	defer col.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go col.run(ctx, time.Duration(cfg.PollIntervalSec)*time.Second)
	startLogTailers(st, cfg)

	st.prune(24*time.Hour, 20000)
	st.pruneHourly(time.Duration(cfg.RetentionDays) * 24 * time.Hour)
	go func() {
		t := time.NewTicker(time.Hour)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				st.prune(24*time.Hour, 20000)
				st.pruneHourly(time.Duration(cfg.RetentionDays) * 24 * time.Hour)
			}
		}
	}()

	a := &api{store: st, cfg: cfg, onlineWin: int64(cfg.OnlineWindowSec), geo: newGeoLookup(cfg.GeoDB)}

	auth, err := newAuthenticator(cfg)
	if err != nil {
		log.Fatalf("auth: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/login", serveLoginPage)
	mux.HandleFunc("/api/login", auth.login)
	mux.HandleFunc("/api/logout", auth.logout)
	mux.HandleFunc("/api/overview", a.overview)
	mux.HandleFunc("/api/traffic", a.traffic)
	mux.HandleFunc("/api/connections", a.connections)
	mux.HandleFunc("/api/history", a.history)
	mux.HandleFunc("/api/configs", a.configs)
	mux.HandleFunc("/api/health", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})
	mux.Handle("/", webHandler())

	srv := &http.Server{Addr: cfg.Listen, Handler: auth.middleware(mux)}
	go func() {
		log.Printf("panel listening on %s", cfg.Listen)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("http server: %v", err)
		}
	}()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	log.Println("shutting down")
	cancel()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	_ = srv.Shutdown(shutdownCtx)
}
