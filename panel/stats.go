package main

import (
	"context"
	"fmt"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/encoding"
)

// statsCodec is a minimal protobuf codec for the V2Ray StatsService
// QueryStats request/response messages. It avoids depending on the full
// v2ray-core / sing-box generated code by hand-encoding the tiny wire format.
type statsCodec struct{}

func (statsCodec) Name() string { return "proto" }

type queryStatsRequest struct{}

type statEntry struct {
	Name  string
	Value int64
}

type queryStatsResponse struct {
	Stats []statEntry
}

func (statsCodec) Marshal(v any) ([]byte, error) {
	switch v.(type) {
	case *queryStatsRequest, queryStatsRequest:
		return []byte{}, nil
	default:
		return nil, fmt.Errorf("statsCodec: cannot marshal %T", v)
	}
}

func (statsCodec) Unmarshal(data []byte, v any) error {
	resp, ok := v.(*queryStatsResponse)
	if !ok {
		return fmt.Errorf("statsCodec: cannot unmarshal into %T", v)
	}
	resp.Stats = parseQueryStatsResponse(data)
	return nil
}

const (
	wireVarint  = 0
	wireFixed64 = 1
	wireBytes   = 2
	wireFixed32 = 5
)

func readVarint(b []byte) (uint64, int) {
	var v uint64
	for i := 0; i < len(b) && i < 10; i++ {
		c := b[i]
		v |= uint64(c&0x7f) << (7 * uint(i))
		if c < 0x80 {
			return v, i + 1
		}
	}
	return v, len(b)
}

func parseQueryStatsResponse(data []byte) []statEntry {
	var stats []statEntry
	for len(data) > 0 {
		field, wire, n := readTag(data)
		if n <= 0 {
			break
		}
		data = data[n:]
		switch wire {
		case wireVarint:
			_, n := readVarint(data)
			data = data[n:]
		case wireFixed64:
			if len(data) < 8 {
				return stats
			}
			data = data[8:]
		case wireBytes:
			l, n := readVarint(data)
			if n <= 0 || uint64(len(data)-n) < l {
				return stats
			}
			data = data[n:]
			payload := data[:l]
			data = data[l:]
			if field == 1 {
				stats = append(stats, parseStat(payload))
			}
		case wireFixed32:
			if len(data) < 4 {
				return stats
			}
			data = data[4:]
		default:
			return stats
		}
	}
	return stats
}

func parseStat(data []byte) statEntry {
	var s statEntry
	for len(data) > 0 {
		field, wire, n := readTag(data)
		if n <= 0 {
			break
		}
		data = data[n:]
		switch wire {
		case wireVarint:
			val, n := readVarint(data)
			data = data[n:]
			if field == 2 {
				s.Value = int64(val)
			}
		case wireBytes:
			l, n := readVarint(data)
			if n <= 0 || uint64(len(data)-n) < l {
				return s
			}
			data = data[n:]
			if field == 1 {
				s.Name = string(data[:l])
			}
			data = data[l:]
		case wireFixed64:
			if len(data) < 8 {
				return s
			}
			data = data[8:]
		case wireFixed32:
			if len(data) < 4 {
				return s
			}
			data = data[4:]
		default:
			return s
		}
	}
	return s
}

func readTag(b []byte) (field int, wire int, n int) {
	v, n := readVarint(b)
	if n <= 0 {
		return 0, 0, 0
	}
	return int(v >> 3), int(v & 7), n
}

const statsMethod = "/v2ray.core.app.stats.command.StatsService/QueryStats"

type statsSource struct {
	addr string
	conn *grpc.ClientConn
}

func newStatsSource(addr string) (*statsSource, error) {
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	return &statsSource{addr: addr, conn: conn}, nil
}

// query returns all stat counters keyed by name.
func (s *statsSource) query(ctx context.Context) (map[string]int64, error) {
	var resp queryStatsResponse
	if err := s.conn.Invoke(ctx, statsMethod, &queryStatsRequest{}, &resp, grpc.ForceCodec(statsCodec{})); err != nil {
		return nil, err
	}
	m := make(map[string]int64, len(resp.Stats))
	for _, st := range resp.Stats {
		m[st.Name] = st.Value
	}
	return m, nil
}

func (s *statsSource) Close() error {
	return s.conn.Close()
}

var _ encoding.Codec = statsCodec{}
