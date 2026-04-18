#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  Ubuntu Dev Stack Installer  v3.0
#  PHP 8.4 · MariaDB · Node.js · Composer · Valet · Laravel
#  Ubuntu 24.04 LTS  |  WSL compatible  |  bash 4.0+
# ════════════════════════════════════════════════════════════════

# ── Bash guard ───────────────────────────────────────────────────
if [ -z "${BASH_VERSION:-}" ]; then
  echo "ERROR: run with bash, not sh.  Try:  bash $0"; exit 1
fi
_bv="${BASH_VERSINFO[0]:-0}"
if [ "$_bv" -lt 4 ]; then
  echo "ERROR: bash 4+ required (found bash $_bv)"; exit 1
fi

set -e
set -u
(set -o pipefail 2>/dev/null) && set -o pipefail

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export DEBIAN_FRONTEND=noninteractive

# ── Palette ──────────────────────────────────────────────────────
R=$'\033[0m'         ; BD=$'\033[1m'       ; DM=$'\033[2m'
IT=$'\033[3m'
K0=$'\033[38;5;234m' ; K1=$'\033[38;5;238m'; K2=$'\033[38;5;242m'
K3=$'\033[38;5;246m' ; K4=$'\033[38;5;250m'; K5=$'\033[38;5;255m'
CYAN=$'\033[38;5;51m'; TCYN=$'\033[38;5;45m'
GRN=$'\033[38;5;84m' ; TGRN=$'\033[38;5;48m'
YLW=$'\033[38;5;227m'; GOLD=$'\033[38;5;220m'
RED=$'\033[38;5;203m'

# ── State ────────────────────────────────────────────────────────
LOG_FILE="/tmp/dev-stack-$(date +%s).log"
NODE_VERSION="22"
declare -A PKG_STATUS=()
declare -A PKG_VER=()
declare -A ALREADY=()
INSTALL_ERRORS=()
START_TIME=$SECONDS
SUDO_PASS=""

PKGS=(system php mariadb composer nodejs valet laravel)

declare -A PKG_LABEL=(
  [system]="System Update"
  [php]="PHP 8.4"
  [mariadb]="MariaDB"
  [composer]="Composer"
  [nodejs]="Node.js"
  [valet]="Laravel Valet"
  [laravel]="Laravel CLI"
)

# ── WSL detection ────────────────────────────────────────────────
IS_WSL=0
grep -qi microsoft /proc/version 2>/dev/null && IS_WSL=1
grep -qi wsl       /proc/version 2>/dev/null && IS_WSL=1

# ── Terminal helpers ─────────────────────────────────────────────
TW()       { tput cols  2>/dev/null || echo 80; }
TH()       { tput lines 2>/dev/null || echo 24; }
cls()      { printf '\033[2J\033[H'; }
cur_hide() { printf '\033[?25l'; }
cur_show() { printf '\033[?25h'; }
cur_pos()  { printf '\033[%d;%dH' "$1" "$2"; }
erase_eol(){ printf '\033[K'; }

trap 'cur_show; printf "\033[?25h"; tput sgr0 2>/dev/null || true; echo' EXIT INT TERM

rep() {
  local c="$1" n="$2" s="" i
  for (( i=0; i<n; i++ )); do s+="$c"; done
  printf '%s' "$s"
}

strip_ansi() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*[mK]//g'; }

center() {
  local text="$1" vl="$2" w="${3:-$(TW)}"
  local pad=$(( (w - vl) / 2 ))
  [ $pad -lt 0 ] && pad=0
  printf '%*s%s\n' "$pad" '' "$text"
}

# ── Service helpers ───────────────────────────────────────────────
svc_start() {
  local s="$1"
  if [ "$IS_WSL" -eq 1 ] || ! systemctl is-system-running --quiet 2>/dev/null; then
    sudo service "$s" start   >> "$LOG_FILE" 2>&1 || true
  else
    sudo systemctl start "$s" >> "$LOG_FILE" 2>&1 || true
  fi
}
svc_enable() {
  local s="$1"
  if [ "$IS_WSL" -eq 1 ] || ! systemctl is-system-running --quiet 2>/dev/null; then
    sudo service "$s" start        >> "$LOG_FILE" 2>&1 || true
  else
    sudo systemctl enable --now "$s" >> "$LOG_FILE" 2>&1 || true
  fi
}
svc_active() {
  local s="$1"
  if [ "$IS_WSL" -eq 1 ] || ! systemctl is-system-running --quiet 2>/dev/null; then
    sudo service "$s" status >> "$LOG_FILE" 2>&1
  else
    systemctl is-active --quiet "$s"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  DASHBOARD LAYOUT
# ══════════════════════════════════════════════════════════════════
DASH_PKG_ROW=7
DASH_BAR_ROW=17
DASH_MSG_ROW=18
DASH_LOG_ROW=20
LOG_LINES=5
declare -a LOG_RING=()

_st_icon() {
  case "$1" in
    ok)      printf '%s●%s' "$TGRN$BD" "$R" ;;
    skip)    printf '%s◌%s' "$K2$BD"   "$R" ;;
    fail)    printf '%s✘%s' "$RED$BD"  "$R" ;;
    running) printf '%s◆%s' "$GOLD$BD" "$R" ;;
    *)       printf '%s○%s' "$K1"      "$R" ;;
  esac
}

_st_label() {
  local p="$1" st="${PKG_STATUS[$1]:-pending}" ver="${PKG_VER[$1]:-}"
  case "$st" in
    ok)      [ -n "$ver" ] && printf '%s%s%s' "$TGRN" "$ver" "$R" \
                           || printf '%s%s%s' "$TGRN" "installed" "$R" ;;
    skip)    [ -n "$ver" ] && printf '%s%s  (skip)%s' "$K2" "$ver" "$R" \
                           || printf '%sskipped%s' "$K2" "$R" ;;
    fail)    printf '%sfailed%s' "$RED" "$R" ;;
    running) printf '%sinstalling...%s' "$GOLD" "$R" ;;
    *)       printf '%spending%s' "$K1" "$R" ;;
  esac
}

dash_recalc_rows() {
  DASH_BAR_ROW=$(( DASH_PKG_ROW + ${#PKGS[@]} + 3 ))
  DASH_MSG_ROW=$(( DASH_BAR_ROW + 1 ))
  DASH_LOG_ROW=$(( DASH_MSG_ROW + 3 ))
  local h; h=$(TH)
  local avail=$(( h - DASH_LOG_ROW - 4 ))
  [ $avail -lt 3 ] && avail=3
  [ $avail -gt 8 ] && avail=8
  LOG_LINES=$avail
}

dash_draw_chrome() {
  local w; w=$(TW)
  cls; cur_hide
  dash_recalc_rows

  # ── Title bar ──
  cur_pos 1 1
  printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos 2 1
  local wsl_tag=""
  [ "$IS_WSL" -eq 1 ] && wsl_tag="  ${DM}${K2}WSL${R}"
  printf '  %s%sDev Stack Installer%s  %s%sv3.0%s%s' \
    "$BD$K5" "" "$R" "$DM$K2" "" "$R" "$wsl_tag"
  cur_pos 3 1
  printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"

  # ── Packages section ──
  cur_pos 5 1
  printf '  %s%sPACKAGES%s' "$DM$K2" "" "$R"
  cur_pos 6 1
  printf '  %s  %-20s  %s%s' "$K1$DM" "name" "status" "$R"

  local i=0 p
  for p in "${PKGS[@]}"; do
    cur_pos $(( DASH_PKG_ROW + i )) 1
    printf '  %s  %s%-20s%s  %s' \
      "$(_st_icon pending)" "$K2" "${PKG_LABEL[$p]}" "$R" "${K1}—${R}"
    erase_eol
    i=$(( i + 1 ))
  done

  # ── Progress section ──
  cur_pos $(( DASH_PKG_ROW + ${#PKGS[@]} + 1 )) 1
  printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos $(( DASH_PKG_ROW + ${#PKGS[@]} + 2 )) 1
  printf '  %s%sPROGRESS%s' "$DM$K2" "" "$R"

  # ── Log section ──
  cur_pos $(( DASH_LOG_ROW - 1 )) 1
  printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos $(( DASH_LOG_ROW )) 1
  printf '  %s%sLOG%s' "$DM$K2" "" "$R"

  # ── Bottom ──
  cur_pos $(( DASH_LOG_ROW + LOG_LINES + 1 )) 1
  printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos $(( DASH_LOG_ROW + LOG_LINES + 2 )) 1
  printf '  %s%s%s' "$DM$K1" "$LOG_FILE" "$R"
}

dash_draw_pkgs() {
  local i=0 p
  for p in "${PKGS[@]}"; do
    cur_pos $(( DASH_PKG_ROW + i )) 1
    printf '  %s  %s%-20s%s  %s' \
      "$(_st_icon "${PKG_STATUS[$p]:-pending}")" \
      "$K4$BD" "${PKG_LABEL[$p]}" "$R" \
      "$(_st_label "$p")"
    erase_eol
    i=$(( i + 1 ))
  done
}

dash_draw_bar() {
  local done_n="$1" total="$2"
  local w; w=$(TW)
  local bar_w=$(( w - 12 ))
  [ $bar_w -lt 10 ] && bar_w=10
  local filled=$(( done_n * bar_w / total ))
  local empty=$(( bar_w - filled ))
  local pct=$(( done_n * 100 / total ))

  cur_pos "$DASH_BAR_ROW" 1
  printf '  %s[%s' "$K1" "$R"
  if [ $filled -gt 0 ]; then
    local h1=$(( filled / 2 )); [ $h1 -lt 1 ] && h1=1
    local h2=$(( filled - h1 ))
    printf '%s%s%s' "$TCYN$BD" "$(rep '█' "$h1")" "$R"
    [ $h2 -gt 0 ] && printf '%s%s%s' "$TGRN$BD" "$(rep '█' "$h2")" "$R"
  fi
  [ $empty -gt 0 ] && printf '%s%s%s' "$K0" "$(rep '░' "$empty")" "$R"
  printf '%s]%s' "$K1" "$R"
  if [ $pct -eq 100 ]; then
    printf '  %s✔ 100%%%s' "$TGRN$BD" "$R"
  else
    printf '  %s%3d%%%s' "$GOLD$BD" "$pct" "$R"
  fi
  erase_eol
}

dash_draw_msg() {
  cur_pos "$DASH_MSG_ROW" 1
  printf '  %s›%s %s%s%s' "$TCYN" "$R" "$K3" "$1" "$R"
  erase_eol
}

dash_log() {
  local line="$1"
  LOG_RING+=("$line")
  local maxbuf=$(( LOG_LINES * 3 ))
  while [ ${#LOG_RING[@]} -gt $maxbuf ]; do
    LOG_RING=("${LOG_RING[@]:1}")
  done
  local total=${#LOG_RING[@]}
  local start=$(( total - LOG_LINES ))
  [ $start -lt 0 ] && start=0
  local i
  for (( i=0; i<LOG_LINES; i++ )); do
    cur_pos $(( DASH_LOG_ROW + 1 + i )) 1
    local idx=$(( start + i ))
    if [ $idx -lt $total ]; then
      printf '  %s' "${LOG_RING[$idx]}"
    else
      printf '  '
    fi
    erase_eol
  done
}

# ── Status setters ────────────────────────────────────────────────
pkg_running() { PKG_STATUS[$1]="running"; dash_draw_pkgs; dash_draw_msg "${2:-Installing ${PKG_LABEL[$1]}...}"; }
pkg_ok()      { PKG_STATUS[$1]="ok";      [ -n "${2:-}" ] && PKG_VER[$1]="$2"; dash_draw_pkgs; }
pkg_skip()    { PKG_STATUS[$1]="skip";    [ -n "${2:-}" ] && PKG_VER[$1]="$2"; dash_draw_pkgs; }
pkg_fail()    { PKG_STATUS[$1]="fail";    INSTALL_ERRORS+=("$1"); dash_draw_pkgs; }

# ── Log helpers ───────────────────────────────────────────────────
_log() {
  local ic="$1" cl="$2"; shift 2
  dash_log "${cl}${ic}${R}  ${K3}$*${R}"
  printf '[%s] %s\n' "$ic" "$*" >> "$LOG_FILE"
}
log_ok()   { _log "✔" "$TGRN$BD" "$@"; }
log_info() { _log "·" "$TCYN"    "$@"; }
log_warn() { _log "◆" "$GOLD"    "$@"; }
log_err()  { _log "✘" "$RED$BD"  "$@"; }
log_run()  { _log "›" "$K2$DM"   "$@"; }

# ── Spinner ───────────────────────────────────────────────────────
SPIN_PID=""
_SF=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

spinner_start() {
  local msg="$1"
  (
    local i=0
    while true; do
      cur_pos "$DASH_MSG_ROW" 1
      printf '  %s%s%s  %s%s%s' "$TCYN$BD" "${_SF[$((i%10))]}" "$R" "$K3" "$msg" "$R"
      erase_eol
      sleep 0.1
      i=$(( i + 1 ))
    done
  ) &
  SPIN_PID=$!
}

spinner_stop() {
  if [ -n "${SPIN_PID:-}" ]; then
    kill "$SPIN_PID" 2>/dev/null || true
    wait "$SPIN_PID" 2>/dev/null || true
    SPIN_PID=""
  fi
  cur_pos "$DASH_MSG_ROW" 1; erase_eol
}

# ══════════════════════════════════════════════════════════════════
#  SUDO
# ══════════════════════════════════════════════════════════════════
_prompt_row() { printf '%d' $(( DASH_LOG_ROW + LOG_LINES + 3 )); }

_read_pw() {
  local __v="$1" __p="${2:-Password: }" __s="" __c
  cur_show
  cur_pos "$(_prompt_row)" 1
  printf '%s%s%s' "$TGRN$BD" "$__p" "$R"
  erase_eol
  while IFS= read -r -s -n1 __c; do
    if [ -z "$__c" ] || [ "$__c" = $'\r' ]; then echo; break; fi
    if [ "$__c" = $'\177' ] || [ "$__c" = $'\010' ]; then
      [ -n "$__s" ] && { __s="${__s%?}"; printf '\b \b'; }
    else
      __s+="$__c"; printf '*'
    fi
  done
  cur_hide
  printf -v "$__v" '%s' "$__s"
}

sudo_warmup() {
  [ $EUID -eq 0 ] && return 0
  sudo -n true 2>/dev/null && return 0
  local pw="" user; user=$(whoami)
  while true; do
    _read_pw pw "${BD}[sudo]${R}${TGRN} password for ${BD}${user}${R}${TGRN}: "
    if printf '%s\n' "$pw" | sudo -S -v >> "$LOG_FILE" 2>&1; then
      SUDO_PASS="$pw"
      cur_pos "$(_prompt_row)" 1; erase_eol
      log_ok "sudo authenticated"
      return 0
    else
      cur_pos "$(_prompt_row)" 1
      printf '  %swrong password — try again%s' "$RED" "$R"; erase_eol
      sleep 1
      cur_pos "$(_prompt_row)" 1; erase_eol
    fi
  done
}

_sudo() {
  local desc="$1"; shift
  log_run "$desc"
  spinner_start "$desc"
  local rc=0
  if sudo -n true 2>/dev/null; then
    sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  elif [ -n "$SUDO_PASS" ]; then
    printf '%s\n' "$SUDO_PASS" | sudo -S "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  else
    sudo "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  fi
  spinner_stop
  [ $rc -eq 0 ] && log_ok "$desc" || log_err "$desc (exit $rc)"
  return $rc
}

_run() {
  local desc="$1"; shift
  log_run "$desc"
  spinner_start "$desc"
  local rc=0
  "$@" >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop
  [ $rc -eq 0 ] && log_ok "$desc" || log_err "$desc (exit $rc)"
  return $rc
}

# ══════════════════════════════════════════════════════════════════
#  PROMPTS
# ══════════════════════════════════════════════════════════════════
prompt_yn() {
  local q="$1" default="${2:-y}" r
  cur_show
  cur_pos "$(_prompt_row)" 1
  local hint
  [ "$default" = "y" ] \
    && hint="${TGRN}Y${R}${K2}/n${R}" \
    || hint="${K2}y/${R}${TGRN}N${R}"
  printf '  %s%s%s  [%s]: ' "$K5$BD" "$q" "$R" "$hint"
  erase_eol
  read -r r
  r="${r:-$default}"
  cur_pos "$(_prompt_row)" 1; erase_eol; cur_hide
  [[ "$r" =~ ^[Yy] ]]
}

prompt_val() {
  local label="$1" def="$2" vname="$3" r
  cur_show
  cur_pos "$(_prompt_row)" 1
  printf '  %s%s%s  [%s%s%s]: ' "$K5$BD" "$label" "$R" "$GOLD" "$def" "$R"
  erase_eol
  read -r r
  cur_pos "$(_prompt_row)" 1; erase_eol; cur_hide
  printf -v "$vname" '%s' "${r:-$def}"
}

prompt_pw() {
  _read_pw "$1" "  ${K5}${BD}$2${R}${K4}: "
  cur_pos "$(_prompt_row)" 1; erase_eol
}

# ══════════════════════════════════════════════════════════════════
#  SPLASH
# ══════════════════════════════════════════════════════════════════
show_splash() {
  cls; cur_hide
  local w; w=$(TW); local h; h=$(TH)
  local r=$(( h/2 - 5 )); [ $r -lt 1 ] && r=1

  cur_pos $r 1;         printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos $(( r+2 )) 1; center "${BD}${K5}Dev Stack Installer${R}" 19 "$w"
  cur_pos $(( r+3 )) 1
  local sub="v3.0  ·  Ubuntu 24.04"
  [ "$IS_WSL" -eq 1 ] && sub+="  ·  WSL"
  center "${DM}${K3}${sub}${R}" ${#sub} "$w"
  cur_pos $(( r+5 )) 1; center "${K1}$(rep '·' 48)${R}" 48 "$w"
  cur_pos $(( r+6 )) 1; center "${K3}PHP 8.4  MariaDB  Node.js  Composer  Valet  Laravel${R}" 51 "$w"
  cur_pos $(( r+7 )) 1; center "${K1}$(rep '·' 48)${R}" 48 "$w"
  cur_pos $(( r+9 )) 1; center "${DM}${K2}$(date '+%Y-%m-%d  %H:%M')${R}" 16 "$w"
  cur_pos $(( r+11 )) 1; printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos $(( r+13 )) 1; cur_show
  local msg="  Press ENTER to begin, Ctrl+C to cancel  "
  printf '%*s%s%s%s' $(( (w-${#msg})/2 )) '' "$K2" "$msg" "$R"
  read -r _
  cur_hide
}

# ══════════════════════════════════════════════════════════════════
#  DETECT INSTALLED
# ══════════════════════════════════════════════════════════════════
detect_installed() {
  local p
  for p in php php8.4; do
    command -v "$p" &>/dev/null \
      && ALREADY[php]=$($p --version 2>/dev/null | head -1 | awk '{print $2}') && break
  done
  for p in mariadb mysql; do
    command -v "$p" &>/dev/null \
      && ALREADY[mariadb]=$($p --version 2>/dev/null | awk '{print $3,$4}' | tr -d ',') && break
  done
  command -v node     &>/dev/null && ALREADY[nodejs]=$(node --version 2>/dev/null)
  command -v composer &>/dev/null \
    && ALREADY[composer]=$(composer --version 2>/dev/null | head -1 | awk '{print $3}')

  local bin
  for bin in \
    "$(command -v valet 2>/dev/null || true)" \
    "$HOME/.config/composer/vendor/bin/valet" \
    "$HOME/.composer/vendor/bin/valet"; do
    [ -x "$bin" ] \
      && ALREADY[valet]=$("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "installed") \
      && break
  done
  for bin in \
    "$(command -v laravel 2>/dev/null || true)" \
    "$HOME/.config/composer/vendor/bin/laravel" \
    "$HOME/.composer/vendor/bin/laravel"; do
    [ -x "$bin" ] \
      && ALREADY[laravel]=$("$bin" --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "installed") \
      && break
  done
}

# ══════════════════════════════════════════════════════════════════
#  SYSTEM UPDATE
# ══════════════════════════════════════════════════════════════════
do_update() {
  pkg_running system "Updating apt cache..."
  _sudo "apt-get update" apt-get update -qq                          || { pkg_fail system; return 1; }
  dash_draw_msg "Upgrading system packages..."
  _sudo "apt-get upgrade" \
    env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold"                           || true
  dash_draw_msg "Installing base utilities..."
  _sudo "base utilities" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      curl wget gnupg2 software-properties-common \
      apt-transport-https ca-certificates lsb-release git unzip      || { pkg_fail system; return 1; }
  pkg_ok system "ready"
}

# ══════════════════════════════════════════════════════════════════
#  PHP 8.4
# ══════════════════════════════════════════════════════════════════
do_php() {
  pkg_running php "Adding ondrej/php PPA..."
  _sudo "add ondrej/php PPA" \
    env DEBIAN_FRONTEND=noninteractive add-apt-repository ppa:ondrej/php -y  || { pkg_fail php; return 1; }
  _sudo "apt-get update" apt-get update -qq
  dash_draw_msg "Installing PHP 8.4 + extensions..."
  _sudo "php8.4 packages" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      php8.4 php8.4-cli php8.4-common php8.4-curl php8.4-pgsql \
      php8.4-fpm php8.4-gd php8.4-imap php8.4-intl php8.4-mbstring \
      php8.4-mysql php8.4-opcache php8.4-soap php8.4-xml php8.4-zip \
      php8.4-bcmath php8.4-sqlite3                                   || { pkg_fail php; return 1; }
  svc_start php8.4-fpm; svc_enable php8.4-fpm; sleep 1
  svc_active php8.4-fpm 2>/dev/null && log_ok "php8.4-fpm running" || log_warn "php8.4-fpm may not be running"
  sudo update-alternatives --set php /usr/bin/php8.4 >> "$LOG_FILE" 2>&1 || true
  local ver; ver=$(php8.4 --version 2>/dev/null | head -1 | awk '{print $2}' || echo "8.4")
  pkg_ok php "$ver"
}

# ══════════════════════════════════════════════════════════════════
#  MARIADB
# ══════════════════════════════════════════════════════════════════
do_mariadb() {
  pkg_running mariadb "Installing MariaDB..."
  _sudo "mariadb-server" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      mariadb-server mariadb-client                                  || { pkg_fail mariadb; return 1; }
  svc_enable mariadb
  local ver; ver=$(mariadbd --version 2>/dev/null | awk '{print $3}' \
    || mysqld --version 2>/dev/null | awk '{print $3}' || echo "10.x")
  pkg_ok mariadb "$ver"
  _mariadb_secure
}

_mariadb_secure() {
  log_info "MariaDB secure setup..."
  local set_pw=false root_pass=""
  if prompt_yn "Set a root password for MariaDB?" "y"; then
    set_pw=true
    while true; do
      local p1="" p2=""
      prompt_pw p1 "New MariaDB root password"
      prompt_pw p2 "Confirm password"
      if [ "$p1" = "$p2" ] && [ -n "$p1" ]; then
        root_pass="$p1"; log_ok "Password confirmed"; break
      else
        log_warn "Passwords do not match — retry"
      fi
    done
  fi
  local rm_anon=true no_remote=true rm_test=true
  prompt_yn "Remove anonymous users?"     "y" || rm_anon=false
  prompt_yn "Disallow remote root login?" "y" || no_remote=false
  prompt_yn "Remove test database?"       "y" || rm_test=false
  local sql=""
  $set_pw    && sql+="ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}'; "
  $rm_anon   && sql+="DELETE FROM mysql.user WHERE User=''; "
  $no_remote && sql+="DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1'); "
  $rm_test   && sql+="DROP DATABASE IF EXISTS test; DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%'; "
  sql+="FLUSH PRIVILEGES;"
  spinner_start "Applying MariaDB security settings..."
  local rc=0
  sudo mariadb -e "$sql" >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop
  [ $rc -eq 0 ] && log_ok "MariaDB hardened" || log_warn "Some security steps failed — see log"
}

# ══════════════════════════════════════════════════════════════════
#  COMPOSER
# ══════════════════════════════════════════════════════════════════
do_composer() {
  pkg_running composer "Downloading Composer..."
  local tmp; tmp=$(mktemp -d); cd "$tmp"
  spinner_start "Downloading composer-setup.php..."
  local rc=0
  php -r "copy('https://getcomposer.org/installer','composer-setup.php');" >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop
  if [ $rc -ne 0 ]; then pkg_fail composer; cd - >/dev/null; rm -rf "$tmp"; return 1; fi
  spinner_start "Running setup..."
  rc=0; php composer-setup.php >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop
  if [ $rc -ne 0 ]; then pkg_fail composer; cd - >/dev/null; rm -rf "$tmp"; return 1; fi
  php -r "unlink('composer-setup.php');" 2>/dev/null || true
  _sudo "install composer binary" mv composer.phar /usr/local/bin/composer
  sudo chmod +x /usr/local/bin/composer 2>/dev/null || true
  cd - >/dev/null; rm -rf "$tmp"
  spinner_start "composer self-update..."
  composer self-update --no-interaction >> "$LOG_FILE" 2>&1 || true
  spinner_stop
  local ver; ver=$(composer --version 2>/dev/null | head -1 | awk '{print $3}' || echo "2.x")
  pkg_ok composer "$ver"
}

# ══════════════════════════════════════════════════════════════════
#  NODE.JS via NVM
# ══════════════════════════════════════════════════════════════════
do_nodejs() {
  pkg_running nodejs "Installing NVM..."
  _run "Download + run NVM installer" \
    bash -c 'curl -fsSo /tmp/_nvm.sh \
      https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh \
      && bash /tmp/_nvm.sh'                                          || { pkg_fail nodejs; return 1; }
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh" || true
  dash_draw_msg "Installing Node.js v${NODE_VERSION}..."
  _run "nvm install $NODE_VERSION" nvm install "$NODE_VERSION"      || { pkg_fail nodejs; return 1; }
  _run "nvm alias default"         nvm alias default "$NODE_VERSION" || true
  local nv; nv=$(node -v 2>/dev/null | tr -d 'v' || echo "?")
  pkg_ok nodejs "$nv"
}

# ══════════════════════════════════════════════════════════════════
#  VALET
# ══════════════════════════════════════════════════════════════════
_composer_bin() {
  local b
  b=$(composer global config bin-dir --absolute 2>/dev/null | tail -1 || true)
  if [ -z "$b" ] || [ ! -d "$b" ]; then
    if   [ -d "$HOME/.config/composer/vendor/bin" ]; then b="$HOME/.config/composer/vendor/bin"
    elif [ -d "$HOME/.composer/vendor/bin" ];         then b="$HOME/.composer/vendor/bin"
    else b="$HOME/.config/composer/vendor/bin"; fi
  fi
  printf '%s' "$b"
}

do_valet() {
  pkg_running valet "Installing Valet dependencies..."
  _sudo "valet apt deps" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      network-manager libnss3-tools jq xsel                          || { pkg_fail valet; return 1; }
  dash_draw_msg "composer global require cpriego/valet-linux..."
  _run "composer require valet-linux" \
    composer global require cpriego/valet-linux --no-interaction      || { pkg_fail valet; return 1; }
  local cbin; cbin=$(_composer_bin)
  [[ ":$PATH:" != *":$cbin:"* ]] && export PATH="$cbin:$PATH"
  if [ ! -x "$cbin/valet" ]; then
    log_err "valet binary not found at $cbin/valet"
    pkg_fail valet; return 1
  fi
  svc_start php8.4-fpm || true; sleep 1
  dash_draw_msg "Running valet install..."
  local rc=0
  spinner_start "valet install"
  "$cbin/valet" install >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop
  if [ $rc -ne 0 ]; then
    log_warn "Retrying valet install with sudo -E"
    rc=0
    sudo -E HOME="$HOME" USER="$USER" "$cbin/valet" install >> "$LOG_FILE" 2>&1 || rc=$?
  fi
  [ $rc -ne 0 ] && { log_err "valet install failed (exit $rc)"; pkg_fail valet; return 1; }
  sudo chown -R "$USER":"$USER" "$HOME/.valet"           >> "$LOG_FILE" 2>&1 || true
  sudo chmod -R u+rw "$HOME/.valet"                      >> "$LOG_FILE" 2>&1 || true
  sudo chown -R "$USER":"$USER" "$HOME/.config/composer" >> "$LOG_FILE" 2>&1 || true
  mkdir -p "$HOME/Sites"
  cd "$HOME/Sites"
  "$cbin/valet" park >> "$LOG_FILE" 2>&1 && log_ok "~/Sites parked → *.test" \
    || log_warn "valet park failed — run: cd ~/Sites && valet park"
  cd - >/dev/null
  local ver; ver=$("$cbin/valet" --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "installed")
  pkg_ok valet "$ver"
}

# ══════════════════════════════════════════════════════════════════
#  LARAVEL INSTALLER  (4-level fallback)
# ══════════════════════════════════════════════════════════════════
do_laravel() {
  pkg_running laravel "Preparing Laravel installer..."
  local cbin; cbin=$(_composer_bin)
  [[ ":$PATH:" != *":$cbin:"* ]] && export PATH="$cbin:$PATH"

  # Remove stale
  if composer global show laravel/installer &>/dev/null 2>&1; then
    spinner_start "Removing old laravel/installer..."
    composer global remove laravel/installer --no-interaction >> "$LOG_FILE" 2>&1 || true
    spinner_stop
  fi

  # Attempt 1 — normal
  local rc=0
  dash_draw_msg "composer global require laravel/installer..."
  spinner_start "composer global require laravel/installer"
  composer global require laravel/installer --no-interaction >> "$LOG_FILE" 2>&1 || rc=$?
  spinner_stop

  # Attempt 2 — with-all-dependencies
  if [ $rc -ne 0 ]; then
    log_warn "Conflict — retrying with --with-all-dependencies"
    rc=0
    spinner_start "retrying with --with-all-dependencies..."
    composer global require laravel/installer \
      --no-interaction --with-all-dependencies >> "$LOG_FILE" 2>&1 || rc=$?
    spinner_stop
  fi

  # Attempt 3 — isolated dir
  if [ $rc -ne 0 ]; then
    log_warn "Trying isolated install..."
    local idir="$HOME/.local/share/laravel-installer"
    rm -rf "$idir"; mkdir -p "$idir"
    cat > "$idir/composer.json" <<'CJSON'
{
    "require": { "laravel/installer": "*" },
    "config": { "allow-plugins": { "laravel/installer": true } }
}
CJSON
    rc=0
    spinner_start "isolated composer install..."
    composer install --no-interaction --working-dir="$idir" >> "$LOG_FILE" 2>&1 || rc=$?
    spinner_stop
    if [ $rc -eq 0 ]; then
      mkdir -p "$cbin"
      local src
      for src in "$idir/vendor/bin/laravel" "$idir/vendor/laravel/installer/bin/laravel"; do
        [ -f "$src" ] && { cp "$src" "$cbin/laravel"; chmod +x "$cbin/laravel"; break; }
      done
    fi
  fi

  # Attempt 4 — GitHub release phar
  if [ $rc -ne 0 ] || [ ! -x "$cbin/laravel" ]; then
    log_warn "Trying GitHub release download..."
    local url
    url=$(curl -fsSL "https://api.github.com/repos/laravel/installer/releases/latest" 2>/dev/null \
      | grep '"browser_download_url"' | grep '\.phar' | head -1 | cut -d'"' -f4 || true)
    if [ -n "$url" ]; then
      rc=0; mkdir -p "$cbin"
      spinner_start "Downloading laravel.phar..."
      curl -fsSL "$url" -o "$cbin/laravel" >> "$LOG_FILE" 2>&1 || rc=$?
      spinner_stop
      [ $rc -eq 0 ] && chmod +x "$cbin/laravel"
    else
      rc=1
    fi
  fi

  # Verify
  local lbin=""
  lbin=$(command -v laravel 2>/dev/null || true)
  [ -z "$lbin" ] && [ -x "$cbin/laravel" ] && lbin="$cbin/laravel"

  if [ -n "$lbin" ] && [ -x "$lbin" ]; then
    local ver; ver=$("$lbin" --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "installed")
    pkg_ok laravel "$ver"
  else
    log_err "Could not install laravel/installer"
    log_run "Manual fix:  composer global require laravel/installer --with-all-dependencies"
    pkg_fail laravel
  fi
}

# ══════════════════════════════════════════════════════════════════
#  SHELL CONFIG
# ══════════════════════════════════════════════════════════════════
configure_shell() {
  local cbin; cbin=$(_composer_bin)
  local nvm_block='export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ]          && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
  local f
  for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$f" ] || continue
    local fn; fn=$(basename "$f")
    if ! grep -q 'composer/vendor/bin' "$f" 2>/dev/null; then
      { echo; echo "# Composer PATH — dev-stack-installer"; echo "export PATH=\"${cbin}:\$PATH\""; } >> "$f"
      log_ok "Composer PATH → $fn"
    fi
    if ! grep -q 'NVM_DIR' "$f" 2>/dev/null; then
      { echo; echo "# NVM — dev-stack-installer"; printf '%s\n' "$nvm_block"; } >> "$f"
      log_ok "NVM config → $fn"
    fi
  done
}

# ══════════════════════════════════════════════════════════════════
#  POST-INSTALL FIXES
# ══════════════════════════════════════════════════════════════════
post_fix() {
  local d
  for d in "$HOME/.valet" "$HOME/.config/composer" "$HOME/.composer"; do
    [ -d "$d" ] || continue
    sudo chown -R "$USER":"$USER" "$d" >> "$LOG_FILE" 2>&1 || true
    sudo chmod -R u+rw "$d"           >> "$LOG_FILE" 2>&1 || true
  done
  svc_start php8.4-fpm || true; sleep 1
  local cbin; cbin=$(_composer_bin)
  [[ ":$PATH:" != *":$cbin:"* ]] && export PATH="$cbin:$PATH"
  if [ -x "$cbin/valet" ]; then
    "$cbin/valet" status >> "$LOG_FILE" 2>&1 \
      && log_ok "valet status OK" || log_warn "valet status issues — see log"
  fi
}

# ══════════════════════════════════════════════════════════════════
#  FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════
show_summary() {
  cls; cur_hide
  local w; w=$(TW)

  cur_pos 1 1; printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"
  cur_pos 2 1; center "${BD}${K5}Installation Complete${R}" 20 "$w"
  cur_pos 3 1; printf '%s%s%s' "$K0" "$(rep '─' "$w")" "$R"

  cur_pos 5 1
  printf '  %s%-20s  %-14s  %s%s\n' "$K2$DM" "Package" "Version" "Status" "$R"
  cur_pos 6 1
  printf '  %s%s%s\n' "$K1" "$(rep '·' $(( w - 4 )))" "$R"

  local row=7 p
  for p in "${PKGS[@]}"; do
    [ "$p" = "system" ] && continue
    local st="${PKG_STATUS[$p]:-pending}" ver="${PKG_VER[$p]:-—}"
    local icon st_txt
    case "$st" in
      ok)   icon="${TGRN}●${R}"; st_txt="${TGRN}installed${R}"  ;;
      skip) icon="${K2}◌${R}";   st_txt="${K2}skipped${R}"      ;;
      fail) icon="${RED}✘${R}";  st_txt="${RED}failed${R}"       ;;
      *)    icon="${K1}○${R}";   st_txt="${K2}—${R}"             ;;
    esac
    cur_pos $row 1
    printf '  %s  %s%-20s%s  %-14s  %s\n' \
      "$icon" "$K4$BD" "${PKG_LABEL[$p]}" "$R" "$ver" "$st_txt"
    row=$(( row + 1 ))
  done

  row=$(( row + 1 ))
  cur_pos $row 1; printf '  %s%s%s\n' "$K0" "$(rep '─' $(( w - 4 )))" "$R"

  if [ ${#INSTALL_ERRORS[@]} -gt 0 ]; then
    row=$(( row + 1 )); cur_pos $row 1
    printf '  %s%sFailed:%s' "$RED$BD" "" "$R"
    local e
    for e in "${INSTALL_ERRORS[@]}"; do
      row=$(( row + 1 )); cur_pos $row 1
      printf '    %s✘  %s%s' "$RED" "$e" "$R"
    done
    row=$(( row + 1 ))
  fi

  row=$(( row + 1 )); cur_pos $row 1
  printf '  %s%sNext steps%s\n' "$TCYN$BD" "" "$R"
  row=$(( row + 1 )); cur_pos $row 1
  printf '  %s1.%s  source ~/.zshrc  %s# reload shell%s\n' "$TCYN" "$K4" "$K1$DM" "$R"
  row=$(( row + 1 )); cur_pos $row 1
  printf '  %s2.%s  cd ~/Sites && laravel new myapp\n' "$TCYN" "$K4"
  row=$(( row + 1 )); cur_pos $row 1
  printf '  %s3.%s  open http://myapp.test\n' "$TCYN" "$K4"

  if [ "$IS_WSL" -eq 1 ]; then
    row=$(( row + 1 )); cur_pos $row 1
    printf '  %s⚠  WSL:%s  add service start commands to ~/.bashrc\n' "$GOLD$BD" "$K3"
    row=$(( row + 1 )); cur_pos $row 1
    printf '     %ssudo service php8.4-fpm start && sudo service nginx start && sudo service mariadb start%s\n' "$K2$DM" "$R"
  fi

  row=$(( row + 2 )); cur_pos $row 1
  printf '  %s%s%s\n' "$K0" "$(rep '─' "$w")" "$R"
  row=$(( row + 1 )); cur_pos $row 1
  local elapsed=$(( SECONDS - START_TIME ))
  printf '  %sFinished in %dm %ds  ·  log: %s%s\n' \
    "$DM$K2" "$(( elapsed/60 ))" "$(( elapsed%60 ))" "$LOG_FILE" "$R"
  row=$(( row + 2 )); cur_pos $row 1
  cur_show
}

# ══════════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════════
main() {
  [ ! -t 0 ] && { echo "ERROR: Run in an interactive terminal."; exit 1; }
  printf '[START] %s\n' "$(date)" > "$LOG_FILE"

  show_splash

  # Draw dashboard
  dash_recalc_rows
  dash_draw_chrome

  # Init all as pending
  local p
  for p in "${PKGS[@]}"; do PKG_STATUS[$p]="pending"; done

  # Scan existing
  dash_draw_msg "Scanning installed packages..."
  detect_installed
  for p in php mariadb nodejs composer valet laravel; do
    if [ -v "ALREADY[$p]" ]; then PKG_VER[$p]="${ALREADY[$p]}"; fi
  done
  dash_draw_pkgs

  # sudo auth
  sudo_warmup

  # Skip already-installed?
  if [ ${#ALREADY[@]} -gt 0 ]; then
    log_info "Found existing: ${!ALREADY[*]}"
    if prompt_yn "Skip already-installed packages?" "y"; then
      for p in "${!ALREADY[@]}"; do
        PKG_STATUS[$p]="skip"
        log_info "Skipping $p (${ALREADY[$p]})"
      done
      dash_draw_pkgs
    fi
  fi

  # Node version
  if [ "${PKG_STATUS[nodejs]:-pending}" != "skip" ]; then
    prompt_val "Node.js version to install" "$NODE_VERSION" NODE_VERSION
  fi

  # Confirm
  prompt_yn "Start installation now?" "y" || {
    cur_pos "$(_prompt_row)" 1; printf '  %sCancelled.%s\n' "$GOLD" "$R"; cur_show; exit 0
  }

  # ── Install loop ─────────────────────────────────────────────────
  local total=${#PKGS[@]} done_n=0
  for p in "${PKGS[@]}"; do
    dash_draw_bar "$done_n" "$total"
    if [ "${PKG_STATUS[$p]:-pending}" = "skip" ]; then
      done_n=$(( done_n + 1 ))
      dash_draw_bar "$done_n" "$total"
      continue
    fi
    case "$p" in
      system)   do_update   ;;
      php)      do_php      ;;
      mariadb)  do_mariadb  ;;
      composer) do_composer ;;
      nodejs)   do_nodejs   ;;
      valet)    do_valet    ;;
      laravel)  do_laravel  ;;
    esac
    done_n=$(( done_n + 1 ))
    dash_draw_bar "$done_n" "$total"
  done

  dash_draw_bar "$total" "$total"
  dash_draw_msg "Finalizing..."
  post_fix
  configure_shell
  dash_draw_msg "Done ✔"
  sleep 1

  show_summary
}

main "$@"
