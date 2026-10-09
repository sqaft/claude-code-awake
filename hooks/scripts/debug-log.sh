#!/bin/bash
# GEÇİCİ: /remote-control tespiti için deney logu. Deney bitince silinecek.
# Her hook olayında payload'ı ve process durumunu LOG_FILE'a yazar.
# Kullanım: debug-log.sh <EventName>

EVENT="${1:-unknown}"
LOG_DIR="/tmp/claude-code-awake-debug"
LOG_FILE="$LOG_DIR/log.txt"
mkdir -p "$LOG_DIR" 2>/dev/null

INPUT="$(cat 2>/dev/null)"

# Prompt metni gizlilik için loga yazılmaz.
if command -v jq >/dev/null 2>&1; then
	PAYLOAD="$(printf '%s' "$INPUT" | jq -c 'del(.prompt)' 2>/dev/null)"
else
	PAYLOAD="$(printf '%s' "$INPUT" | sed 's/"prompt"[[:space:]]*:[[:space:]]*"[^"]*"/"prompt":"<redacted>"/')"
fi

{
	echo "=================================================="
	echo "time:    $(date '+%Y-%m-%d %H:%M:%S')"
	echo "event:   $EVENT"
	echo "payload: $PAYLOAD"
	echo "hook pid=$$ ppid=$PPID"

	echo "--- process chain (pid ppid command) ---"
	pid=$PPID
	for _ in 1 2 3 4 5; do
		[ -z "$pid" ] || [ "$pid" = "0" ] || [ "$pid" = "1" ] && break
		ps -p "$pid" -o pid=,ppid=,args= 2>/dev/null
		pid="$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')"
	done

	echo "--- CLAUDE*/ANTHROPIC* env (değerler gizli) ---"
	env | grep -E '^(CLAUDE|ANTHROPIC)' | sed 's/=.*/=<set>/' | sort

	echo "--- claude process: ağ bağlantıları ---"
	if command -v lsof >/dev/null 2>&1; then
		lsof -nP -a -p "$PPID" -i 2>/dev/null | awk 'NR==1 || /ESTABLISHED|LISTEN/'
	fi

	echo "--- claude process: açık dosyalar (~/.claude altı) ---"
	if command -v lsof >/dev/null 2>&1; then
		lsof -nP -p "$PPID" 2>/dev/null | grep "/.claude" | awk '{print $NF}' | sort -u
	fi

	echo "--- ~/.claude altında son 2 dakikada değişen dosyalar ---"
	find "$HOME/.claude" -type f -mmin -2 2>/dev/null | grep -v '/projects/' | head -30

	echo "--- sistem pmset assertions (kısa) ---"
	pmset -g assertions 2>/dev/null | grep -E 'caffeinate|PreventUserIdleSystemSleep|PreventSystemSleep' | head -10
} >>"$LOG_FILE" 2>&1

exit 0
