#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)

RUN_ID=${BENCH_RUN_ID:-$(date +%Y%m%d-%H%M%S)}
RUN_DIR=${BENCH_OUT_DIR:-"$ROOT_DIR/benchmarks/results/$RUN_ID"}
LOG_DIR="$RUN_DIR/logs"
CSV_FILE="$RUN_DIR/results.csv"
META_FILE="$RUN_DIR/metadata.txt"

SSHD=${BENCH_SSHD:-/usr/sbin/sshd}
if [ ! -x "$SSHD" ] && [ -x /opt/homebrew/sbin/sshd ]; then
  SSHD=/opt/homebrew/sbin/sshd
fi
SSHD_SESSION_PATH=${BENCH_SSHD_SESSION_PATH:-}
SSHD_AUTH_PATH=${BENCH_SSHD_AUTH_PATH:-}
MEASURE_SERVER=${BENCH_MEASURE_SERVER:-0}

DATA_MIB=${BENCH_DATA_MIB:-64}
TRANSFER_ITERS=${BENCH_TRANSFER_ITERS:-3}
LATENCY_ITERS=${BENCH_LATENCY_ITERS:-5}
BASE_PORT=${BENCH_PORT:-22222}

CLIENT_SPECS=${BENCH_CLIENTS:-"hpnssh=${HOME}/bin/hpnssh brew-openssh=/opt/homebrew/bin/ssh system-openssh=/usr/bin/ssh"}
CIPHERS=${BENCH_CIPHERS:-"aes128-gcm@openssh.com"}
KEXS=${BENCH_KEXS:-"curve25519-sha256"}
LATENCY_CIPHER=${BENCH_LATENCY_CIPHER:-aes128-gcm@openssh.com}
if [ "${BENCH_MACS+x}" = x ]; then
  MACS=$BENCH_MACS
else
  MACS=
fi

mkdir -p "$RUN_DIR" "$LOG_DIR"
SERVER_LOG_DIR="$LOG_DIR/server"
mkdir -p "$SERVER_LOG_DIR"

csv_quote() {
  local value=${1-}
  value=${value//\"/\"\"}
  printf '"%s"' "$value"
}

csv_row() {
  local first=1
  local field
  for field in "$@"; do
    if [ "$first" -eq 0 ]; then
      printf ',' >> "$CSV_FILE"
    fi
    csv_quote "$field" >> "$CSV_FILE"
    first=0
  done
  printf '\n' >> "$CSV_FILE"
}

sanitize() {
  printf '%s' "$*" | tr -cs 'A-Za-z0-9._@=-' '_'
}

time_field() {
  local key=$1
  local file=$2
  awk -v key="$key" '
    $1 == key { print $2; found = 1; exit }
    END { if (!found) print "NA" }
  ' "$file"
}

rss_field() {
  local file=$1
  awk '
    /maximum resident set size/ { print $1; found = 1; exit }
    END { if (!found) print "NA" }
  ' "$file"
}

sum_float() {
  awk '
    BEGIN { found = 0; sum = 0 }
    { sum += $1; found = 1 }
    END { if (found) printf "%.6f", sum; else print "NA" }
  '
}

server_sum_field() {
  local safe=$1
  local key=$2
  local f value
  for f in "$SERVER_LOG_DIR"/"$safe".*.time; do
    [ -e "$f" ] || continue
    value=$(time_field "$key" "$f")
    if [ "$value" != NA ]; then
      printf '%s\n' "$value"
    fi
  done | sum_float
}

server_max_rss_field() {
  local safe=$1
  local f value
  for f in "$SERVER_LOG_DIR"/"$safe".*.time; do
    [ -e "$f" ] || continue
    value=$(rss_field "$f")
    if [ "$value" != NA ]; then
      printf '%s\n' "$value"
    fi
  done | awk '
    BEGIN { found = 0; max = 0 }
    $1 > max { max = $1; found = 1 }
    END { if (found) printf "%.0f", max; else print "NA" }
  '
}

server_helper_count() {
  local safe=$1
  local count=0
  local f
  for f in "$SERVER_LOG_DIR"/"$safe".*.time; do
    [ -e "$f" ] || continue
    count=$((count + 1))
  done
  printf '%s' "$count"
}

server_time_log_list() {
  local safe=$1
  local first=1
  local f
  for f in "$SERVER_LOG_DIR"/"$safe".*.time; do
    [ -e "$f" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ';'
    fi
    printf '%s' "$f"
    first=0
  done
}

server_cpu_sum() {
  local user_s=$1
  local sys_s=$2
  awk -v user_s="$user_s" -v sys_s="$sys_s" '
    BEGIN {
      if (user_s == "NA" || sys_s == "NA") print "NA";
      else printf "%.6f", user_s + sys_s;
    }
  '
}

throughput_mib_s() {
  local bytes=$1
  local real_s=$2
  awk -v bytes="$bytes" -v real_s="$real_s" '
    BEGIN {
      if (real_s + 0 > 0 && bytes + 0 > 0) {
        printf "%.2f", (bytes / 1048576.0) / real_s
      } else {
        printf "NA"
      }
    }
  '
}

create_helper_wrapper() {
  local role=$1
  local real_path=$2
  local wrapper_path=$3

  cat > "$wrapper_path" <<EOF
#!/bin/sh
role='$role'
real_path='$real_path'
label_file='$SERVER_LABEL_FILE'
server_log_dir='$SERVER_LOG_DIR'
label=\$(cat "\$label_file" 2>/dev/null || printf unknown)
safe=\$(printf '%s' "\$label" | tr -cs 'A-Za-z0-9._@=-' '_')
tmp_log="\$server_log_dir/\$safe.\$role.\$\$.tmp"
out_log="\$server_log_dir/\$safe.\$role.\$\$.time"
/usr/bin/time -lp -o "\$tmp_log" "\$real_path" "\$@"
rc=\$?
cat "\$tmp_log" > "\$out_log" 2>/dev/null
printf 'exit_status %s\\n' "\$rc" >> "\$out_log"
rm -f "\$tmp_log"
exit "\$rc"
EOF
  chmod +x "$wrapper_path"
}

cipher_list_without_none() {
  local out=
  local cipher
  for cipher in $CIPHERS; do
    if [ "$cipher" = none ]; then
      continue
    fi
    if [ -n "$out" ]; then
      out="$out,$cipher"
    else
      out=$cipher
    fi
  done
  printf '%s' "$out"
}

has_none_cipher_test() {
  local cipher
  for cipher in $CIPHERS; do
    if [ "$cipher" = none ]; then
      return 0
    fi
  done
  return 1
}

run_timed() {
  local test_type=$1
  local client_name=$2
  local client_path=$3
  local client_version=$4
  local cipher=$5
  local kex=$6
  local mac=$7
  local iteration=$8
  local bytes=$9
  shift 9

  local safe
  safe=$(sanitize "$test_type-$client_name-$cipher-$kex-$mac-$iteration")
  local time_log="$LOG_DIR/$safe.time"
  local stderr_log="$LOG_DIR/$safe.stderr"
  local server_label_file=${SERVER_LABEL_FILE:-}

  if [ "$MEASURE_SERVER" = 1 ]; then
    rm -f "$SERVER_LOG_DIR"/"$safe".*.time "$SERVER_LOG_DIR"/"$safe".*.tmp 2>/dev/null || true
    printf '%s' "$safe" > "$server_label_file"
  fi

  set +e
  /usr/bin/time -lp -o "$time_log" "$@" > /dev/null 2> "$stderr_log"
  local rc=$?
  set -e

  local real_s user_s sys_s rss throughput
  real_s=$(time_field real "$time_log")
  user_s=$(time_field user "$time_log")
  sys_s=$(time_field sys "$time_log")
  rss=$(rss_field "$time_log")
  throughput=$(throughput_mib_s "$bytes" "$real_s")

  local client_cpu_s server_user_s server_sys_s server_cpu_s server_rss server_helpers server_logs
  client_cpu_s=$(server_cpu_sum "$user_s" "$sys_s")
  if [ "$MEASURE_SERVER" = 1 ]; then
    server_user_s=$(server_sum_field "$safe" user)
    server_sys_s=$(server_sum_field "$safe" sys)
    server_cpu_s=$(server_cpu_sum "$server_user_s" "$server_sys_s")
    server_rss=$(server_max_rss_field "$safe")
    server_helpers=$(server_helper_count "$safe")
    server_logs=$(server_time_log_list "$safe")
  else
    server_user_s=NA
    server_sys_s=NA
    server_cpu_s=NA
    server_rss=NA
    server_helpers=0
    server_logs=
  fi

  csv_row \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$test_type" \
    "$client_name" \
    "$client_path" \
    "$client_version" \
    "$cipher" \
    "$kex" \
    "$mac" \
    "$iteration" \
    "$bytes" \
    "$real_s" \
    "$user_s" \
    "$sys_s" \
    "$client_cpu_s" \
    "$rss" \
    "$throughput" \
    "$server_user_s" \
    "$server_sys_s" \
    "$server_cpu_s" \
    "$server_rss" \
    "$server_helpers" \
    "$rc" \
    "$time_log" \
    "$stderr_log" \
    "$server_logs"
}

choose_port() {
  local port=$BASE_PORT
  while nc -z 127.0.0.1 "$port" >/dev/null 2>&1; do
    port=$((port + 1))
  done
  printf '%s' "$port"
}

TMP_DIR=$(mktemp -d /tmp/hpnssh-bench.XXXXXX)
SSHD_PID=
SERVER_LABEL_FILE="$TMP_DIR/current-server-label"

cleanup() {
  if [ -n "${SSHD_PID:-}" ]; then
    kill "$SSHD_PID" >/dev/null 2>&1 || true
    wait "$SSHD_PID" >/dev/null 2>&1 || true
  fi
  if [ "${BENCH_KEEP_TMP:-0}" != "1" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

if [ ! -x "$SSHD" ]; then
  printf 'No executable sshd found. Set BENCH_SSHD=/path/to/sshd.\n' >&2
  exit 1
fi

if [ -z "$SSHD_SESSION_PATH" ]; then
  case "$(basename -- "$SSHD")" in
    hpnsshd)
      sibling_session="$(dirname -- "$SSHD")/hpnsshd-session"
      if [ -x "$sibling_session" ]; then
        SSHD_SESSION_PATH=$sibling_session
      fi
      ;;
    sshd)
      sibling_session="$(dirname -- "$SSHD")/sshd-session"
      if [ -x "$sibling_session" ]; then
        SSHD_SESSION_PATH=$sibling_session
      elif [ -x /opt/homebrew/opt/openssh/libexec/sshd-session ] &&
          [ "${SSHD#/opt/homebrew/}" != "$SSHD" ]; then
        SSHD_SESSION_PATH=/opt/homebrew/opt/openssh/libexec/sshd-session
      elif [ -x /usr/libexec/sshd-session ]; then
        SSHD_SESSION_PATH=/usr/libexec/sshd-session
      fi
      ;;
  esac
fi

if [ -z "$SSHD_AUTH_PATH" ]; then
  case "$(basename -- "$SSHD")" in
    hpnsshd)
      sibling_auth="$(dirname -- "$SSHD")/hpnsshd-auth"
      if [ -x "$sibling_auth" ]; then
        SSHD_AUTH_PATH=$sibling_auth
      fi
      ;;
    sshd)
      sibling_auth="$(dirname -- "$SSHD")/sshd-auth"
      if [ -x "$sibling_auth" ]; then
        SSHD_AUTH_PATH=$sibling_auth
      elif [ -x /opt/homebrew/opt/openssh/libexec/sshd-auth ] &&
          [ "${SSHD#/opt/homebrew/}" != "$SSHD" ]; then
        SSHD_AUTH_PATH=/opt/homebrew/opt/openssh/libexec/sshd-auth
      elif [ -x /usr/libexec/sshd-auth ]; then
        SSHD_AUTH_PATH=/usr/libexec/sshd-auth
      fi
      ;;
  esac
fi

REAL_SSHD_SESSION_PATH=$SSHD_SESSION_PATH
REAL_SSHD_AUTH_PATH=$SSHD_AUTH_PATH

if [ "$MEASURE_SERVER" = 1 ]; then
  if [ ! -x "$REAL_SSHD_SESSION_PATH" ] || [ ! -x "$REAL_SSHD_AUTH_PATH" ]; then
    printf 'BENCH_MEASURE_SERVER=1 requires executable SshdSessionPath and SshdAuthPath helpers.\n' >&2
    printf 'SshdSessionPath=%s\nSshdAuthPath=%s\n' "$REAL_SSHD_SESSION_PATH" "$REAL_SSHD_AUTH_PATH" >&2
    exit 1
  fi
  create_helper_wrapper session "$REAL_SSHD_SESSION_PATH" "$TMP_DIR/sshd-session-wrapper"
  create_helper_wrapper auth "$REAL_SSHD_AUTH_PATH" "$TMP_DIR/sshd-auth-wrapper"
  SSHD_SESSION_PATH="$TMP_DIR/sshd-session-wrapper"
  SSHD_AUTH_PATH="$TMP_DIR/sshd-auth-wrapper"
fi

PORT=$(choose_port)
TARGET="$(id -un)@127.0.0.1"
HOST_KEY="$TMP_DIR/host_ed25519"
CLIENT_KEY="$TMP_DIR/client_ed25519"
AUTHORIZED_KEYS="$TMP_DIR/authorized_keys"
DATA_FILE="$TMP_DIR/payload.bin"
SSHD_CONFIG="$TMP_DIR/sshd_config"
SSHD_LOG="$RUN_DIR/sshd.log"

ssh-keygen -q -t ed25519 -N '' -f "$HOST_KEY"
ssh-keygen -q -t ed25519 -N '' -f "$CLIENT_KEY"
cat "$CLIENT_KEY.pub" > "$AUTHORIZED_KEYS"
chmod 700 "$TMP_DIR"
chmod 600 "$HOST_KEY" "$CLIENT_KEY" "$AUTHORIZED_KEYS"

cat > "$SSHD_CONFIG" <<EOF
Port $PORT
ListenAddress 127.0.0.1
HostKey $HOST_KEY
AuthorizedKeysFile $AUTHORIZED_KEYS
PidFile $TMP_DIR/sshd.pid
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
StrictModes no
AllowUsers $(id -un)
UseDNS no
MaxStartups 100:100:100
LogLevel ERROR
Subsystem sftp internal-sftp
EOF

if [ -n "$SSHD_SESSION_PATH" ]; then
  printf 'SshdSessionPath %s\n' "$SSHD_SESSION_PATH" >> "$SSHD_CONFIG"
fi
if [ -n "$SSHD_AUTH_PATH" ]; then
  printf 'SshdAuthPath %s\n' "$SSHD_AUTH_PATH" >> "$SSHD_CONFIG"
fi

if [ -n "$KEXS" ]; then
  printf 'KexAlgorithms %s\n' "$(printf '%s' "$KEXS" | tr ' ' ',')" >> "$SSHD_CONFIG"
fi

SERVER_CIPHERS=$(cipher_list_without_none)
if [ -n "$SERVER_CIPHERS" ]; then
  printf 'Ciphers %s\n' "$SERVER_CIPHERS" >> "$SSHD_CONFIG"
fi

if has_none_cipher_test; then
  printf 'NoneEnabled yes\n' >> "$SSHD_CONFIG"
fi

"$SSHD" -t -f "$SSHD_CONFIG"
"$SSHD" -D -e -f "$SSHD_CONFIG" > "$SSHD_LOG" 2>&1 &
SSHD_PID=$!

i=0
server_ready=0
while [ "$i" -lt 100 ]; do
  if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then
    server_ready=1
    break
  fi
  if ! kill -0 "$SSHD_PID" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
  i=$((i + 1))
done

if [ "$server_ready" -ne 1 ]; then
  printf 'Temporary sshd did not become ready. Log:\n' >&2
  cat "$SSHD_LOG" >&2 || true
  exit 1
fi

dd if=/dev/zero of="$DATA_FILE" bs=1048576 count="$DATA_MIB" >/dev/null 2>&1
BYTES=$((DATA_MIB * 1048576))

{
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'run_dir=%s\n' "$RUN_DIR"
  printf 'sshd=%s\n' "$SSHD"
  "$SSHD" -V 2>&1 || true
  printf 'sshd_session_path=%s\n' "$SSHD_SESSION_PATH"
  printf 'sshd_auth_path=%s\n' "$SSHD_AUTH_PATH"
  printf 'real_sshd_session_path=%s\n' "$REAL_SSHD_SESSION_PATH"
  printf 'real_sshd_auth_path=%s\n' "$REAL_SSHD_AUTH_PATH"
  printf 'measure_server=%s\n' "$MEASURE_SERVER"
  printf 'port=%s\n' "$PORT"
  printf 'data_mib=%s\n' "$DATA_MIB"
  printf 'transfer_iters=%s\n' "$TRANSFER_ITERS"
  printf 'latency_iters=%s\n' "$LATENCY_ITERS"
  printf 'date_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sw_vers 2>/dev/null || true
  uname -a
  sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/^/cpu=/' || true
  sysctl -n hw.ncpu 2>/dev/null | sed 's/^/hw_ncpu=/' || true
  sysctl -n hw.memsize 2>/dev/null | sed 's/^/hw_memsize=/' || true
  printf '\nclients:\n'
  for spec in $CLIENT_SPECS; do
    name=${spec%%=*}
    path=${spec#*=}
    if [ -x "$path" ]; then
      printf '%s=%s | ' "$name" "$path"
      "$path" -V 2>&1 || true
    else
      printf '%s=%s | missing\n' "$name" "$path"
    fi
  done
} > "$META_FILE"

cat > "$CSV_FILE" <<'EOF'
"timestamp_utc","test_type","client_name","client_path","client_version","cipher","kex","mac","iteration","bytes","real_s","client_user_s","client_sys_s","client_cpu_s","client_max_rss_bytes","throughput_mib_s","server_user_s","server_sys_s","server_cpu_s","server_max_rss_bytes","server_helper_count","exit_code","time_log","stderr_log","server_time_logs"
EOF

BASE_OPTS=(
  -F /dev/null
  -p "$PORT"
  -i "$CLIENT_KEY"
  -o BatchMode=yes
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o GlobalKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o Compression=no
  -o GSSAPIAuthentication=no
  -o PreferredAuthentications=publickey
  -o PasswordAuthentication=no
  -o KbdInteractiveAuthentication=no
)

printf 'Benchmark run: %s\n' "$RUN_DIR"
printf 'Temporary sshd: %s on 127.0.0.1:%s\n' "$SSHD" "$PORT"
printf 'Payload: %s MiB, transfer iterations: %s, latency iterations: %s\n' "$DATA_MIB" "$TRANSFER_ITERS" "$LATENCY_ITERS"

for spec in $CLIENT_SPECS; do
  client_name=${spec%%=*}
  client_path=${spec#*=}
  if [ ! -x "$client_path" ]; then
    printf 'Skipping missing client: %s (%s)\n' "$client_name" "$client_path" >&2
    continue
  fi
  client_version=$("$client_path" -V 2>&1 | tr '\n' ' ')

  printf '\n[%s] latency by KEX\n' "$client_name"
  for kex in $KEXS; do
    iter=1
    while [ "$iter" -le "$LATENCY_ITERS" ]; do
      run_timed \
        latency_kex \
        "$client_name" \
        "$client_path" \
        "$client_version" \
        "$LATENCY_CIPHER" \
        "$kex" \
        implicit \
        "$iter" \
        0 \
        "$client_path" \
        "${BASE_OPTS[@]}" \
        -c "$LATENCY_CIPHER" \
        -o "KexAlgorithms=$kex" \
        "$TARGET" \
        true
      iter=$((iter + 1))
    done
  done

  printf '[%s] transfer by cipher\n' "$client_name"
  for cipher in $CIPHERS; do
    mac=implicit
    if [ "$cipher" = aes128-ctr ] || [ "$cipher" = aes256-ctr ]; then
      mac=hmac-sha2-256-etm@openssh.com
    fi
    mac_args=()
    if [ "$mac" != implicit ]; then
      mac_args=(-m "$mac")
    fi
    cipher_args=(-c "$cipher")
    if [ "$cipher" = none ]; then
      cipher_args=(-c aes128-gcm@openssh.com -o NoneSwitch=yes -o NoneEnabled=yes)
    fi
    iter=1
    while [ "$iter" -le "$TRANSFER_ITERS" ]; do
      run_timed \
        upload_cipher \
        "$client_name" \
        "$client_path" \
        "$client_version" \
        "$cipher" \
        curve25519-sha256 \
        "$mac" \
        "$iter" \
        "$BYTES" \
        bash -c 'data=$1; client=$2; target=$3; shift 3; cat "$data" | "$client" "$@" "$target" "cat > /dev/null"' \
        sh \
        "$DATA_FILE" \
        "$client_path" \
        "$TARGET" \
        "${BASE_OPTS[@]}" \
        "${cipher_args[@]}" \
        -o KexAlgorithms=curve25519-sha256 \
        ${mac_args[@]+"${mac_args[@]}"}

      run_timed \
        download_cipher \
        "$client_name" \
        "$client_path" \
        "$client_version" \
        "$cipher" \
        curve25519-sha256 \
        "$mac" \
        "$iter" \
        "$BYTES" \
        bash -c 'data=$1; client=$2; target=$3; shift 3; "$client" "$@" "$target" "cat $data" > /dev/null' \
        sh \
        "$DATA_FILE" \
        "$client_path" \
        "$TARGET" \
        "${BASE_OPTS[@]}" \
        "${cipher_args[@]}" \
        -o KexAlgorithms=curve25519-sha256 \
        ${mac_args[@]+"${mac_args[@]}"}

      iter=$((iter + 1))
    done
  done

  printf '[%s] upload by MAC with aes128-ctr\n' "$client_name"
  for mac in $MACS; do
    iter=1
    while [ "$iter" -le "$TRANSFER_ITERS" ]; do
      run_timed \
        upload_mac \
        "$client_name" \
        "$client_path" \
        "$client_version" \
        aes128-ctr \
        curve25519-sha256 \
        "$mac" \
        "$iter" \
        "$BYTES" \
        bash -c 'data=$1; client=$2; target=$3; shift 3; cat "$data" | "$client" "$@" "$target" "cat > /dev/null"' \
        sh \
        "$DATA_FILE" \
        "$client_path" \
        "$TARGET" \
        "${BASE_OPTS[@]}" \
        -c aes128-ctr \
        -o KexAlgorithms=curve25519-sha256 \
        -m "$mac"
      iter=$((iter + 1))
    done
  done
done

printf '\nRaw results: %s\n' "$CSV_FILE"
printf 'Metadata:    %s\n' "$META_FILE"
printf 'Logs:        %s\n' "$LOG_DIR"
