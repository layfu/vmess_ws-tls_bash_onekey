package main

import "testing"

func TestFormatRegion(t *testing.T) {
	cases := map[string]string{
		"中国|河北省|石家庄市|联通|CN":       "中国-河北-石家庄 联通",
		"中国|福建省|福州市|中国电信|CN":      "中国-福建-福州 中国电信",
		"United States|California|0|0|US": "United States-California",
		"中国|0|0|0|CN":                 "中国",
		"0|0|0|0|0":                    "",
		"":                             "",
	}
	for in, want := range cases {
		if got := formatRegion(in); got != want {
			t.Errorf("formatRegion(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestCleanRegionField(t *testing.T) {
	cases := map[string]string{
		"河北省": "河北",
		"石家庄市": "石家庄",
		"中国":  "中国",
		"0":   "",
		"":    "",
		" 市 ": "",
	}
	for in, want := range cases {
		if got := cleanRegionField(in); got != want {
			t.Errorf("cleanRegionField(%q) = %q, want %q", in, got, want)
		}
	}
}
