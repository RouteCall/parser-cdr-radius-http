#!/bin/sh

# line for run like a daemon
# RADACCT_DIR='/var/log/radacct/temp/' STORAGE_DIR='/var/log/radacct/detail/' /usr/sbin/daemon -P /var/run/parser-cdr-radius-http.run -r -f /usr/local/bin/safe-parser-cdr-radius-http.sh

# bins
DIRNAME="$(/usr/bin/which dirname)"
DIRNAME="${DIRNAME:-/usr/bin/dirname}"
PGREP="$(/usr/bin/which pgrep)"
PGREP="${PGREP:-/bin/pgrep}"
PKILL="$(/usr/bin/which pkill)"
PKILL="${PKILL:-/bin/pkill}"
SLEEP="$(/usr/bin/which sleep)"
SLEEP="${SLEEP:-/bin/sleep}"

# global variables
BASEDIR="$(${DIRNAME} $0)"
SCRIPTNAME="parser-cdr-radius-http.sh"
NULL='/dev/null'
SLEEP_MON=1

"${BASEDIR}"/"${SCRIPTNAME}" -h > "${NULL}" || exit 1

_run_parser() {
  "${BASEDIR}"/"${SCRIPTNAME}" &
}

_monitor() {
  while true; do
    ${SLEEP} ${SLEEP_MON}
    if ${PGREP} -fq "${SCRIPTNAME}"; then
      continue
    fi
    _run_parser
  done
}

# Don't die if stdout/stderr can't be written to
trap '' PIPE

if ${PGREP} -fq "${SCRIPTNAME}" && ${PGREP} -fq "safe-${SCRIPTNAME}"; then
  exit 0
fi

if ${PGREP} -fq "safe-${SCRIPTNAME}"; then
  ${PKILL} -f "safe-${SCRIPTNAME}" || exit 1
fi

_monitor

exit $?

