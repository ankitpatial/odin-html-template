#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

BENCHTIME="${BENCHTIME:-2s}"
COUNT="${COUNT:-3}"

echo "========================================="
echo "  Config: BENCHTIME=${BENCHTIME}  COUNT=${COUNT}"
echo "  (override with BENCHTIME=5s COUNT=5 ./bench/run.sh)"
echo "========================================="

echo ""
echo "========================================="
echo "  Building Odin benchmark (-o:speed)..."
echo "========================================="
odin build bench/odin_bench/ -collection:ohtml=. -o:speed -out:bench/odin_bench/bench

echo ""
echo "========================================="
echo "  Running Odin benchmark (${COUNT} runs)..."
echo "========================================="
# Run COUNT times, collect all lines, then average per benchmark
ODIN_ALL=$(mktemp)
for i in $(seq 1 "$COUNT"); do
  echo "  run $i/$COUNT"
  bench/odin_bench/bench 2>&1 >> "$ODIN_ALL"
done
# Show last run for reference
echo ""
tail -20 "$ODIN_ALL" | head -15

echo ""
echo "========================================="
echo "  Running Go benchmark..."
echo "  flags: -benchtime=${BENCHTIME} -count=${COUNT}"
echo "         -benchmem -ldflags=\"-s -w\""
echo "========================================="
GO_OUT=$(cd bench/go_bench && go test -bench=. \
  -benchtime="$BENCHTIME" \
  -count="$COUNT" \
  -benchmem \
  -ldflags="-s -w" \
  2>&1)
echo "$GO_OUT"

# --- Parse results into temp files ---
ODIN_TMP=$(mktemp)
GO_TMP=$(mktemp)
trap "rm -f '$ODIN_ALL' '$ODIN_TMP' '$GO_TMP' bench/odin_bench/bench" EXIT

# Odin: average ns/op across COUNT runs per benchmark name
# Format: "ExecSimple  01338912 ops  0000000788 ns/op  (...)"
awk '$5=="ns/op" {
  v=$4; sub(/^0+/,"",v); if(v=="") v="0"
  sum[$1]+=v; n[$1]++
}
END {
  for(name in sum) printf "%s %d\n", name, sum[name]/n[name]
}' "$ODIN_ALL" > "$ODIN_TMP"

# Go: average ns/op across COUNT runs per benchmark name
# With -count=N, Go prints N result lines per benchmark
# Format: "BenchmarkExecSimple-12  1000000  1006 ns/op  0 B/op  0 allocs/op"
echo "$GO_OUT" | awk '/ns\/op/ {
  name=$1; sub(/^Benchmark/,"",name); sub(/-[0-9]+$/,"",name)
  for(i=1;i<=NF;i++) if($(i+1)=="ns/op") { sum[name]+=$i; n[name]++; break }
}
END {
  for(name in sum) printf "%s %.0f\n", name, sum[name]/n[name]
}' > "$GO_TMP"

# Also extract Go allocs/op (averaged)
GO_ALLOC_TMP=$(mktemp)
trap "rm -f '$ODIN_ALL' '$ODIN_TMP' '$GO_TMP' '$GO_ALLOC_TMP' bench/odin_bench/bench" EXIT
echo "$GO_OUT" | awk '/allocs\/op/ {
  name=$1; sub(/^Benchmark/,"",name); sub(/-[0-9]+$/,"",name)
  for(i=1;i<=NF;i++) {
    if($(i+1)=="B/op") { bsum[name]+=$i; bn[name]++ }
    if($(i+1)=="allocs/op") { asum[name]+=$i; an[name]++ }
  }
}
END {
  for(name in bsum) printf "%s %d %d\n", name, bsum[name]/bn[name], asum[name]/an[name]
}' > "$GO_ALLOC_TMP"

echo ""
echo ""
echo "============================================================="
echo "  Comparison  (averaged over ${COUNT} runs, lower is better)"
echo "============================================================="

awk '
BEGIN {
  split("ParseSimple ParseLoop ParseComplex ExecSimple ExecLoop ExecNested ExecEscape ExecComplex FullSimple FullComplex", order)
  for(i in order) count++
  printf "%-20s %10s %10s %10s  %12s\n", "Benchmark", "Go ns/op", "Odin ns/op", "Speedup", "Go allocs/op"
  printf "%-20s %10s %10s %10s  %12s\n", "----", "--------", "----------", "-------", "------------"
}
FILENAME==ARGV[1] { go[$1]=$2; next }
FILENAME==ARGV[2] { odin[$1]=$2; next }
FILENAME==ARGV[3] { go_bop[$1]=$2; go_aop[$1]=$3; next }
END {
  for(i=1; i<=count; i++) {
    name = order[i]
    g = go[name]+0; o = odin[name]+0
    alloc = ""
    if(go_bop[name] != "") alloc = sprintf("%dB / %d", go_bop[name], go_aop[name])
    if(g>0 && o>0) {
      printf "%-20s %10d %10d %9.2fx  %12s\n", name, g, o, g/o, alloc
    } else {
      printf "%-20s %10s %10s %10s  %12s\n", name, (g?g:"-"), (o?o:"-"), "-", alloc
    }
  }
}
' "$GO_TMP" "$ODIN_TMP" "$GO_ALLOC_TMP"

echo ""
echo "Speedup = Go / Odin (>1x means Odin is faster)"
echo ""
echo "Build flags:"
echo "  Odin : -o:speed"
echo "  Go   : -ldflags=\"-s -w\" (stripped, all optimizations enabled)"
