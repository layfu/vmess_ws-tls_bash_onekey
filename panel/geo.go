package main

import (
	"log"
	"net"
	"net/netip"
	"strings"
	"sync"

	"github.com/lionsoul2014/ip2region/binding/golang/xdb"
)

// geoLookup resolves a source address to a human-readable region using an
// offline ip2region xdb file. It is safe for concurrent use.
type geoLookup struct {
	mu sync.Mutex
	v4 *xdb.Searcher
}

func newGeoLookup(dbFile string) *geoLookup {
	g := &geoLookup{}
	if dbFile == "" {
		return g
	}
	buf, err := xdb.LoadContentFromFile(dbFile)
	if err != nil {
		log.Printf("geo: load %s: %v", dbFile, err)
		return g
	}
	v4, err := xdb.NewWithBuffer(xdb.IPv4, buf)
	if err != nil {
		log.Printf("geo: init searcher: %v", err)
		return g
	}
	g.v4 = v4
	return g
}

// lookup returns a region string for the given address, e.g.
// "中国-河北-石家庄 联通", or "" if the address is not public IPv4 or is unknown.
func (g *geoLookup) lookup(addr string) string {
	if g == nil || g.v4 == nil {
		return ""
	}
	host := addr
	if h, _, err := net.SplitHostPort(addr); err == nil {
		host = h
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return ""
	}
	if !ip.Is4() || ip.IsPrivate() || ip.IsLoopback() || ip.IsUnspecified() || ip.IsLinkLocalUnicast() {
		return ""
	}
	g.mu.Lock()
	region, err := g.v4.Search(ip.String())
	g.mu.Unlock()
	if err != nil {
		return ""
	}
	return formatRegion(region)
}

// formatRegion converts an ip2region region string
// "Country|Province|City|ISP|iso" into "Country-Province-City ISP".
func formatRegion(s string) string {
	parts := strings.Split(s, "|")
	if len(parts) < 3 {
		return ""
	}
	country := cleanRegionField(parts[0])
	province := cleanRegionField(parts[1])
	city := cleanRegionField(parts[2])
	isp := ""
	if len(parts) > 3 {
		isp = cleanRegionField(parts[3])
	}
	var loc []string
	if country != "" {
		loc = append(loc, country)
	}
	if province != "" && province != country {
		loc = append(loc, province)
	}
	if city != "" && city != province && city != country {
		loc = append(loc, city)
	}
	out := strings.Join(loc, "-")
	if isp != "" {
		out += " " + isp
	}
	return out
}

func cleanRegionField(s string) string {
	s = strings.TrimSpace(s)
	if s == "" || s == "0" {
		return ""
	}
	s = strings.TrimSuffix(strings.TrimSuffix(s, "市"), "省")
	return s
}
