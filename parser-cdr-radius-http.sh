#!/usr/bin/env bash

##
# Parser based on Digiuim Dictionary for Asterisk CDR RADIUS
# https://raw.githubusercontent.com/asterisk/asterisk/1fcc86d905236c340f30fa3a4ef62e63b9a9cb73/contrib/dictionary.digium > /usr/local/etc/radiusclient-ng/dictionary.digium
#
# Example of cdr asterisk in Radius format
#Acct-Status-Type = Stop
#Asterisk-Src = "2122195786"
#Asterisk-Dst = "99995591953149870"
#Asterisk-Dst-Ctx = "outbound-calls"
#Asterisk-Clid = "Foo" <2122195786>"
#Asterisk-Chan = "SIP/zwtelecom03-00088e65"
#Asterisk-Dst-Chan = "SIP/pkemp-00088e66"
#Asterisk-Last-App = "Dial"
#Asterisk-Last-Data = "SIP/5591953149870@pkemp,,rTt"
#Asterisk-Start-Time = "2018-09-01 20:51:19 -0300"
#Asterisk-Answer-Time = "2018-09-01 20:51:41 -0300"
#Asterisk-End-Time = "2018-09-01 20:53:49 -0300"
#Asterisk-Duration = 150
#Asterisk-Bill-Sec = 128
#Asterisk-Disposition = "ANSWERED"
#Asterisk-AMA-Flags = "DOCUMENTATION"
#Asterisk-Unique-ID = "1535845879.560741"
###

# bins
CURL="$(/usr/bin/which curl)"
CURL="${CURL:-/usr/local/bin/curl}"
GREP="$(/usr/bin/which grep)"
GREP="${GREP:-/usr/bin/grep}"
TR="$(/usr/bin/which tr)"
TR="${TR:-/usr/bin/tr}"
SED="$(/usr/bin/which sed)"
SED="${SED:-/usr/bin/sed}"
BASENAME="$(/usr/bin/which basename)"
BASENAME="${BASENAME:-/usr/bin/basename}"

# global variables
SCRIPTNAME="$(${BASENAME} "$0")"
LOG="/var/log/${SCRIPTNAME}.log"
NULL="/dev/null"
URL="https://api.routecall.io/cdr"
PATH='/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/root/bin'

# check of bins
${CURL} --version > ${NULL} || exit 1
${GREP} --version > ${NULL} || exit 1
[[ -f ${SED} ]] || exit 1

_help() {
  cat <<EOF
Usage:
  RADACCT_DIR='/var/log/radacct/detail_temp/' STORAGE_DIR='/storage/radacct/' $0 [APS]

APS: accts per second
RADACCT_DIR: directory that radius write accts
STORAGE_DIR: directory for storage permanent. if not set, the file of accounts will be deleted.
EOF
}
_err() {
  printf "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]: $@\n" | tee -a ${LOG}
}

_get_detail_file() {
  ls -1 -f ${RADACCT_DIR} | head -3 | tail -1
}

_storage_detail() {
  if [[ -f "$1" ]]; then
    f="${1}"
    mv -v ${f} ${STORAGE_DIR}
  else
    rm -v ${f}
  fi
}

_parser_file() {
  [[ -f ${RADACCT_DIR}/"$1" ]] && f="${RADACCT_DIR}/$1" || exit 1
  eval $( \
    cat ${f} | 
      ${GREP} -E 'Asterisk-|NAS-Token' | 
      ${SED} -e 's,[[:space:]]=[[:space:]],=,g' | 
      ${SED} -r 's/(Asterisk|NAS)-([A-Z]+[a-z]+|[A-Z]+)(-)?([A-Z]+[a-z]+)?/\1_\2_\4/g' | 
      ${SED} 's/_=/=/g'
  )

  # https://docs.routecall.io/billing_http_asterisk.html
  echo "
  {
            \"access_token\": \"${NAS_Token}\",
            \"cdr\":
            {
                \"accountcode\": \"${Asterisk_Acc_Code}\",
                \"src\": \"${Asterisk_Src}\",
                \"dst\": \"${Asterisk_Dst}\",
                \"dcontext\": \"${Asterisk_Dst_Ctx}\",
                \"clid\": \"${Asterisk_Clid}\",
                \"channel\": \"${Asterisk_Chan}\",
                \"dstchannel\": \"${Asterisk_Dst_Chan}\",
                \"lastapp\": \"${Asterisk_Last_App}\",
                \"lastdata\": \"${Asterisk_Last_Data}\",
                \"start\": \"${Asterisk_Start_Time}\",
                \"answer\": \"${Asterisk_Answer_Time}\",
                \"end\": \"${Asterisk_End_Time}\",
                \"duration\": \"${Asterisk_Duration}\",
                \"billsec\": \"${Asterisk_Bill_Sec}\",
                \"disposition\": \"${Asterisk_Disposition}\",
                \"amaflags\": \"${Asterisk_AMA_Flags}\",
                \"uniqueid\": \"${Asterisk_Unique_ID}\"
            }
        }
  "
}

_send_acct_to_http() {
  detail_file="$(_get_detail_file)"
  json_string=$(_parser_file ${detail_file}) || exit 1
  # when http response is "200 OK": {"job_id":"4e4d7829-bc73-4d87-8590-a0155acd83e5"}
  response="$(${CURL} -X POST -H "Content-Type: application/json" -d "${json_string}" "${URL}" 2> ${NULL})" 
  echo "'${response}'" | 
    ${GREP} -E '\{"job_id":"([[:alnum:]]+-?)+"\}'

  if [[ $? -eq 0 ]]; then
    _storage_detail "${RADACCT_DIR}/${detail_file}"
  else
    _err "HTTP response: ${response}"
    exit 1
  fi
}

try_spawn_threads_per_second() {
  [[ $1 =~ ^[0-9]+$ ]] && requests_per_second=$1 || exit 1

  # sleep for get ${requests_per_second}
  sleep_in_seconds="$(printf "%.6f" $(echo "scale=6; 1/${requests_per_second}" | bc))"

  # infinite loop
  while true; do
    echo '' > "${LOG}" 2>&1 &
    echo '' > "${LOG}" 2>&1 &
    # sub-shell in background
    ( time _send_acct_to_http ) > "${LOG}" 2>&1 &
    echo '' > "${LOG}" 2>&1 &
    wait
  done
}

_main() {
  # infinite loop
  while true; do
    try_spawn_threads_per_second "$1"
  done
}


# if argument is int value and if environment variables is a directory, then exec the main function
if [[ $1 =~ ^[0-9]+$ ]] && [[ -d "${RADACCT_DIR}" ]]; then
  RADACCT_DIR=${RADACCT_DIR%/}
  _main "$1"
  exit $?
elif [[ "$1" == "-h" ]]; then
  _help
  exit 0
else
  _help
  exit 1
fi

