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

// rawRegion returns the raw ip2region record for the given address, e.g.
// "中国|河北省|石家庄市|联通|CN", or false if the address is not public IPv4
// or is unknown.
func (g *geoLookup) rawRegion(addr string) (string, bool) {
	if g == nil || g.v4 == nil {
		return "", false
	}
	host := addr
	if h, _, err := net.SplitHostPort(addr); err == nil {
		host = h
	}
	ip, err := netip.ParseAddr(host)
	if err != nil {
		return "", false
	}
	if !ip.Is4() || ip.IsPrivate() || ip.IsLoopback() || ip.IsUnspecified() || ip.IsLinkLocalUnicast() {
		return "", false
	}
	g.mu.Lock()
	region, err := g.v4.Search(ip.String())
	g.mu.Unlock()
	if err != nil {
		return "", false
	}
	return region, true
}

// lookup returns a region string for the given address, e.g.
// "中国-河北-石家庄 联通", or "" if the address is not public IPv4 or is unknown.
func (g *geoLookup) lookup(addr string) string {
	region, ok := g.rawRegion(addr)
	if !ok {
		return ""
	}
	return formatRegion(region)
}

// regionFields holds the parsed fields of an ip2region record.
type regionFields struct {
	country  string
	province string
	city     string
	isp      string
	iso      string
}

func parseRegionFields(region string) regionFields {
	parts := strings.Split(region, "|")
	get := func(i int) string {
		if i < len(parts) {
			return cleanRegionField(parts[i])
		}
		return ""
	}
	return regionFields{
		country:  get(0),
		province: get(1),
		city:     get(2),
		isp:      get(3),
		iso:      strings.ToUpper(get(4)),
	}
}

// lookupPoint resolves an address to a display region plus coarse coordinates
// (country centroid, or Chinese province capital), used to place clients on the
// globe. ok is false when the address is unknown or has no coordinate entry.
func (g *geoLookup) lookupPoint(addr string) (region string, lat, lng float64, ok bool) {
	raw, found := g.rawRegion(addr)
	if !found {
		return "", 0, 0, false
	}
	region = formatRegion(raw)
	lat, lng, ok = coordForRegion(parseRegionFields(raw))
	return region, lat, lng, ok
}

// coordForRegion picks a coordinate for the given region fields, preferring the
// Chinese province for CN addresses and falling back to the country centroid.
func coordForRegion(f regionFields) (lat, lng float64, ok bool) {
	if f.iso == "CN" || f.country == "中国" {
		for name, c := range provinceCoords {
			if f.province == name || strings.HasPrefix(f.province, name) {
				return c[0], c[1], true
			}
		}
	}
	if c, found := countryCoords[f.iso]; found {
		return c[0], c[1], true
	}
	return 0, 0, false
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
