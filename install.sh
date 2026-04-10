#!/usr/bin/env bash
# ================================================================
#  Ubuntu Dev Stack Installer  v2.2
#  PHP 8.4  MariaDB  Node.js  Composer  Valet  Laravel
#  Ubuntu 24.04 LTS
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

# ── State ─────────────────────────────────────────────────────────
LOG_FILE="/tmp/ubuntu-dev-installer-$(date +%s).log"
NODE_VERSION="24"
declare -A INSTALL=([php]=1 [mariadb]=1 [nodejs]=1 [composer]=1 [valet]=1 [laravel]=1)
declare -A RESULT=()
declare -A ALREADY=()    # versions already installed
INSTALL_ERRORS=()
START_TIME=$SECONDS
CACHED_SUDO_PASS=""      # Password cacheado para reutilizar

# ── Terminal ──────────────────────────────────────────────────────
TW()       { tput cols  2>/dev/null || echo 80; }
cls()      { printf '\033[2J\033[H'; }
cur_hide() { printf '\033[?25l'; }
cur_show() { printf '\033[?25h'; }
trap 'cur_show; tput sgr0 2>/dev/null || true; echo' EXIT INT TERM

PAD=3
_P() { printf '%*s' "$PAD" ''; }

# ── rep: repeat char N times (loop-safe for multibyte) ───────────
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

# ── Box chars (UTF-8 if locale supports it, ASCII fallback) ───────
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
ic_ok()    { printf '%s%s+%s' "$GRN" "$B" "$R"; }
ic_skip()  { printf '%s%s~%s' "$YLW" "$B" "$R"; }
ic_err()   { printf '%s%sX%s' "$RED" "$B" "$R"; }
ic_info()  { printf '%s%si%s' "$CYN" "$B" "$R"; }
ic_warn()  { printf '%s%s!%s' "$YLW" "$B" "$R"; }
ic_arr()   { printf '%s>%s'   "$CYN"      "$R"; }
ic_dot()   { printf '%s.%s'   "$DGY"      "$R"; }
ic_exists(){ printf '%s%s*%s' "$GRN" "$B" "$R"; }

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
#  SUDO PASSWORD PROMPT — colored green with * masking
# ================================================================
# Reads a password character by character, printing * for each.
# Returns the password in the variable named by $1.
read_password_masked() {
  local __varname="$1"
  local __prompt="${2:-Password: }"
  local __pass=""
  local __char

  # Print colored prompt
  printf '%s%s%s%s' "$GRN" "$B" "$__prompt" "$R"

  # Read char by char
  while IFS= read -r -s -n1 __char; do
    # Enter key (empty string or carriage return)
    if [[ -z "$__char" || "$__char" == $'\r' ]]; then
      echo   # newline after password
      break
    fi
    # Backspace
    if [[ "$__char" == $'\177' || "$__char" == $'\010' ]]; then
      if [[ -n "$__pass" ]]; then
        __pass="${__pass%?}"
        # Erase last * on screen
        printf '\b \b'
      fi
    else
      __pass+="$__char"
      printf '%s*%s' "$GRN" "$R"
    fi
  done

  printf -v "$__varname" '%s' "$__pass"
}

# ================================================================
#  CUSTOM SUDO: intercepts the password prompt, shows it in green
#  with * masking, then feeds it to sudo via stdin (-S flag).
# ================================================================
sudo_ask() {
  # Usage: sudo_ask "description" cmd [args...]
  local desc="$1"; shift
  spinner_stop

  # Check if sudo already has cached credentials
  if sudo -n true 2>/dev/null; then
    # No password needed right now
    log_run "$desc"
    local rc=0
    sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then log_ok "$desc"
    else log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc"); fi
    return $rc
  fi

  # Need a password - use cached or prompt
  local __pw=""
  local user; user=$(whoami)
  
  if [[ -n "$CACHED_SUDO_PASS" ]]; then
    # Use cached password
    log_run "$desc"
    local rc=0
    printf '%s\n' "$CACHED_SUDO_PASS" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    if [[ $rc -eq 0 ]]; then log_ok "$desc"
    else
      # Cached password failed, prompt for new one
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

  # No cached password - prompt user
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

# Warm-up sudo cache once at startup with our styled prompt
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

# ── run_cmd (non-sudo, with spinner) ─────────────────────────────
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

# sudo_cmd: runs command with sudo (credentials cached at start)
sudo_cmd() {
  local desc="$1"; shift
  spinner_stop
  
  log_run "$desc"
  local rc=0
  
  # Check if sudo is already cached (no password needed)
  if sudo -n true 2>/dev/null; then
    # Already cached - use it directly
    sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  else
    # Not cached - use cached password from initial auth
    if [[ -n "$CACHED_SUDO_PASS" ]]; then
      printf '%s\n' "$CACHED_SUDO_PASS" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    else
      # Fallback: try direct sudo (will prompt)
      sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
    fi
  fi
  
  if [[ $rc -eq 0 ]]; then log_ok "$desc"
  else log_err "$desc  (exit $rc)"; log_dim "see: $LOG_FILE"; INSTALL_ERRORS+=("$desc"); fi
  return $rc
}

# ── Pacman Progress Bar (animated) ─────────────────────────────────
PACMAN_FRAMES=('◐' '◑' '◒' '◓' '◔' '◕')
PACMAN_DIRTY='●'
PACMAN_CLEAN='○'

global_progress() {
  local cur="$1" tot="$2" lbl="${3:-}"
  local w; w=$(TW)
  local bar_w=$(( w - PAD*2 - 20 ))
  [[ $bar_w -lt 10 ]] && bar_w=10
  local filled=$(( cur * bar_w / tot ))
  local empty=$(( bar_w - filled ))
  local pct=$(( cur * 100 / tot ))
  
  local pacman_frame="${PACMAN_FRAMES[$((SECONDS % 6))]}"
  local bar_filled=""
  for ((i=0; i<filled; i++)); do
    if [[ $i -eq $((filled-1)) && $cur -lt $tot ]]; then
      bar_filled+="$GRN$pacman_frame$R"
    else
      bar_filled+="$GRN$PACMAN_DIRTY$R"
    fi
  done
  
  printf '%s%s[%s%s%s]%s %s%3d%%%s  %s%s%s\n' \
    "$(_P)" "$DGY" "$bar_filled" "$DGY" "$(rep "$PACMAN_CLEAN" "$empty")" "$R" \
    "$B$WHT" "$pct" "$R" \
    "$DIM" "$lbl" "$R"
}

task_progress() {
  local cur="$1" tot="$2" color="${3:-$CYN}"
  local w; w=$(TW)
  local bar_w=$(( w - PAD*2 - 4 ))
  [[ $bar_w -lt 8 ]] && bar_w=8
  local filled=$(( cur * bar_w / tot ))
  local empty=$(( bar_w - filled ))
  
  local pacman_frame="${PACMAN_FRAMES[$((SECONDS % 6))]}"
  if [[ $cur -lt $tot ]]; then
    printf '%s%s|%s%s%s%s%s|%s\n' \
      "$(_P)" "$DGY" "$color" "$(rep '█' "$filled")" "$color$pacman_frame$R" \
      "$DGY" "$(rep '░' "$empty")" "$R"
  else
    printf '%s%s|%s%s%s|%s\n' \
      "$(_P)" "$DGY" "$GRN" "$(rep '█' "$bar_w")" "$R"
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
  local num="$1" title="$2" color="${3:-$CYN}"
  local w; w=$(TW)
  echo
  printf '%s%s%s[ Step %s ]  %s%s%s\n' \
    "$(_P)" "$color$B" "$B" "$num" "$WHT" "$title" "$R"
  printf '%s%s%s%s\n' "$(_P)" "$color" "$(rep '-' $((w-PAD*2)))" "$R"
  echo
}

pkg_header() {
  local name="$1" glyph="$2" color="${3:-$CYN}"
  local w; w=$(TW)
  local ll=$(( w - PAD*2 - ${#name} - ${#glyph} - 6 ))
  [[ $ll -lt 2 ]] && ll=2
  echo
  printf '%s%s%s+-- %s  %s  %s%s%s\n' \
    "$(_P)" "$color$B" "$B" "$glyph" "$WHT" "$name" \
    "$(rep '-' "$ll")" "$R"
  echo
}

# ================================================================
#  DETECT ALREADY-INSTALLED VERSIONS
# ================================================================
detect_installed() {
  # PHP
  local phpver=""
  if command -v php &>/dev/null; then
    phpver=$(php --version 2>/dev/null | head -1 | awk '{print $1,$2}')
  elif command -v php8.4 &>/dev/null; then
    phpver=$(php8.4 --version 2>/dev/null | head -1 | awk '{print $1,$2}')
  fi
  if [[ -n "$phpver" ]]; then
    ALREADY[php]="$phpver"
  fi

  # MariaDB / MySQL
  local dbver=""
  if command -v mariadb &>/dev/null; then
    dbver=$(mariadb --version 2>/dev/null | awk '{print $1,$2,$3}')
  elif command -v mysql &>/dev/null; then
    dbver=$(mysql --version 2>/dev/null | awk '{print $1,$2,$3}')
  fi
  if [[ -n "$dbver" ]]; then
    ALREADY[mariadb]="$dbver"
  fi

  # Node.js
  local nodever=""
  if command -v node &>/dev/null; then
    nodever=$(node --version 2>/dev/null)
  fi
  if [[ -n "$nodever" ]]; then
    ALREADY[nodejs]="Node.js $nodever"
  fi

  # npm
  if command -v npm &>/dev/null && [[ -n "${ALREADY[nodejs]:-}" ]]; then
    local npmver; npmver=$(npm --version 2>/dev/null)
    ALREADY[nodejs]+=" / npm $npmver"
  fi

  # Composer
  if command -v composer &>/dev/null; then
    local compver; compver=$(composer --version 2>/dev/null | head -1 | cut -d' ' -f1-3)
    ALREADY[composer]="$compver"
  fi

  # Valet
  local valetbin
  valetbin=$(command -v valet 2>/dev/null \
    || echo "$HOME/.composer/vendor/bin/valet" \
    || echo "$HOME/.config/composer/vendor/bin/valet")
  if [[ -x "$valetbin" ]]; then
    local vv; vv=$("$valetbin" --version 2>/dev/null | head -1 || echo "valet-linux")
    ALREADY[valet]="$vv"
  fi

  # Laravel installer
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
  center_plain "${B}Dev Stack Installer  v2.2${R}" "$w"
  center_plain "PHP 8.4  |  MariaDB  |  Node.js  |  Composer  |  Valet  |  Laravel" "$w"
  echo
  center_plain "Ubuntu 24.04 LTS   |   $(date '+%Y-%m-%d  %H:%M')" "$w"
  echo
  printf '%s%s%s\n' "$DGY" "$(rep '=' "$w")" "$R"
  echo
}

# ================================================================
#  INITIAL SUDO PASSWORD PROMPT (UI)
# ================================================================
prompt_sudo_initial() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi

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
    CACHED_SUDO_PASS="$__pw"  # Cache password for later use
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
#  STEP 1 — System Check + Already Installed detection
# ================================================================
check_requirements() {
  prompt_sudo_initial
  
  show_banner
  step_header "1/6" "System Check" "$BLU"
  local w; w=$(TW)

  # ── System status ───────────────────────────────────────────────
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

  # ── Detect already-installed versions ──────────────────────────
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
        local row
        row=$(printf '$(ic_exists)  %s%-18s%s %s%s%s' \
          "${GRN}${B}" "$key" "$R" \
          "${DIM}" "${ALREADY[$key]}" "$R")
        # rebuild with actual ic_exists output
        box_row "$(ic_exists)  ${GRN}${B}$(printf '%-18s' "$key")${R}  ${DIM}${ALREADY[$key]}${R}" "$w" "$GRN"
        # Mark as pre-installed in RESULT so summary shows it
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
#  STEP 2 — Package Selection (all by default)
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
  # Disable exit-on-error for interactive prompts
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
  if [[ -f "$HOME/.zshrc" ]]; then
    shells_found+=".zshrc "
  fi
  if [[ -f "$HOME/.bashrc" ]]; then
    shells_found+=".bashrc"
  fi
  [[ -z "$shells_found" ]] && shells_found="(none detected)"

  box_row "  $(ic_info)  Valet sites dir:  ${CYN}~/Sites${R}" "$w" "$CYN"
  box_row "  $(ic_info)  Shell configs:    ${DIM}${shells_found}${R}" "$w" "$CYN"
  box_row "  $(ic_info)  Log file:         ${DIM}${LOG_FILE}${R}" "$w" "$CYN"
  box_bot "$w" "$CYN"
  echo
  
  # Re-enable exit-on-error
  set -e
}

# ================================================================
#  STEP 4 — Plan + Confirm
# ================================================================
show_plan() {
  # Disable exit-on-error
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
      if [[ -v "ALREADY[$pkg]" ]]; then
        ver_tag="  ${DIM}${ALREADY[$pkg]}${R}"
      fi
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
  
  # Re-enable exit-on-error
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
  sudo_cmd "apt-get update"   apt-get update -qq
  sudo_cmd "apt-get upgrade"  apt-get upgrade -y -qq
  sudo_cmd "Base utilities"   apt-get install -y -qq \
    curl wget gnupg2 software-properties-common \
    apt-transport-https ca-certificates lsb-release
}

install_php() {
  [[ "${INSTALL[php]:-0}" != "1" ]] && return 0
  pkg_header "PHP 8.4" "*" "$MGT"
  local t=0 total=3; task_progress $t $total "$MGT"

  sudo_cmd "Add ondrej/php PPA"  add-apt-repository ppa:ondrej/php -y
  (( t++ )) || true; task_progress $t $total "$MGT"

  sudo_cmd "apt-get update"      apt-get update -qq
  sudo_cmd "PHP 8.4 + extensions" apt-get install -y -qq \
    php8.4 php8.4-cli php8.4-common php8.4-curl php8.4-pgsql \
    php8.4-fpm php8.4-gd php8.4-imap php8.4-intl php8.4-mbstring \
    php8.4-mysql php8.4-opcache php8.4-soap php8.4-xml php8.4-zip
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
    apt-get install -y -qq mariadb-server mariadb-client
  (( t++ )) || true; task_progress $t $total "$BLU"

  sudo_cmd "Enable + start MariaDB" systemctl enable --now mariadb
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
  local t=0 total=4; task_progress $t $total "$RED"

  sudo_cmd "Valet deps" \
    apt-get install -y -qq network-manager libnss3-tools jq xsel
  (( t++ )) || true; task_progress $t $total "$RED"

  run_cmd "composer global require cpriego/valet-linux" \
    composer global require cpriego/valet-linux
  (( t++ )) || true; task_progress $t $total "$RED"

  # Find valet binary - check both possible global locations
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
    return 1
  fi

  [[ ":$PATH:" != *":$cbin:"* ]] && export PATH="$cbin:$PATH"
  log_dim "Valet binary: $cbin/valet"

  # Run valet install (needs sudo for system config)
  spinner_stop
  # Use -E to preserve user environment (HOME, etc.)
  sudo_cmd "valet install" sudo -E HOME="$HOME" "$cbin/valet" install
  (( t++ )) || true; task_progress $t $total "$RED"

  # Park ~/Sites (no sudo needed)
  [[ ! -d "$HOME/Sites" ]] && { mkdir -p "$HOME/Sites"; log_ok "Created ~/Sites"; }
  if cd "$HOME/Sites" && "$cbin/valet" park >> "$LOG_FILE" 2>&1; then
    log_ok "Parked ~/Sites  ->  *.test"
  else
    log_warn "valet park failed -- run: cd ~/Sites && valet park"
    INSTALL_ERRORS+=("valet park")
  fi
  (( t++ )) || true; task_progress $t $total "$RED"

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
      # installed (new or pre-existing)
      printf '%s  %s%s+%s  %s%-16s%s  %s%s%s\n' \
        "$(_P)" "$GRN$B" "" "$R" "$B" "$pkg" "$R" \
        "$DIM" "${RESULT[$pkg]}" "$R"
    elif [[ "${INSTALL[$pkg]:-0}" == "0" && -v "ALREADY[$pkg]" ]]; then
      # skipped because already installed
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
  
  # Flush input buffer before confirmation
  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done
  
  echo
  confirm "Continue with installation?" \
    || { printf '\n%s %sCancelled.%s\n\n' "$(_P)" "$YLW" "$R"; exit 0; }

  # Flush input buffer before package selection
  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done
  
  select_packages
  
  # Flush input buffer before configuration
  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done
  
  configure_options
  
  # Flush input buffer before plan review
  sleep 0.5
  while read -r -t 0.2 -n1 _discard 2>/dev/null; do :; done
  
  show_plan

  show_banner
  step_header "5/6" "Installing" "$GRN"

  local steps=("system" "php" "mariadb" "composer" "nodejs" "valet" "laravel")
  local n=${#steps[@]} cur=0

  for step in "${steps[@]}"; do
    (( cur++ )) || true
    echo
    printf '%s%sProgress  (%d/%d)%s\n' "$(_P)" "$DGY" "$cur" "$n" "$R"
    global_progress "$cur" "$n" "$step"
    echo

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

  echo
  global_progress "$n" "$n" "complete"
  echo

  configure_shell
  show_summary
}

main "$@"
