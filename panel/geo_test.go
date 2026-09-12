package main

import "testing"

func TestFormatRegion(t *testing.T) {
	cases := map[string]string{
		"中国|河北省|石家庄市|联通|CN":               "中国-河北-石家庄 联通",
		"中国|福建省|福州市|中国电信|CN":              "中国-福建-福州 中国电信",
		"United States|California|0|0|US": "United States-California",
		"中国|0|0|0|CN":                     "中国",
		"0|0|0|0|0":                       "",
		"":                                "",
	}
	for in, want := range cases {
		if got := formatRegion(in); got != want {
			t.Errorf("formatRegion(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCleanRegionField(t *testing.T) {
	cases := map[string]string{
		"河北省":  "河北",
		"石家庄市": "石家庄",
		"中国":   "中国",
		"0":    "",
		"":     "",
		" 市 ":  "",
	}
	for in, want := range cases {
		if got := cleanRegionField(in); got != want {
			t.Errorf("cleanRegionField(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestParseRegionFields(t *testing.T) {
	f := parseRegionFields("中国|河北省|石家庄市|联通|CN")
	if f.country != "中国" || f.province != "河北" || f.city != "石家庄" || f.isp != "联通" || f.iso != "CN" {
		t.Errorf("fields = %+v", f)
	}
	if got := parseRegionFields(""); got != (regionFields{}) {
		t.Errorf("empty fields = %+v", got)
	}
}

func TestCoordForRegion(t *testing.T) {
	cases := []struct {
		region string
		ok     bool
	}{
		{"中国|河北省|石家庄市|联通|CN", true},
		{"中国|内蒙古自治区|呼和浩特市|联通|CN", true},
		{"United States|California|0|0|US", true},
		{"中国|0|0|0|CN", true},
		{"0|0|0|0|0", false},
		{"Nowhere|Nowhere|0|0|ZZ", false},
	}
	for _, c := range cases {
		lat, lng, ok := coordForRegion(parseRegionFields(c.region))
		if ok != c.ok {
			t.Errorf("coordForRegion(%q) ok = %v, want %v", c.region, ok, c.ok)
			continue
		}
		if ok && (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
			t.Errorf("coordForRegion(%q) out of range: %v,%v", c.region, lat, lng)
		}
	}

	// Chinese provinces resolve to the province capital, not the country centroid.
	lat, lng, ok := coordForRegion(parseRegionFields("中国|河北省|石家庄市|联通|CN"))
	if !ok || lat < 36 || lat > 41 || lng < 112 || lng > 117 {
		t.Errorf("Hebei coord = %v,%v ok=%v", lat, lng, ok)
	}
}
