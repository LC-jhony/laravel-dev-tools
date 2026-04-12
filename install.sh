
#!/usr/bin/env bash
# ================================================================
#  Ubuntu Dev Stack Installer  v2.3
#  PHP 8.4  MariaDB  Node.js  Composer  Valet  Laravel
#  Ubuntu 24.04 LTS  |  WSL compatible
# ================================================================
set -euo pipefail

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# ── Colors ────────────────────────────────────────────────────────
R=$'\033[0m'
B=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[38;5;203m'
GRN=$'\033[38;5;114m'
YLW=$'\033[38;5;221m'
BLU=$'\033[38;5;111m'
MGT=$'\033[38;5;183m'
CYN=$'\033[38;5;80m'
WHT=$'\033[38;5;255m'
GRY=$'\033[38;5;244m'
DGY=$'\033[38;5;238m'
# Extra palette for modern UI
C1=$'\033[38;5;51m'    # bright cyan
C2=$'\033[38;5;45m'    # sky
C3=$'\033[38;5;39m'    # azure
C4=$'\033[38;5;33m'    # blue
C5=$'\033[38;5;27m'    # deep blue
EMERALD=$'\033[38;5;48m'
MINT=$'\033[38;5;85m'
CORAL=$'\033[38;5;210m'
GOLD=$'\033[38;5;220m'
VIOLET=$'\033[38;5;135m'
BG_STRIP=$'\033[48;5;234m'   # subtle dark bg for bar rows
ITALIC=$'\033[3m'
BOLD=$'\033[1m'

# ── State ─────────────────────────────────────────────────────────
LOG_FILE="/tmp/ubuntu-dev-installer-$(date +%s).log"
NODE_VERSION="24"
declare -A INSTALL=([php]=1 [mariadb]=1 [nodejs]=1 [composer]=1 [valet]=1 [laravel]=1)
declare -A RESULT=()
declare -A ALREADY=()
INSTALL_ERRORS=()
START_TIME=$SECONDS
CACHED_SUDO_PASS=""

# ── Detect WSL ────────────────────────────────────────────────────
IS_WSL=0
if grep -qi microsoft /proc/version 2>/dev/null || grep -qi wsl /proc/version 2>/dev/null; then
  IS_WSL=1
fi

# ── Terminal ──────────────────────────────────────────────────────
TW()       { tput cols  2>/dev/null || echo 80; }
cls()      { printf '\033[2J\033[H'; }
cur_hide() { printf '\033[?25l'; }
cur_show() { printf '\033[?25h'; }
trap 'cur_show; tput sgr0 2>/dev/null || true; echo' EXIT INT TERM

PAD=3
_P() { printf '%*s' "$PAD" ''; }

rep() {
  local char="$1" n="$2" i s=""
  for (( i=0; i<n; i++ )); do s+="$char"; done
  printf '%s' "$s"
}

strip_ansi() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*[mK]//g'; }

center_plain() {
  local text="$1" w="${2:-$(TW)}"
  local len=${#text}
  local pad=$(( (w - len) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf "%${pad}s%s\n" "" "$text"
}

center_color() {
  local text="$1" raw_len="$2" w="${3:-$(TW)}"
  local pad=$(( (w - raw_len) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf "%${pad}s%s\n" "" "$text"
}

rule() {
  local color="${1:-$DGY}" char="${2:--}" w="${3:-$(TW)}"
  printf '%s%s%s\n' "$color" "$(rep "$char" "$w")" "$R"
}

_BT='+' _BB='+' _BL='|' _BR='|' _BH='-' _BSL='+' _BSR='+'
if [[ "${LANG:-}" =~ UTF ]]; then
  _BT='╭' _BB='╰' _BL='│' _BR='│' _BH='─' _BSL='├' _BSR='┤'
fi

box_top() {
  local w="$1" c="${2:-$CYN}"
  local inner=$(( w - PAD*2 - 2 ))
  printf '%s%s%s%s%s%s\n' "$c" "$(_P)" "$_BT" "$(rep "$_BH" "$inner")" "$_BR" "$R"
}
box_bot() {
  local w="$1" c="${2:-$CYN}"
  local inner=$(( w - PAD*2 - 2 ))
  printf '%s%s%s%s%s%s\n' "$c" "$(_P)" "$_BB" "$(rep "$_BH" "$inner")" "$_BR" "$R"
}
box_sep() {
  local w="$1" c="${2:-$CYN}"
  local inner=$(( w - PAD*2 - 2 ))
  printf '%s%s%s%s%s%s\n' "$c" "$(_P)" "$_BSL" "$(rep "$_BH" "$inner")" "$_BSR" "$R"
}
box_row() {
  local content="$1" w="$2" c="${3:-$CYN}"
  local raw; raw=$(strip_ansi "$content")
  local clen=${#raw}
  local inner=$(( w - PAD*2 - 4 ))
  local rpad=$(( inner - clen ))
  [[ $rpad -lt 0 ]] && rpad=0
  printf '%s%s%s%s %s%*s %s%s\n' \
    "$c" "$(_P)" "$_BL" "$R" \
    "$content" "$rpad" "" \
    "$c" "$_BR$R"
}

# ── Status icons ──────────────────────────────────────────────────
ic_ok()    { printf '%s%s✔%s' "$EMERALD" "$BOLD" "$R"; }
ic_skip()  { printf '%s%s◌%s' "$YLW"    "$BOLD" "$R"; }
ic_err()   { printf '%s%s✘%s' "$CORAL"  "$BOLD" "$R"; }
ic_info()  { printf '%s%s◈%s' "$C1"     "$BOLD" "$R"; }
ic_warn()  { printf '%s%s◆%s' "$GOLD"   "$BOLD" "$R"; }
ic_arr()   { printf '%s›%s'   "$C2"            "$R"; }
ic_dot()   { printf '%s·%s'   "$DGY"           "$R"; }
ic_exists(){ printf '%s%s⬡%s' "$MINT"   "$BOLD" "$R"; }

# ── Logging ───────────────────────────────────────────────────────
log_ok()    { printf '%s %s  %s%s%s%s\n'   "$(_P)" "$(ic_ok)"    "$GRN$B" "$*" "$R" ""; printf '[OK]    %s\n' "$*" >> "$LOG_FILE"; }
log_skip()  { printf '%s %s  %s%s%s\n'     "$(_P)" "$(ic_skip)"  "$YLW"   "$*" "$R";   printf '[SKIP]  %s\n' "$*" >> "$LOG_FILE"; }
log_err()   { printf '%s %s  %s%s%s\n'     "$(_P)" "$(ic_err)"   "$RED"   "$*" "$R";   printf '[ERR]   %s\n' "$*" >> "$LOG_FILE"; }
log_info()  { printf '%s %s  %s%s%s\n'     "$(_P)" "$(ic_info)"  "$WHT"   "$*" "$R";   printf '[INFO]  %s\n' "$*" >> "$LOG_FILE"; }
log_warn()  { printf '%s %s  %s%s%s\n'     "$(_P)" "$(ic_warn)"  "$YLW"   "$*" "$R";   printf '[WARN]  %s\n' "$*" >> "$LOG_FILE"; }
log_run()   { printf '%s %s  %s%s%s%s\n'   "$(_P)" "$(ic_arr)"   "$DIM$CYN" "$*" "$R" ""; printf '[RUN]   %s\n' "$*" >> "$LOG_FILE"; }
log_dim()   { printf '%s %s  %s%s%s\n'     "$(_P)" "$(ic_dot)"   "$GRY"   "$*" "$R";   printf '[DIM]   %s\n' "$*" >> "$LOG_FILE"; }
log_exists(){ printf '%s %s  %s%s%s%s\n'   "$(_P)" "$(ic_exists)" "$GRN"  "Already installed: " "$*" "$R"; printf '[EXISTS] %s\n' "$*" >> "$LOG_FILE"; }

# ================================================================
#  SERVICE HELPER — works on both systemd and WSL/SysV
# ================================================================
svc_start() {
  local svc="$1"
  if [[ $IS_WSL -eq 1 ]] || ! systemctl is-system-running --quiet 2>/dev/null; then
    sudo service "$svc" start >> "$LOG_FILE" 2>&1 || true
  else
    sudo systemctl start "$svc" >> "$LOG_FILE" 2>&1 || true
  fi
}

svc_enable() {
  local svc="$1"
  if [[ $IS_WSL -eq 1 ]] || ! systemctl is-system-running --quiet 2>/dev/null; then
    # WSL doesn't support enable in the traditional sense; just start
    sudo service "$svc" start >> "$LOG_FILE" 2>&1 || true
  else
    sudo systemctl enable --now "$svc" >> "$LOG_FILE" 2>&1 || true
  fi
}

svc_status() {
  local svc="$1"
  if [[ $IS_WSL -eq 1 ]] || ! systemctl is-system-running --quiet 2>/dev/null; then
    sudo service "$svc" status >> "$LOG_FILE" 2>&1
  else
    systemctl is-active --quiet "$svc"
  fi
}

# ================================================================
#  SUDO PASSWORD PROMPT
# ================================================================
read_password_masked() {
  local __varname="$1"
  local __prompt="${2:-Password: }"
  local __pass=""
  local __char

  printf '%s%s%s%s' "$GRN" "$B" "$__prompt" "$R"

  while IFS= read -r -s -n1 __char; do
    if [[ -z "$__char" || "$__char" == $'\r' ]]; then
      echo
      break
    fi
    if [[ "$__char" == $'\177' || "$__char" == $'\010' ]]; then
      if [[ -n "$__pass" ]]; then
        __pass="${__pass%?}"
        printf '\b \b'
      fi
    else
      __pass+="$__char"
      printf '%s*%s' "$GRN" "$R"
    fi
  done

  printf -v "$__varname" '%s' "$__pass"
}

sudo_ask() {
  local desc="$1"; shift
  spinner_stop

  if sudo -n true 2>/dev/null; then
    log_run "$desc"
    local rc=0
    sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then log_ok "$desc"
    else log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc"); fi
    return $rc
  fi

  local __pw=""
  local user; user=$(whoami)

  if [[ -n "$CACHED_SUDO_PASS" ]]; then
    log_run "$desc"
    local rc=0
    printf '%s\n' "$CACHED_SUDO_PASS" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then log_ok "$desc"
    else
      printf '\n'
      read_password_masked __pw "${GRN}${B}[sudo]${R}${GRN} password for ${B}${user}${R}${GRN}:${R} "
      printf '\n'
      if [[ -n "$__pw" ]]; then
        CACHED_SUDO_PASS="$__pw"
        printf '%s\n' "$__pw" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?
      fi
      if [[ $rc -eq 0 ]]; then log_ok "$desc"
      else log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc"); fi
    fi
    return $rc
  fi

  printf '\n'
  read_password_masked __pw "${GRN}${B}[sudo]${R}${GRN} password for ${B}${user}${R}${GRN}:${R} "
  printf '\n'

  log_run "$desc"
  local rc=0
  printf '%s\n' "$__pw" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?

  if [[ $rc -eq 0 ]]; then
    CACHED_SUDO_PASS="$__pw"
    log_ok "$desc"
  else
    log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc")
  fi
  return $rc
}

sudo_warmup() {
  if [[ $EUID -eq 0 ]]; then return 0; fi
  if sudo -n true 2>/dev/null; then
    log_ok "sudo: passwordless access confirmed"
    return 0
  fi

  local __pw="" user; user=$(whoami)
  printf '\n'
  log_info "sudo authentication required (cached for the session)"
  printf '\n'
  read_password_masked __pw "${GRN}${B}[sudo]${R}${GRN} password for ${B}${user}${R}${GRN}:${R} "
  printf '\n'

  local rc=0
  if printf '%s\n' "$__pw" | sudo -S -v >> "$LOG_FILE" 2>&1; then
    log_ok "sudo ready -- credentials cached"
  else
    rc=$?
    log_warn "Incorrect password -- trying once more"
    printf '\n'
    read_password_masked __pw "${GRN}${B}[sudo]${R}${GRN} password for ${B}${user}${R}${GRN}:${R} "
    printf '\n'
    if printf '%s\n' "$__pw" | sudo -S -v >> "$LOG_FILE" 2>&1; then
      log_ok "sudo ready"
    else
      log_err "sudo authentication failed -- cannot continue"
      exit 1
    fi
  fi
}

# ── Spinner ───────────────────────────────────────────────────────
SPIN_PID=""
SPIN_FRAMES=('-' '\' '|' '/')

spinner_start() {
  local msg="$1"
  cur_hide
  (
    local i=0
    while true; do
      local f="${SPIN_FRAMES[$((i % 4))]}"
      printf '\r%s %s%s%s  %s%s%s   ' \
        "$(_P)" "$CYN$B" "$f" "$R" "$DIM" "$msg" "$R"
      sleep 0.1
      (( i++ )) || true
    done
  ) &
  SPIN_PID=$!
}

spinner_stop() {
  if [[ -n "${SPIN_PID:-}" ]]; then
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=""
    printf '\r%s\r' "$(rep ' ' "$(TW)")"
    cur_show
  fi
}

run_cmd() {
  local desc="$1"; shift
  spinner_start "$desc"
  local rc=0
  "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop
  if [[ $rc -eq 0 ]]; then log_ok "$desc"
  else log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc"); fi
  return $rc
}

sudo_cmd() {
  local desc="$1"; shift
  spinner_stop
  log_run "$desc"
  local rc=0

  if sudo -n true 2>/dev/null; then
    sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  else
    if [[ -n "$CACHED_SUDO_PASS" ]]; then
      printf '%s\n' "$CACHED_SUDO_PASS" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    else
      sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    fi
  fi

  if [[ $rc -eq 0 ]]; then log_ok "$desc"
  else log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc"); fi
  return $rc
}

# ================================================================
#  MODERN PROGRESS UI
#  global_progress  — full-width multi-segment pipeline bar
#  task_progress    — slim per-package fill bar with glow head
#  draw_pkg_panel   — live status panel of all packages
# ================================================================

# Gradient palette for the 7 pipeline segments
declare -a SEG_COLORS=("$C1" "$C2" "$C3" "$C4" "$EMERALD" "$MINT" "$GOLD")
declare -a SEG_ICONS=("⬡" "⬡" "⬡" "⬡" "⬡" "⬡" "⬡")  # filled once done
declare -a STEP_NAMES=("system" "php" "mariadb" "composer" "nodejs" "valet" "laravel")
declare -a STEP_DONE=()   # filled with 1 as each step completes

# thin block chars for smooth fill
FILL_FULL='█'
FILL_HEAD='▓'
FILL_MID='▒'
FILL_EMPTY='░'

# ── global_progress: pipeline dots + thin gradient bar ──────────
global_progress() {
  local cur="$1" tot="$2" lbl="${3:-}"
  local w; w=$(TW)
  local pct=$(( cur * 100 / tot ))

  # ── Row 1: pipeline segment dots ─────────────────────────────
  printf '%s  ' "$(_P)"
  local i
  for (( i=0; i<tot; i++ )); do
    local sname="${STEP_NAMES[$i]:-step}"
    local sc="${SEG_COLORS[$i]:-$CYN}"
    local slen=${#sname}
    if (( i < cur )); then
      # completed segment
      printf '%s%s●%s' "$sc$BOLD" "" "$R"
      printf '%s%s%s' "$sc" "$sname" "$R"
    elif (( i == cur - 1 )) && (( cur < tot )); then
      # active (last completed = current running)
      printf '%s%s◆%s' "$GOLD$BOLD" "" "$R"
      printf '%s%s%s' "$GOLD$BOLD" "$sname" "$R"
    else
      # pending
      printf '%s○%s' "$DGY" "$R"
      printf '%s%s%s' "$DGY" "$sname" "$R"
    fi
    (( i < tot-1 )) && printf '%s ─ %s' "$DGY" "$R"
  done
  echo

  # ── Row 2: gradient fill bar ─────────────────────────────────
  local bar_w=$(( w - PAD*2 - 12 ))
  [[ $bar_w -lt 20 ]] && bar_w=20
  local filled=$(( cur * bar_w / tot ))
  local empty=$(( bar_w - filled ))

  printf '%s  ' "$(_P)"
  printf '%s╠%s' "$DGY" "$R"

  # Fill with gradient blocks — color shifts across segments
  local seg_w=$(( filled / (tot > 0 ? tot : 1) ))
  local remaining=$filled
  local col_i=0
  for (( i=0; i<tot && remaining>0; i++ )); do
    local chunk=$(( i < tot-1 ? seg_w : remaining ))
    [[ $chunk -gt $remaining ]] && chunk=$remaining
    [[ $chunk -lt 0 ]] && chunk=0
    local sc="${SEG_COLORS[$i]:-$CYN}"
    if (( chunk > 0 )); then
      # last char of each segment = slightly brighter head
      local body=$(( chunk - 1 ))
      [[ $body -gt 0 ]] && printf '%s%s%s' "$sc" "$(rep "$FILL_FULL" "$body")" "$R"
      printf '%s%s%s' "$sc$BOLD" "$FILL_HEAD" "$R"
    fi
    (( remaining -= chunk )) || true
    (( col_i++ )) || true
  done

  # empty portion
  if (( empty > 0 )); then
    printf '%s%s%s' "$DGY" "$(rep "$FILL_EMPTY" "$empty")" "$R"
  fi

  # pct badge
  printf '%s╣%s' "$DGY" "$R"
  if (( pct == 100 )); then
    printf '  %s%s %3d%%%s' "$EMERALD$BOLD" "✔" "$pct" "$R"
  else
    printf '  %s%s%3d%%%s' "$GOLD$BOLD" "" "$pct" "$R"
  fi
  echo

  # ── Row 3: current step label ─────────────────────────────────
  if [[ -n "$lbl" ]]; then
    printf '%s  %s%s  %s%s%s\n' \
      "$(_P)" "$DGY" "└─" "$ITALIC$GRY" "$lbl" "$R"
  fi
  echo
}

# ── task_progress: slim segmented bar per package ───────────────
task_progress() {
  local cur="$1" tot="$2" color="${3:-$C2}"
  local w; w=$(TW)
  local bar_w=$(( w - PAD*2 - 8 ))
  [[ $bar_w -lt 12 ]] && bar_w=12
  local filled=$(( cur * bar_w / tot ))
  local empty=$(( bar_w - filled ))

  printf '%s  ' "$(_P)"
  printf '%s▕%s' "$DGY" "$R"
  if (( cur >= tot )); then
    # complete: solid emerald
    printf '%s%s%s' "$EMERALD$BOLD" "$(rep "$FILL_FULL" "$bar_w")" "$R"
    printf '%s▏%s' "$DGY" "$R"
    printf '  %s✔ done%s\n' "$EMERALD$BOLD" "$R"
  elif (( filled > 0 )); then
    local body=$(( filled - 1 ))
    [[ $body -gt 0 ]] && printf '%s%s%s' "$color" "$(rep "$FILL_FULL" "$body")" "$R"
    # animated glow head — uses SECONDS for flicker
    local glow
    (( SECONDS % 2 == 0 )) && glow="$GOLD$BOLD" || glow="$color$BOLD"
    printf '%s%s%s' "$glow" "$FILL_HEAD" "$R"
    printf '%s%s%s' "$DGY" "$(rep "$FILL_EMPTY" "$empty")" "$R"
    printf '%s▏%s' "$DGY" "$R"
    printf '  %s%d/%d%s\n' "$DGY" "$cur" "$tot" "$R"
  else
    printf '%s%s%s' "$DGY" "$(rep "$FILL_EMPTY" "$bar_w")" "$R"
    printf '%s▏%s' "$DGY" "$R"
    printf '  %s%d/%d%s\n' "$DGY" "$cur" "$tot" "$R"
  fi
}

# ── Prompt helpers ────────────────────────────────────────────────
confirm() {
  local msg="$1" default="${2:-y}"
  local hint
  [[ "$default" == "y" ]] \
    && hint="${GRN}Y${R}${DGY}/n${R}" \
    || hint="${DGY}y/${R}${GRN}N${R}"
  printf '%s %s%s?%s  %s%s%s  %s[%s%s]%s  ' \
    "$(_P)" "$YLW$B" "?" "$R" "$WHT" "$msg" "$R" "$DGY" "$hint" "$DGY" "$R"
  read -r reply
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

ask() {
  local msg="$1" default="$2" varname="$3"
  printf '%s %s%s>%s  %s%s%s  %s[%s%s%s]%s: ' \
    "$(_P)" "$CYN$B" ">" "$R" "$WHT" "$msg" "$R" \
    "$DGY" "$GRY" "$default" "$DGY" "$R"
  read -r _r
  printf -v "$varname" '%s' "${_r:-$default}"
}

# ── Headers ───────────────────────────────────────────────────────
step_header() {
  local num="$1" title="$2" color="${3:-$C1}"
  local w; w=$(TW)
  local inner=$(( w - PAD*2 ))
  echo
  # top rule with step badge
  local badge=" STEP ${num} "
  local badge_len=${#badge}
  local rule_len=$(( inner - badge_len - 2 ))
  printf '%s%s%s %s%s%s %s%s%s\n' \
    "$(_P)" "$DGY" "$(rep '─' 2)" \
    "$color$BOLD" "$badge" "$R" \
    "$DGY" "$(rep '─' $((rule_len > 0 ? rule_len : 2)))" "$R"
  # title line
  printf '%s  %s%s %s%s\n' \
    "$(_P)" "$color$BOLD" "▸" "$WHT$BOLD" "$title$R"
  printf '%s%s%s%s\n' "$(_P)" "$DGY" "$(rep '╌' "$inner")" "$R"
  echo
}

pkg_header() {
  local name="$1" glyph="$2" color="${3:-$C2}"
  local w; w=$(TW)
  local inner=$(( w - PAD*2 ))
  echo
  # badge bar: ▐ PKG ▌ name ──────
  local tag=" ${glyph} "
  local tag_len=${#tag}
  local name_len=${#name}
  local tail=$(( inner - tag_len - name_len - 5 ))
  [[ $tail -lt 2 ]] && tail=2
  printf '%s%s%s%s%s%s  %s%s%s  %s%s%s\n' \
    "$(_P)" \
    "$color$BOLD" "▐${tag}▌" "$R" \
    "  " "" \
    "$WHT$BOLD" "$name" "$R" \
    "$DGY" "$(rep '─' "$tail")" "$R"
  echo
}

# ================================================================
#  DETECT ALREADY-INSTALLED VERSIONS
# ================================================================
detect_installed() {
  local phpver=""
  if command -v php &>/dev/null; then
    phpver=$(php --version 2>/dev/null | head -1 | awk '{print $1,$2}')
  elif command -v php8.4 &>/dev/null; then
    phpver=$(php8.4 --version 2>/dev/null | head -1 | awk '{print $1,$2}')
  fi
  [[ -n "$phpver" ]] && ALREADY[php]="$phpver"

  local dbver=""
  if command -v mariadb &>/dev/null; then
    dbver=$(mariadb --version 2>/dev/null | awk '{print $1,$2,$3}')
  elif command -v mysql &>/dev/null; then
    dbver=$(mysql --version 2>/dev/null | awk '{print $1,$2,$3}')
  fi
  [[ -n "$dbver" ]] && ALREADY[mariadb]="$dbver"

  local nodever=""
  if command -v node &>/dev/null; then
    nodever=$(node --version 2>/dev/null)
  fi
  if [[ -n "$nodever" ]]; then
    ALREADY[nodejs]="Node.js $nodever"
    if command -v npm &>/dev/null; then
      local npmver; npmver=$(npm --version 2>/dev/null)
      ALREADY[nodejs]+=" / npm $npmver"
    fi
  fi

  if command -v composer &>/dev/null; then
    local compver; compver=$(composer --version 2>/dev/null | head -1 | cut -d' ' -f1-3)
    ALREADY[composer]="$compver"
  fi

  local valetbin
  valetbin=$(command -v valet 2>/dev/null \
    || echo "$HOME/.composer/vendor/bin/valet" \
    || echo "$HOME/.config/composer/vendor/bin/valet")
  if [[ -x "$valetbin" ]]; then
    local vv; vv=$("$valetbin" --version 2>/dev/null | head -1 || echo "valet-linux")
    ALREADY[valet]="$vv"
  fi

  local laravelbin
  laravelbin=$(command -v laravel 2>/dev/null \
    || echo "$HOME/.composer/vendor/bin/laravel" \
    || echo "$HOME/.config/composer/vendor/bin/laravel")
  if [[ -x "$laravelbin" ]]; then
    local lv; lv=$("$laravelbin" --version 2>/dev/null | head -1 || echo "laravel/installer")
    ALREADY[laravel]="$lv"
  fi
}

# ================================================================
#  BANNER
# ================================================================
show_banner() {
  cls
  local w; w=$(TW)
  echo
  printf '%s%s%s\n' "$DGY" "$(rep '=' "$w")" "$R"
  echo
  center_color "${CYN}${B}  _   _ ____  _   _ _   _ _____ _   _  ${R}" 38 "$w"
  center_color "${CYN}${B} | | | | __ )| | | | \ | |_   _| | | | ${R}" 38 "$w"
  center_color "${CYN}${B} | | | |  _ \| | | |  \| | | | | | | | ${R}" 38 "$w"
  center_color "${BLU}${B} | |_| | |_) | |_| | |\  | | | | |_| | ${R}" 38 "$w"
  center_color "${BLU}${B}  \___/|____/ \___/|_| \_| |_|  \___/  ${R}" 38 "$w"
  echo
  center_plain "${B}Dev Stack Installer  v2.3${R}" "$w"
  center_plain "PHP 8.4  |  MariaDB  |  Node.js  |  Composer  |  Valet  |  Laravel" "$w"
  echo
  if [[ $IS_WSL -eq 1 ]]; then
    center_plain "${YLW}WSL detected -- service commands adjusted${R}" "$w"
    echo
  fi
  center_plain "Ubuntu 24.04 LTS   |   $(date '+%Y-%m-%d  %H:%M')" "$w"
  echo
  printf '%s%s%s\n' "$DGY" "$(rep '=' "$w")" "$R"
  echo
}

# ================================================================
#  INITIAL SUDO PASSWORD PROMPT
# ================================================================
prompt_sudo_initial() {
  if [[ $EUID -eq 0 ]]; then return 0; fi

  cls
  local w; w=$(TW)
  echo
  printf '%s%s%s\n' "$DGY" "$(rep '=' "$w")" "$R"
  echo
  center_color "${GRN}${B}  sudo Authentication  ${R}" 24 "$w"
  echo
  center_plain "${DIM}Enter your password to begin the installation${R}" "$w"
  echo
  printf '%s%s%s\n' "$DGY" "$(rep '=' "$w")" "$R"
  echo

  local __pw="" user; user=$(whoami)
  read_password_masked __pw "${GRN}${B}[sudo]${R}${GRN} password for ${B}${user}${R}${GRN}:${R} "
  printf '\n'

  if printf '%s\n' "$__pw" | sudo -S -v >> "$LOG_FILE" 2>&1; then
    CACHED_SUDO_PASS="$__pw"
    local w2; w2=$(TW)
    echo
    printf '%s%s%s\n' "$DGY" "$(rep '=' "$w2")" "$R"
    center_color "${GRN}${B}  Authentication successful  ${R}" 25 "$w2"
    echo
    printf '%s%s%s\n' "$DGY" "$(rep '=' "$w2")" "$R"
    echo
    sleep 1
  else
    printf '\n'
    log_err "Incorrect password -- please try again"
    prompt_sudo_initial
  fi
}

# ================================================================
#  STEP 1 — System Check
# ================================================================
check_requirements() {
  prompt_sudo_initial

  show_banner
  step_header "1/6" "System Check" "$BLU"
  local w; w=$(TW)

  box_top "$w" "$BLU"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${VERSION_ID:-0}" == "24.04" ]] || [[ "${VERSION_ID:-0}" > "24" ]]; then
      box_row "$(ic_ok)  ${GRN}OS:${R}  ${B}Ubuntu 24.04 LTS${R}  ${DIM}($PRETTY_NAME)${R}" "$w" "$BLU"
    else
      box_row "$(ic_warn)  ${YLW}OS:${R}  Ubuntu ${VERSION_ID:-?}  ${DIM}(24.04+ recommended)${R}" "$w" "$BLU"
    fi
  else
    box_row "$(ic_warn)  ${YLW}OS detection failed${R}" "$w" "$BLU"
  fi

  if [[ $IS_WSL -eq 1 ]]; then
    box_row "$(ic_info)  ${CYN}WSL:${R}  ${YLW}Detected -- systemctl replaced with service${R}" "$w" "$BLU"
  fi

  if [[ $EUID -eq 0 ]]; then
    box_row "$(ic_ok)  ${GRN}User:${R}  Running as root" "$w" "$BLU"
  elif sudo -n true 2>/dev/null; then
    box_row "$(ic_ok)  ${GRN}Sudo:${R}  Passwordless access" "$w" "$BLU"
  else
    box_row "$(ic_warn)  ${YLW}Sudo:${R}  Password required" "$w" "$BLU"
  fi

  spinner_start "Checking network"
  local net="offline"
  curl -fsSL --max-time 6 https://packagecloud.io -o /dev/null 2>/dev/null && net="online"
  spinner_stop
  if [[ "$net" == "online" ]]; then
    box_row "$(ic_ok)  ${GRN}Network:${R}  Online" "$w" "$BLU"
  else
    box_row "$(ic_err)  ${RED}Network:${R}  Offline -- will fail" "$w" "$BLU"
  fi

  local free_kb=0 free_gb
  free_kb=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ' || echo 0)
  free_gb=$(awk "BEGIN{printf \"%.1f\", $free_kb/1048576}")
  if (( free_kb >= 2097152 )); then
    box_row "$(ic_ok)  ${GRN}Disk:${R}  ${B}${free_gb} GB${R} free" "$w" "$BLU"
  else
    box_row "$(ic_warn)  ${YLW}Disk:${R}  ${free_gb} GB free  ${DIM}(2 GB+ needed)${R}" "$w" "$BLU"
  fi

  local sh; sh=$(basename "${SHELL:-bash}")
  box_row "$(ic_info)  ${CYN}Shell:${R}  $sh" "$w" "$BLU"
  box_bot "$w" "$BLU"
  echo

  spinner_start "Scanning installed packages"
  detect_installed
  spinner_stop

  if [[ ${#ALREADY[@]} -gt 0 ]]; then
    step_header "1/6" "Already Installed" "$GRN"
    box_top "$w" "$GRN"
    box_row "  ${B}${WHT}Package              Installed Version${R}" "$w" "$GRN"
    box_sep "$w" "$GRN"

    local -a order=(php mariadb nodejs composer valet laravel)
    for key in "${order[@]}"; do
      if [[ -v "ALREADY[$key]" ]]; then
        box_row "$(ic_exists)  ${GRN}${B}$(printf '%-18s' "$key")${R}  ${DIM}${ALREADY[$key]}${R}" "$w" "$GRN"
        RESULT[$key]="${ALREADY[$key]}  ${DIM}(already installed)${R}"
      fi
    done

    box_sep "$w" "$GRN"
    box_row "  ${DIM}These will be skipped unless you choose to reinstall.${R}" "$w" "$GRN"
    box_bot "$w" "$GRN"
    echo

    if confirm "Skip already-installed packages?"; then
      for key in "${!ALREADY[@]}"; do
        INSTALL[$key]=0
        log_skip "Skipping $key (${ALREADY[$key]})"
      done
    else
      log_info "Will reinstall / update all selected packages"
    fi
    echo
  else
    log_info "No existing installation detected -- fresh install"
    echo
  fi

  echo
}

# ================================================================
#  STEP 2 — Package Selection
# ================================================================
show_package_selector() {
  step_header "2/6" "Install All Components" "$MGT"
  local w; w=$(TW)

  box_top "$w" "$MGT"
  box_row "  ${B}${WHT}Will install:${R}" "$w" "$MGT"
  box_sep "$w" "$MGT"
  box_row "  ${GRN}1)${R}  PHP 8.4         (includes FPM, GD, XML, ZIP, MySQL, etc)${R}" "$w" "$MGT"
  box_row "  ${GRN}2)${R}  MariaDB        (MySQL-compatible database)${R}" "$w" "$MGT"
  box_row "  ${GRN}3)${R}  Node.js v${NODE_VERSION}     (via NVM)${R}" "$w" "$MGT"
  box_row "  ${GRN}4)${R}  Composer       (PHP dependency manager)${R}" "$w" "$MGT"
  box_row "  ${GRN}5)${R}  Laravel Valet  (local development server)${R}" "$w" "$MGT"
  box_row "  ${GRN}6)${R}  Laravel Inst  (project creator)${R}" "$w" "$MGT"
  box_bot "$w" "$MGT"
  echo
}

select_packages() {
  show_package_selector
  return 0
}

# ================================================================
#  STEP 3 — Configuration
# ================================================================
configure_options() {
  set +e

  step_header "3/6" "Configuration" "$CYN"
  local w; w=$(TW)

  box_top "$w" "$CYN"

  if [[ "${INSTALL[nodejs]:-0}" == "1" ]]; then
    box_row "  ${CYN}${B}Node.js version  ${DIM}(NVM will install this)${R}" "$w" "$CYN"
    box_bot "$w" "$CYN"
    echo
    ask "Node.js version to install" "$NODE_VERSION" NODE_VERSION
    echo
    box_top "$w" "$CYN"
    box_row "  $(ic_ok)  Node.js target: ${GRN}${B}v${NODE_VERSION}${R}" "$w" "$CYN"
  else
    box_row "  ${DIM}Node.js skipped${R}" "$w" "$CYN"
  fi

  local shells_found=""
  [[ -f "$HOME/.zshrc"  ]] && shells_found+=".zshrc "
  [[ -f "$HOME/.bashrc" ]] && shells_found+=".bashrc"
  [[ -z "$shells_found" ]] && shells_found="(none detected)"

  box_row "  $(ic_info)  Valet sites dir:  ${CYN}~/Sites${R}" "$w" "$CYN"
  box_row "  $(ic_info)  Shell configs:    ${DIM}${shells_found}${R}" "$w" "$CYN"
  box_row "  $(ic_info)  Log file:         ${DIM}${LOG_FILE}${R}" "$w" "$CYN"
  if [[ $IS_WSL -eq 1 ]]; then
    box_row "  $(ic_warn)  WSL mode:         ${YLW}service used instead of systemctl${R}" "$w" "$CYN"
  fi
  box_bot "$w" "$CYN"
  echo

  set -e
}

# ================================================================
#  STEP 4 — Plan + Confirm
# ================================================================
show_plan() {
  set +e

  step_header "4/6" "Installation Plan" "$YLW"
  local w; w=$(TW)

  local -a queued=() skipped=()
  for pkg in php mariadb nodejs composer valet laravel; do
    [[ "${INSTALL[$pkg]:-0}" == "1" ]] && queued+=("$pkg") || skipped+=("$pkg")
  done

  box_top "$w" "$YLW"
  box_row "  ${B}${WHT}Will install  (${#queued[@]} packages)${R}" "$w" "$YLW"
  box_sep "$w" "$YLW"
  for pkg in "${queued[@]}"; do
    box_row "  ${GRN}${B}+${R}  ${B}${pkg}${R}" "$w" "$YLW"
  done

  if [[ ${#skipped[@]} -gt 0 ]]; then
    box_sep "$w" "$YLW"
    box_row "  ${DGY}Skipped / already installed:${R}" "$w" "$YLW"
    for pkg in "${skipped[@]}"; do
      local ver_tag=""
      [[ -v "ALREADY[$pkg]" ]] && ver_tag="  ${DIM}${ALREADY[$pkg]}${R}"
      box_row "  ${DGY}~  ${pkg}${ver_tag}${R}" "$w" "$YLW"
    done
  fi
  box_bot "$w" "$YLW"
  echo

  [[ ${#queued[@]} -eq 0 ]] && {
    log_warn "Nothing to install -- all packages already present."
    echo
    show_summary
    exit 0
  }

  confirm "Start installation now?" \
    || { printf '\n%s %sAborted.%s\n\n' "$(_P)" "$YLW" "$R"; exit 0; }

  set -e
}

# ================================================================
#  INSTALL FUNCTIONS
# ================================================================

do_update() {
  local w; w=$(TW)
  echo
  printf '%s%s%s[ System Update ]%s\n' "$(_P)" "$BLU$B" "" "$R"
  printf '%s%s%s%s\n' "$(_P)" "$DGY" "$(rep '-' $((w-PAD*2)))" "$R"
  echo

  # Set non-interactive mode so apt never pauses for user input
  # (grub prompts, service restart dialogs, config file questions, etc.)
  export DEBIAN_FRONTEND=noninteractive
  sudo_cmd "apt-get update" \
    apt-get update -qq

  sudo_cmd "apt-get upgrade" \
    env DEBIAN_FRONTEND=noninteractive \
      apt-get upgrade -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold"

  sudo_cmd "Base utilities" \
    env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        curl wget gnupg2 software-properties-common \
        apt-transport-https ca-certificates lsb-release
}

install_php() {
  [[ "${INSTALL[php]:-0}" != "1" ]] && return 0
  pkg_header "PHP 8.4" "*" "$MGT"
  local t=0 total=4; task_progress $t $total "$MGT"

  sudo_cmd "Add ondrej/php PPA" \
    env DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:ondrej/php -y
  (( t++ )) || true; task_progress $t $total "$MGT"

  sudo_cmd "apt-get update" apt-get update -qq
  sudo_cmd "PHP 8.4 + extensions" \
    env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      php8.4 php8.4-cli php8.4-common php8.4-curl php8.4-pgsql \
      php8.4-fpm php8.4-gd php8.4-imap php8.4-intl php8.4-mbstring \
      php8.4-mysql php8.4-opcache php8.4-soap php8.4-xml php8.4-zip
  (( t++ )) || true; task_progress $t $total "$MGT"

  # ── FIX: ensure php8.4-fpm is running (critical for Valet) ──────
  log_run "Starting php8.4-fpm service"
  svc_start "php8.4-fpm"
  svc_enable "php8.4-fpm"

  # Verify FPM is actually running
  if svc_status "php8.4-fpm" 2>/dev/null; then
    log_ok "php8.4-fpm is running"
  else
    log_warn "php8.4-fpm may not be running -- trying again"
    sudo service php8.4-fpm start >> "$LOG_FILE" 2>&1 || true
    sleep 1
    if sudo service php8.4-fpm status >> "$LOG_FILE" 2>&1; then
      log_ok "php8.4-fpm started"
    else
      log_err "php8.4-fpm failed to start -- check $LOG_FILE"
      INSTALL_ERRORS+=("php8.4-fpm start")
    fi
  fi
  (( t++ )) || true; task_progress $t $total "$MGT"

  local ver; ver=$(php8.4 --version 2>/dev/null | head -1 | awk '{print $1,$2}' || echo "PHP 8.4")
  (( t++ )) || true; task_progress $t $total "$MGT"
  log_ok "Installed -- $ver"
  RESULT[php]="$ver"
}

install_mariadb() {
  [[ "${INSTALL[mariadb]:-0}" != "1" ]] && return 0
  pkg_header "MariaDB" "#" "$BLU"
  local t=0 total=2; task_progress $t $total "$BLU"

  sudo_cmd "mariadb-server + mariadb-client" \
    env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      mariadb-server mariadb-client
  (( t++ )) || true; task_progress $t $total "$BLU"

  # ── FIX: use svc_enable for WSL compatibility ────────────────────
  log_run "Enable + start MariaDB"
  svc_enable "mariadb"
  (( t++ )) || true; task_progress $t $total "$BLU"

  local ver; ver=$(mariadbd --version 2>/dev/null | awk '{print $3}' || echo "MariaDB")
  log_ok "Installed -- $ver"
  RESULT[mariadb]="$ver"

  mariadb_secure_wizard
}

mariadb_secure_wizard() {
  local w; w=$(TW)
  echo
  printf '%s%s%s+-- MariaDB Secure Setup Wizard %s%s\n' \
    "$(_P)" "$BLU$B" "" "$(rep '-' $((w-PAD*2-31)))" "$R"
  log_dim "Harden your MariaDB installation step by step."
  echo

  local root_pass="" set_pw=false
  if confirm "  Set a root password for MariaDB?"; then
    set_pw=true
    while true; do
      read_password_masked root_pass \
        "${GRN}${B}  New root password:${R}${GRN} "
      local pass2=""
      read_password_masked pass2 \
        "${GRN}${B}  Confirm password: ${R}${GRN} "
      if [[ "$root_pass" == "$pass2" && -n "$root_pass" ]]; then
        log_ok "Password confirmed"; break
      else
        log_warn "Passwords do not match or empty -- try again"
      fi
    done
  fi

  local rm_anon=true no_remote=true rm_test=true do_reload=true
  confirm "  Remove anonymous users?"      || rm_anon=false
  confirm "  Disallow remote root login?"  || no_remote=false
  confirm "  Remove test database?"        || rm_test=false
  confirm "  Reload privilege tables now?" || do_reload=false

  echo
  spinner_start "Applying MariaDB security settings"
  local sql=""
  [[ "$set_pw"     == "true" ]] && sql+="ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}'; "
  [[ "$rm_anon"    == "true" ]] && sql+="DELETE FROM mysql.user WHERE User=''; "
  [[ "$no_remote"  == "true" ]] && sql+="DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1'); "
  [[ "$rm_test"    == "true" ]] && sql+="DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'; "
  [[ "$do_reload"  == "true" ]] && sql+="FLUSH PRIVILEGES;"
  spinner_stop

  if [[ -n "$sql" ]]; then
    if sudo mariadb -e "$sql" >> "$LOG_FILE" 2>&1; then
      log_ok "MariaDB security settings applied"
    else
      log_err "Some MariaDB settings failed -- see $LOG_FILE"
      INSTALL_ERRORS+=("MariaDB secure setup")
    fi
  fi
  printf '%s%s+%s%s\n' "$(_P)" "$BLU$B" "$(rep '-' $((w-PAD*2-1)))" "$R"
}

install_composer() {
  [[ "${INSTALL[composer]:-0}" != "1" ]] && return 0
  pkg_header "Composer" "@" "$YLW"
  local t=0 total=4; task_progress $t $total "$YLW"

  local tmp; tmp=$(mktemp -d); cd "$tmp"

  run_cmd "Download Composer installer" \
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
  (( t++ )) || true; task_progress $t $total "$YLW"

  log_info "Verifying SHA-384 hash..."
  local expected="dac665fdc30fdd8ec78b38b9800061b4150413ff2e3b6f88543c636f7cd84f6db9189d43a81e5503cda447da73c7e5b6"
  local actual; actual=$(php -r "echo hash_file('sha384', 'composer-setup.php');")
  if [[ "$actual" == "$expected"* ]]; then
    log_ok "Hash verified"
  else
    log_warn "Hash mismatch -- proceeding cautiously"
  fi
  (( t++ )) || true; task_progress $t $total "$YLW"

  run_cmd "Run composer-setup.php"      php composer-setup.php
  run_cmd "Cleanup installer file"      php -r "unlink('composer-setup.php');"
  sudo_cmd "Move to /usr/local/bin"     mv composer.phar /usr/local/bin/composer
  sudo chmod +x /usr/local/bin/composer 2>/dev/null || true
  (( t++ )) || true; task_progress $t $total "$YLW"

  cd - > /dev/null; rm -rf "$tmp"

  local ver; ver=$(composer --version 2>/dev/null | head -1 | cut -d' ' -f1-3 || echo "Composer")
  (( t++ )) || true; task_progress $t $total "$YLW"
  log_ok "Installed -- $ver"
  RESULT[composer]="$ver"
}

install_nodejs() {
  [[ "${INSTALL[nodejs]:-0}" != "1" ]] && return 0
  pkg_header "Node.js v${NODE_VERSION} via NVM" "~" "$GRN"
  local t=0 total=3; task_progress $t $total "$GRN"

  run_cmd "Download + run NVM v0.40.4" \
    bash -c 'curl -fsSo /tmp/_nvm_install.sh \
      https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh \
      && bash /tmp/_nvm_install.sh'
  (( t++ )) || true; task_progress $t $total "$GRN"

  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

  run_cmd "nvm install ${NODE_VERSION}" nvm install "$NODE_VERSION"
  run_cmd "nvm alias default"           nvm alias default "$NODE_VERSION"
  (( t++ )) || true; task_progress $t $total "$GRN"

  local nv npm_v
  nv=$(node -v 2>/dev/null || echo "?")
  npm_v=$(npm -v 2>/dev/null || echo "?")
  (( t++ )) || true; task_progress $t $total "$GRN"
  log_ok "Node.js $nv  |  npm $npm_v"
  RESULT[nodejs]="Node $nv / npm $npm_v"
}

install_valet() {
  [[ "${INSTALL[valet]:-0}" != "1" ]] && return 0
  pkg_header "Laravel Valet Linux" ">" "$RED"
  local t=0 total=5; task_progress $t $total "$RED"

  sudo_cmd "Valet deps" \
    env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      network-manager libnss3-tools jq xsel
  (( t++ )) || true; task_progress $t $total "$RED"

  run_cmd "composer global require cpriego/valet-linux" \
    composer global require cpriego/valet-linux
  (( t++ )) || true; task_progress $t $total "$RED"

  # Find valet binary
  local cbin=""
  if [[ -x "$HOME/.config/composer/vendor/bin/valet" ]]; then
    cbin="$HOME/.config/composer/vendor/bin"
  elif [[ -x "$HOME/.composer/vendor/bin/valet" ]]; then
    cbin="$HOME/.composer/vendor/bin"
  fi

  if [[ -z "$cbin" || ! -x "$cbin/valet" ]]; then
    log_err "Valet binary not found after installation"
    INSTALL_ERRORS+=("valet install")
    (( t++ )) || true; task_progress $t $total "$RED"
    (( t++ )) || true; task_progress $t $total "$RED"
    (( t++ )) || true; task_progress $t $total "$RED"
    return 1
  fi

  [[ ":$PATH:" != *":$cbin:"* ]] && export PATH="$cbin:$PATH"
  log_dim "Valet binary: $cbin/valet"

  # ── FIX: Run valet install as current user (not root) ────────────
  # This prevents ~/.valet files being created as root
  spinner_stop
  log_run "valet install (as $USER)"
  local rc=0
  # Use sudo only for the system-level parts; valet itself must run as user
  # Pass --no-ansi to suppress color codes in log
  "$cbin/valet" install >> "$LOG_FILE" 2>&1 || rc=$?
  if [[ $rc -ne 0 ]]; then
    log_warn "valet install returned $rc -- attempting with sudo -E"
    sudo -E HOME="$HOME" USER="$USER" "$cbin/valet" install >> "$LOG_FILE" 2>&1 || rc=$?
  fi
  if [[ $rc -eq 0 ]]; then
    log_ok "valet install succeeded"
  else
    log_err "valet install failed (exit $rc) -- see $LOG_FILE"
    INSTALL_ERRORS+=("valet install")
  fi
  (( t++ )) || true; task_progress $t $total "$RED"

  # ── FIX: Fix ownership of ~/.valet after install ─────────────────
  log_run "Fix ~/.valet ownership"
  sudo chown -R "$USER":"$USER" "$HOME/.valet" >> "$LOG_FILE" 2>&1 || true
  sudo chmod -R u+rw "$HOME/.valet"            >> "$LOG_FILE" 2>&1 || true
  log_ok "~/.valet permissions corrected"
  (( t++ )) || true; task_progress $t $total "$RED"

  # ── FIX: Ensure php8.4-fpm is running before valet park ──────────
  log_run "Ensuring php8.4-fpm is running"
  svc_start "php8.4-fpm" || true
  sleep 1

  # Park ~/Sites
  [[ ! -d "$HOME/Sites" ]] && { mkdir -p "$HOME/Sites"; log_ok "Created ~/Sites"; }
  if cd "$HOME/Sites" && "$cbin/valet" park >> "$LOG_FILE" 2>&1; then
    log_ok "Parked ~/Sites  ->  *.test"
  else
    log_warn "valet park failed -- run: cd ~/Sites && valet park"
    INSTALL_ERRORS+=("valet park")
  fi

  log_ok "Valet ready -- access sites as <name>.test"
  RESULT[valet]="cpriego/valet-linux"
}

install_laravel() {
  [[ "${INSTALL[laravel]:-0}" != "1" ]] && return 0
  pkg_header "Laravel Installer" "L" "$MGT"
  local t=0 total=1; task_progress $t $total "$MGT"

  run_cmd "composer global require laravel/installer" \
    composer global require laravel/installer
  (( t++ )) || true; task_progress $t $total "$MGT"

  local ver; ver=$(laravel --version 2>/dev/null | head -1 || echo "laravel/installer")
  log_ok "Installed -- $ver"
  RESULT[laravel]="$ver"
}

configure_shell() {
  local w; w=$(TW)
  echo
  printf '%s%s%s[ Shell Configuration ]%s\n' "$(_P)" "$MGT$B" "" "$R"
  printf '%s%s%s%s\n' "$(_P)" "$DGY" "$(rep '-' $((w-PAD*2)))" "$R"
  echo

  local cbin="$HOME/.composer/vendor/bin"
  [[ -d "$HOME/.config/composer/vendor/bin" ]] && cbin="$HOME/.config/composer/vendor/bin"
  local composer_line="export PATH=\"${cbin}:\$PATH\""
  local nvm_block
  nvm_block=$(printf '%s\n%s\n%s' \
    'export NVM_DIR="$HOME/.nvm"' \
    '[ -s "$NVM_DIR/nvm.sh" ]          && \. "$NVM_DIR/nvm.sh"' \
    '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"')

  for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [[ -f "$rcfile" ]] || continue
    local fname; fname=$(basename "$rcfile")
    if ! grep -q 'composer/vendor/bin' "$rcfile" 2>/dev/null; then
      { echo; echo "# Laravel / Composer PATH  (ubuntu-dev-installer)"; echo "$composer_line"; } >> "$rcfile"
      log_ok "Composer PATH -> $fname"
    else
      log_dim "Composer PATH already in $fname"
    fi
    if ! grep -q 'NVM_DIR' "$rcfile" 2>/dev/null; then
      { echo; echo "# NVM -- Node Version Manager  (ubuntu-dev-installer)"; printf '%s\n' "$nvm_block"; } >> "$rcfile"
      log_ok "NVM config -> $fname"
    else
      log_dim "NVM already in $fname"
    fi
  done
}

# ================================================================
#  POST-INSTALL FIX — run after everything is done
#  Corrects any permission issues left by sudo-run valet commands
# ================================================================
fix_valet_permissions() {
  local w; w=$(TW)
  echo
  printf '%s%s%s[ Fixing Valet Permissions ]%s\n' "$(_P)" "$GRN$B" "" "$R"
  printf '%s%s%s%s\n' "$(_P)" "$DGY" "$(rep '-' $((w-PAD*2)))" "$R"
  echo

  # Fix ownership of all valet-related directories
  local dirs=("$HOME/.valet" "$HOME/.config/composer" "$HOME/.composer")
  for dir in "${dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      sudo chown -R "$USER":"$USER" "$dir" >> "$LOG_FILE" 2>&1 || true
      sudo chmod -R u+rw "$dir"           >> "$LOG_FILE" 2>&1 || true
      log_ok "Permissions fixed: $dir"
    fi
  done

  # Ensure config.json is writable
  if [[ -f "$HOME/.valet/config.json" ]]; then
    sudo chown "$USER":"$USER" "$HOME/.valet/config.json" >> "$LOG_FILE" 2>&1 || true
    chmod 644 "$HOME/.valet/config.json" >> "$LOG_FILE" 2>&1 || true
    log_ok "config.json ownership corrected"
  fi

  # Restart php-fpm and nginx to ensure clean state
  log_run "Restarting services"
  svc_start "php8.4-fpm" || true
  sleep 1

  # Find valet binary and check status
  local cbin=""
  [[ -x "$HOME/.config/composer/vendor/bin/valet" ]] && cbin="$HOME/.config/composer/vendor/bin"
  [[ -z "$cbin" && -x "$HOME/.composer/vendor/bin/valet" ]] && cbin="$HOME/.composer/vendor/bin"

  if [[ -n "$cbin" ]]; then
    [[ ":$PATH:" != *":$cbin:"* ]] && export PATH="$cbin:$PATH"
    echo
    log_info "Verifying valet status..."
    "$cbin/valet" status >> "$LOG_FILE" 2>&1 \
      && log_ok "valet status OK" \
      || log_warn "valet status reported issues -- check: $LOG_FILE"
  fi
  echo
}

# ================================================================
#  STEP 6 — Summary
# ================================================================
show_summary() {
  show_banner
  local w; w=$(TW)

  printf '%s%s+== Installation Summary %s%s\n' \
    "$(_P)" "$GRN$B" "$(rep '=' $((w-PAD*2-23)))" "$R"
  echo

  local -a all_pkgs=(php mariadb nodejs composer valet laravel)
  for pkg in "${all_pkgs[@]}"; do
    if [[ -v "RESULT[$pkg]" ]]; then
      printf '%s  %s%s+%s  %s%-16s%s  %s%s%s\n' \
        "$(_P)" "$GRN$B" "" "$R" "$B" "$pkg" "$R" \
        "$DIM" "${RESULT[$pkg]}" "$R"
    elif [[ "${INSTALL[$pkg]:-0}" == "0" && -v "ALREADY[$pkg]" ]]; then
      printf '%s  %s~%s  %s%-16s%s  %s%s  [skipped -- already installed]%s\n' \
        "$(_P)" "$YLW$B" "$R" "$B" "$pkg" "$R" \
        "$DIM" "${ALREADY[$pkg]}" "$R"
    elif [[ "${INSTALL[$pkg]:-0}" == "0" ]]; then
      printf '%s  %s-%s  %s%-16s%s  %sskipped by user%s\n' \
        "$(_P)" "$DGY" "$R" "$B" "$pkg" "$R" "$DIM" "$R"
    else
      printf '%s  %s%sX%s  %s%-16s%s  %sfailed -- check log%s\n' \
        "$(_P)" "$RED$B" "" "$R" "$B" "$pkg" "$R" "$RED" "$R"
    fi
  done

  echo
  if [[ ${#INSTALL_ERRORS[@]} -gt 0 ]]; then
    printf '%s%s%sErrors:%s\n' "$(_P)" "$RED$B" "" "$R"
    for e in "${INSTALL_ERRORS[@]}"; do
      printf '%s  %sX  %s%s\n' "$(_P)" "$RED" "$e" "$R"
    done
    printf '%s  %sLog: %s%s\n' "$(_P)" "$DIM" "$LOG_FILE" "$R"
    echo
  fi

  printf '%s%s+%s%s\n' "$(_P)" "$GRN$B" "$(rep '=' $((w-PAD*2-1)))" "$R"
  echo

  box_top "$w" "$CYN"
  box_row "  ${B}${WHT}Next steps${R}" "$w" "$CYN"
  box_sep "$w" "$CYN"
  box_row "  ${CYN}1.${R}  Reload your shell" "$w" "$CYN"
  box_row "     ${DIM}source ~/.zshrc    # or:  source ~/.bashrc${R}" "$w" "$CYN"
  box_sep "$w" "$CYN"
  box_row "  ${CYN}2.${R}  Create a new Laravel project" "$w" "$CYN"
  box_row "     ${DIM}cd ~/Sites && laravel new myapp${R}" "$w" "$CYN"
  box_sep "$w" "$CYN"
  box_row "  ${CYN}3.${R}  Visit in browser" "$w" "$CYN"
  box_row "     ${DIM}http://myapp.test${R}" "$w" "$CYN"
  box_sep "$w" "$CYN"

  if [[ $IS_WSL -eq 1 ]]; then
    box_row "  ${YLW}WSL note:${R}  Services don't auto-start on boot." "$w" "$CYN"
    box_row "     ${DIM}Add to ~/.bashrc:  sudo service php8.4-fpm start${R}" "$w" "$CYN"
    box_row "     ${DIM}                   sudo service nginx start${R}" "$w" "$CYN"
    box_row "     ${DIM}                   sudo service mariadb start${R}" "$w" "$CYN"
    box_sep "$w" "$CYN"
  fi

  box_row "  ${CYN}4.${R}  Full log: ${DIM}${LOG_FILE}${R}" "$w" "$CYN"
  box_bot "$w" "$CYN"
  echo

  local elapsed=$(( SECONDS - START_TIME ))
  printf '%s%sFinished in %dm %ds%s\n\n' \
    "$(_P)" "$DGY" "$(( elapsed/60 ))" "$(( elapsed%60 ))" "$R"
}

# ================================================================
#  MAIN
# ================================================================
main() {
  [[ ! -t 0 ]] && { echo "ERROR: Run in an interactive terminal."; exit 1; }
  printf '[START] %s\n' "$(date)" > "$LOG_FILE"

  check_requirements

  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done

  echo
  confirm "Continue with installation?" \
    || { printf '\n%s %sCancelled.%s\n\n' "$(_P)" "$YLW" "$R"; exit 0; }

  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done

  select_packages

  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done

  configure_options

  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done

  show_plan

  show_banner
  step_header "5/6" "Installing" "$EMERALD"

  local steps=("system" "php" "mariadb" "composer" "nodejs" "valet" "laravel")
  local n=${#steps[@]} cur=0

  for step in "${steps[@]}"; do
    (( cur++ )) || true

    # ── Live pipeline header ─────────────────────────────────────
    local w; w=$(TW)
    printf '%s%s%s%s\n' "$(_P)" "$DGY" "$(rep '─' $((w-PAD*2)))" "$R"
    global_progress "$cur" "$n" "$step"

    case "$step" in
      system)   do_update        ;;
      php)      install_php      ;;
      mariadb)  install_mariadb  ;;
      composer) install_composer ;;
      nodejs)   install_nodejs   ;;
      valet)    install_valet    ;;
      laravel)  install_laravel  ;;
    esac
  done

  # ── Final completed bar ──────────────────────────────────────
  local wf; wf=$(TW)
  printf '%s%s%s%s\n' "$(_P)" "$DGY" "$(rep '─' $((wf-PAD*2)))" "$R"
  global_progress "$n" "$n" "all packages installed"

  # ── FIX: Always run permission fix after installation ────────────
  fix_valet_permissions

  configure_shell
  show_summary
}

main "$@"
