#!/usr/bin/env bash
### Created by Peter Forret ( pforret ) on 2021-07-07
### Based on https://github.com/pforret/bashew 1.16.5
script_version="0.0.1" # if there is a VERSION.md in this script's folder, it will take priority for version number
readonly script_author="peter@forret.com"
readonly script_created="2021-07-07"
readonly run_as_root=-1 # run_as_root: 0 = don't check anything / 1 = script MUST run as root / -1 = script MAY NOT run as root

list_options() {
  echo -n "
#commented lines will be filtered
flag|h|help|show usage
flag|q|quiet|no output
flag|v|verbose|output more
flag|f|force|do not ask for confirmation (always yes)
flag|f|force|do not ask for confirmation (always yes)
flag|Q|qrcode|add QR encode of URL to image
option|l|log_dir|folder for log files |$HOME/log/$script_prefix
option|o|out_dir|output folder for the m4a/mp3 files (default: derive from URL)|
option|t|tmp_dir|folder for temp files|.tmp
option|A|AUDIO|audio format to use|m4a
option|C|COMMENT|comment metadata for audio file|%c %a
option|D|DAYS|maximum days to go back|365
option|F|FONT|font to use for subtitle|Helvetica
option|G|FONTSIZE|font size|32
option|I|FILTER|only download matching mixes|/
option|N|NUMBER|maximum downloads from this playlist|10
option|P|PIXELS|resolution image (width/height in pixels)|500
option|S|SUBTITLE|subtitle for the image|%u @ %y
option|T|TITLE|title metadata for audio file|%d: %t (%mmin)
param|1|action|action to perform: download/update/check
param|?|url|Mixcloud URL of a user or a playlist
" | grep -v '^#' | grep -v '^\s*$'
}

#####################################################################
## Put your main script here
#####################################################################

main() {
  log_to_file "[$script_basename] $script_version started"

  # shellcheck disable=SC2154
  action=$(lower_case "$action")
  case $action in
  download)
    #TIP: use «$script_prefix download URL» to download all audio files
    #TIP:> $script_prefix download https://www.mixcloud.com/DjBlasto/playlists/discosauro/
    # shellcheck disable=SC2154
    do_download "$url"
    ;;

  check|env)
    ## leave this default action, it will make it easier to test your script
    #TIP: use «$script_prefix check» to check if this script is ready to execute and what values the options/flags are
    #TIP:> $script_prefix check
    #TIP: use «$script_prefix env» to generate an example .env file
    #TIP:> $script_prefix env > .env
    check_script_settings
    yt-dlp -U || echo "Run 'pip install --upgrade yt-dlp' to update yt-dlp"
    ;;

  install)
    #TIP: use «$script_prefix install» to install all required binaries
    #TIP:> $script_prefix install
    install_required_binaries
    ;;

  update)
    ## leave this default action, it will make it easier to test your script
    #TIP: use «$script_prefix update» to update to the latest version
    #TIP:> $script_prefix check
    update_script_to_latest
    ;;

  *)
    die "action [$action] not recognized"
    ;;
  esac
  log_to_file "[$script_basename] ended after $SECONDS secs"
  #TIP: >>> bash script created with «pforret/bashew»
  #TIP: >>> for bash development, also check out «pforret/setver» and «pforret/progressbar»
}

#####################################################################
## Put your helper scripts here
#####################################################################

function do_download(){
  log_to_file "download from mixcloud [$1]"
  require_binary AtomicParsley atomicparsley
  require_binary curl
  require_binary jq
  require_binary mogrify imagemagick
  require_binary python3
  require_binary yt-dlp "pip install --upgrade yt-dlp"
  announce "Download $NUMBER mixes from $1"

  local username uniq playlist not_before
  local input_url="$1"
  username=$(echo "$1" | cut -d/ -f4)
  playlist=$(basename "$1")
  uniq=$(echo "$1" | hash 8)

  [[ "$playlist" == "uploads" ]] && playlist=$username

  # shellcheck disable=SC2154
  local temp_json="$tmp_dir/$username.$uniq.$DAYS.json"
  debug "JSON cache: $temp_json"
  if [[ -f "$temp_json" ]] ; then
    # delete $temp_json if size is 0 bytes
    [[ ! -s "$temp_json" ]] && rm "$temp_json"
    # delete if it is too old
    # find "$tmp_dir" -mtime "+$DAYS" -name "$username.*.json" -delete
  fi
  if [[ ! -f "$temp_json" ]] ; then
    # shellcheck disable=SC2154
    not_before=$(calculate_not_before "$DAYS")
    debug "$os_kernel => only consider mixes after $not_before"
    debug "[$temp_json]: download JSON from $1"
    "yt-dlp" -j --dateafter "$not_before" "$1" > "$temp_json"
  fi

  debug "[$temp_json]: $(du -h "$temp_json" | awk '{print $1}')"
  # shellcheck disable=SC2154
  local download_log="$log_dir/download.$uniq.log"

  local mix_url mix_id mix_title mix_duration mix_date mix_file mix_uploader mix_thumb mix_count mix_artist mix_description mix_uniq mix_minutes
  mix_count=0
  # shellcheck disable=SC2154
  # shellcheck disable=SC2034
    jq -r '[.webpage_url, .id, .title , .duration, .upload_date, ._filename, .uploader_id, .thumbnail, .artist ] | join("\t")' "$temp_json" \
  | grep -i "$FILTER" \
  | while IFS=$'\t' read -r mix_url mix_id mix_title mix_duration mix_date mix_file mix_uploader mix_thumb mix_artist; do
      mix_count=$((mix_count + 1))
      [[ $mix_count -gt $NUMBER ]] && continue
      mix_uniq=$(echo "$mix_url" | hash 4)
      mix_minutes=$(( (mix_duration+30) / 60))
      mix_description="$( jq -r "select(.id==\"$mix_id\") | .description"  "$temp_json" | tr "\r\n\t" " " | sed 's/null//')"
      
      debug "> Mix: $mix_count: $mix_file"
      local pretty_date="${mix_date:0:4}-${mix_date:4:2}-${mix_date:6:2}"
      # shellcheck disable=SC2154
      [[ -z "$out_dir" ]] && out_dir="output/$username"
      [[ ! -d "$out_dir" ]] && mkdir -p "$out_dir"
      local mix_output="$out_dir/$mix_date.${mix_id:0:20}.$mix_uniq.$AUDIO"
      local mix_image="$tmp_dir/$mix_date.${mix_id:0:20}.$mix_uniq.jpg"

      local mix_temp
      if [[ ! -f "$mix_output" ]] ; then
        mix_temp="$tmp_dir/$(basename "$mix_output")"
        debug "> Download: $mix_temp -> $mix_output ..."
        "yt-dlp" --no-overwrites --no-progress --extract-audio --audio-format "$AUDIO" -o "$mix_temp" "$mix_url" >> "$download_log"
        mv "$mix_temp" "$mix_output"
      fi

      curl -s -o "$mix_image" "$mix_thumb"
      [[ ! -f "$mix_image" ]] && cp "$script_install_folder/assets/mixcloud.jpg" "$mix_image"
      debug "> Resize & noise: $mix_image"
      local image_dimensions="${PIXELS}x${PIXELS}"
      mogrify -resize "$image_dimensions" -brightness-contrast -30x10 -statistic median 3x3 -attenuate .5 +noise Gaussian "$mix_image"

      if [[ "$qrcode" -gt 0 ]] ; then
        require_binary "qrencode"
        local qr_orig="$tmp_dir/qr.$uniq.jpg"
        debug "> QR Code: $qr_orig"
        qrencode -o "$qr_orig" -m 2 -s 25 "$input_url"
        mogrify -resize "300x300" "$qr_orig"
        convert "$mix_image" "$qr_orig" -gravity Center -compose dissolve -define compose:args=50,100 -composite "$mix_image.temp.png"
        mv "$mix_image.temp.png" "$mix_image"
        # rm "$qr_orig"
      fi

      local new_sub
      if [[ -n "$SUBTITLE" ]] ; then
        new_sub=$(build_title "$SUBTITLE" "$mix_id" "$pretty_date" "$mix_title" "$mix_artist" "$mix_description" "$mix_minutes" "$username")
        debug "> Subtitle: '$new_sub'"
        mogrify -gravity south -pointsize "$FONTSIZE" -font "$FONT" -undercolor "#0008" -fill "#FFF" -annotate '0x0+0+5' "$new_sub" "$mix_image"
      fi

      local mix_comment
      mix_comment="$(build_title "$COMMENT" "$mix_id" "$pretty_date" "$mix_title" "$mix_artist" "$mix_description" "$mix_minutes" "$username")"
      mix_title="$(build_title "$TITLE" "$mix_id" "$pretty_date" "$mix_title" "$mix_artist" "$mix_description" "$mix_minutes" "$username")"
      debug "Audio title   : '$mix_title'"
      debug "Audio comment : '$mix_comment'"
      if [[ -f "$mix_image" ]] ; then
        debug "Annotate: $mix_output"
        AtomicParsley "$mix_output" \
          --overWrite \
          --artist "$username" \
          --album "$playlist" \
          --title "$mix_title" \
          --podcastURL "$mix_url" \
          --artwork "$mix_image" \
          --category "mixcloud" \
          --keyword "shmixcloud" \
          --description "$mix_comment" \
          --comment "$mix_comment" \
           &>> "$download_log"
      else
        debug "Add metadata on $mix_output"
        AtomicParsley "$mix_output" \
          --overWrite \
          --artist "$username" \
          --album "$playlist" \
          --title "$mix_title" \
          --podcastURL "$mix_url" \
          --category "mixcloud" \
          --keyword "shmixcloud" \
          --description "$mix_comment" \
          --comment "$mix_comment" \
           &>> "$download_log"
      fi
      [[ "$verbose" -eq 0 ]]  && rm "$mix_image"
      out "$mix_output"
      log_to_file "[$mix_output] downloaded and enriched"
    done
}

function build_title(){
  # pattern="$1"
  # mix_url mix_id mix_title mix_duration mix_date mix_file mix_uploader mix_thumb mix_artist mix_description
  echo "$1" \
  | awk \
      -v id="$2" \
      -v date="$3" \
      -v title="$4" \
      -v artist="$5" \
      -v description="$6" \
      -v minutes="$7" \
      -v user="$8" \
      '{
      year=substr(date,1,4);
      gsub(/%a/,artist);
      gsub(/%c/,description);
      gsub(/%d/,date);
      gsub(/%i/,id);
      gsub(/%m/,minutes);
      gsub(/%t/,title);
      gsub(/%u/,user);
      gsub(/%y/,year);
      print;
      }' \
  | cut -c1-256
}


function remove_duplicate_words(){
  awk '{
   split($0,arr," ");
   c=0;
   for (v in arr) c++;
   for (m=c;m >= 1;m--)
     for (n=1; n<m;n++)
        if (arr[m] == arr[n])
           delete arr[m];
   str="";
   for (k=1;k<=c;k++)
   {
      if (arr[k] != "")
          str=str""arr[k]" "
    }
    print substr(str,1,length(str)-1)
   }'
}

function calculate_not_before(){
  local DAYS="$1"
  if [[ $os_kernel == "Darwin" ]] ; then
    # /bin/date works differently for MacOS
    date -v "-${DAYS}d" '+%Y%m%d'
  else
    date -d "$DAYS days ago" '+%Y%m%d'
  fi
}

#####################################################################
################### DO NOT MODIFY BELOW THIS LINE ###################
#####################################################################

# set strict mode -  via http://redsymbol.net/articles/unofficial-bash-strict-mode/
# removed -e because it made basic [[ testing ]] difficult
set -uo pipefail
IFS=$'\n\t'
hash() {
  length=${1:-6}
  if [[ -n $(command -v md5sum) ]]; then
    # regular linux
    md5sum | cut -c1-"$length"
  else
    # macos
    md5 | cut -c1-"$length"
  fi
}

force=0
help=0
verbose=0
#to enable verbose even before option parsing
[[ $# -gt 0 ]] && [[ $1 == "-v" ]] && verbose=1
quiet=0
#to enable quiet even before option parsing
[[ $# -gt 0 ]] && [[ $1 == "-q" ]] && quiet=1

### stdout/stderr output
initialise_output() {
  [[ "${BASH_SOURCE[0]:-}" != "${0}" ]] && sourced=1 || sourced=0
  [[ -t 1 ]] && piped=0 || piped=1 # detect if output is piped
  if [[ $piped -eq 0 ]]; then
    col_reset="\033[0m"
    col_red="\033[1;31m"
    col_grn="\033[1;32m"
    col_ylw="\033[1;33m"
  else
    col_reset=""
    col_red=""
    col_grn=""
    col_ylw=""
  fi

  [[ $(echo -e '\xe2\x82\xac') == '€' ]] && unicode=1 || unicode=0 # detect if unicode is supported
  if [[ $unicode -gt 0 ]]; then
    char_succ="✅"
    char_fail="⛔"
    char_alrt="✴️"
    char_wait="⏳"
    info_icon="🌼"
    config_icon="🌱"
    clean_icon="🧽"
    require_icon="🔌"
  else
    char_succ="OK "
    char_fail="!! "
    char_alrt="?? "
    char_wait="..."
    info_icon="(i)"
    config_icon="[c]"
    clean_icon="[c]"
    require_icon="[r]"
  fi
  error_prefix="${col_red}>${col_reset}"
}

out() {     ((quiet)) && true || printf '%b\n' "$*"; }
debug() {   if ((verbose)); then out "${col_ylw}# $* ${col_reset}" >&2; else true; fi; }
die() {     out "${col_red}${char_fail} $script_basename${col_reset}: $*" >&2 ; tput bel ; safe_exit ; }
alert() {   out "${col_red}${char_alrt}${col_reset}: $*" >&2 ; }
success() { out "${col_grn}${char_succ}${col_reset}  $*"; }
announce() { out "${col_grn}${char_wait}${col_reset}  $*"; sleep 1 ; }
progress() {
  ((quiet)) || (
    local screen_width
    screen_width=$(tput cols 2>/dev/null || echo 80)
    local rest_of_line
    rest_of_line=$((screen_width - 5))

    if flag_set "${piped:-0}"; then
      out "$*" >&2
    else
      printf "... %-${rest_of_line}b\r" "$*                                             " >&2
    fi
  )
}

log_to_file() { [[ -n ${log_file:-} ]] && echo "$(date '+%H:%M:%S') | $*" >>"$log_file"; }

### string processing
lower_case() { echo "$*" | tr '[:upper:]' '[:lower:]'; }
upper_case() { echo "$*" | tr '[:lower:]' '[:upper:]'; }

slugify() {
    # slugify <input> <separator>
    # slugify "Jack, Jill & Clémence LTD"      => jack-jill-clemence-ltd
    # slugify "Jack, Jill & Clémence LTD" "_"  => jack_jill_clemence_ltd
    separator="${2:-}"
    [[ -z "$separator" ]] && separator="-"
    # shellcheck disable=SC2020
    echo "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr 'àáâäæãåāçćčèéêëēėęîïííīįìłñńôöòóœøōõßśšûüùúūÿžźż' 'aaaaaaaaccceeeeeeeiiiiiiilnnoooooooosssuuuuuyzzz' |
        awk '{
          gsub(/[\[\]@#$%^&*;,.:()<>!?\/+=_]/," ",$0);
          gsub(/^  */,"",$0);
          gsub(/  *$/,"",$0);
          gsub(/  */,"-",$0);
          gsub(/[^a-z0-9\-]/,"");
          print;
          }' |
        sed "s/-/$separator/g"
}

title_case() {
    # shellcheck disable=SC2020
    tr 'àáâäæãåāçćčèéêëēėęîïííīįìłñńôöòóœøōõßśšûüùúūÿžźż' 'aaaaaaaaccceeeeeeeiiiiiiilnnoooooooosssuuuuuyzzz' |
    awk '{
          for (i=1; i<=NF; ++i) { $i = toupper(substr($i,1,1)) tolower(substr($i,2)) };
          print $0;
          }'
}

### interactive
confirm() {
  # $1 = question
  flag_set $force && return 0
  read -r -p "$1 [y/N] " -n 1
  echo " "
  [[ $REPLY =~ ^[Yy]$ ]]
}

ask() {
  # $1 = variable name
  # $2 = question
  # $3 = default value
  # not using read -i because that doesn't work on MacOS
  local ANSWER
  read -r -p "$2 ($3) > " ANSWER
  if [[ -z "$ANSWER" ]]; then
    eval "$1=\"$3\""
  else
    eval "$1=\"$ANSWER\""
  fi
}

trap "die \"ERROR \$? after \$SECONDS seconds \n\
\${error_prefix} last command : '\$BASH_COMMAND' \" \
\$(< \$script_install_path awk -v lineno=\$LINENO \
'NR == lineno {print \"\${error_prefix} from line \" lineno \" : \" \$0}')" INT TERM EXIT
# cf https://askubuntu.com/questions/513932/what-is-the-bash-command-variable-good-for

safe_exit() {
  [[ -n "${tmp_file:-}" ]] && [[ -f "$tmp_file" ]] && rm "$tmp_file"
  trap - INT TERM EXIT
  debug "$script_basename finished after $SECONDS seconds"
  exit 0
}

flag_set() { [[ "$1" -gt 0 ]]; }

show_usage() {
  out "Program: ${col_grn}$script_basename $script_version${col_reset} by ${col_ylw}$script_author${col_reset}"
  out "Updated: ${col_grn}$script_modified${col_reset}"
  out "Description: Download Mixcloud shows to disk to be used in e.g. car"
  echo -n "Usage: $script_basename"
  list_options |
    awk '
  BEGIN { FS="|"; OFS=" "; oneline="" ; fulltext="Flags, options and parameters:"}
  $1 ~ /flag/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [flag] %s [default: off]",$2,$3,$4) ;
    oneline  = oneline " [-" $2 "]"
    }
  $1 ~ /option/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [option] %s",$2,$3 " <?>",$4) ;
    if($5!=""){fulltext = fulltext "  [default: " $5 "]"; }
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /list/  {
    fulltext = fulltext sprintf("\n    -%1s|--%-12s: [list] %s (array)",$2,$3 " <?>",$4) ;
    fulltext = fulltext "  [default empty]";
    oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /secret/  {
    fulltext = fulltext sprintf("\n    -%1s|--%s <%s>: [secret] %s",$2,$3,"?",$4) ;
      oneline  = oneline " [-" $2 " <" $3 ">]"
    }
  $1 ~ /param/ {
    if($2 == "1"){
          fulltext = fulltext sprintf("\n    %-17s: [parameter] %s","<"$3">",$4);
          oneline  = oneline " <" $3 ">"
     }
     if($2 == "?"){
          fulltext = fulltext sprintf("\n    %-17s: [parameter] %s (optional)","<"$3">",$4);
          oneline  = oneline " <" $3 "?>"
     }
     if($2 == "n"){
          fulltext = fulltext sprintf("\n    %-17s: [parameters] %s (1 or more)","<"$3">",$4);
          oneline  = oneline " <" $3 " …>"
     }
    }
    END {print oneline; print fulltext}
  '
}

check_last_version(){
  (
  # shellcheck disable=SC2164
  pushd "$script_install_folder" &> /dev/null
  if [[ -d .git ]] ; then
    local remote
    remote="$(git remote -v | grep fetch | awk 'NR == 1 {print $2}')"
    progress "Check for latest version - $remote"
    git remote update &> /dev/null
    if [[ $(git rev-list --count "HEAD...HEAD@{upstream}" 2>/dev/null) -gt 0 ]] ; then
      out "There is a more recent update of this script - run <<$script_prefix update>> to update"
    fi
  fi
  # shellcheck disable=SC2164
  popd &> /dev/null
  )
}

update_script_to_latest(){
  # run in background to avoid problems with modifying a running interpreted script
  (
  sleep 1
  cd "$script_install_folder" && git pull
  ) &
}

show_tips() {
  ((sourced)) && return 0
  # shellcheck disable=SC2016
  grep <"${BASH_SOURCE[0]}" -v '$0' \
  | awk \
      -v green="$col_grn" \
      -v yellow="$col_ylw" \
      -v reset="$col_reset" \
      '
      /TIP: /  {$1=""; gsub(/«/,green); gsub(/»/,reset); print "*" $0}
      /TIP:> / {$1=""; print " " yellow $0 reset}
      ' \
  | awk \
      -v script_basename="$script_basename" \
      -v script_prefix="$script_prefix" \
      '{
      gsub(/\$script_basename/,script_basename);
      gsub(/\$script_prefix/,script_prefix);
      print ;
      }'
}

check_script_settings() {
  if [[ -n $(filter_option_type flag) ]]; then
    out "## ${col_grn}boolean flags${col_reset}:"
    filter_option_type flag |
      while read -r name; do
        if ((piped)); then
          eval "echo \"$name=\$${name:-}\""
        else
          eval "echo -n \"$name=\$${name:-}  \""
        fi
      done
    out " "
    out " "
  fi

  if [[ -n $(filter_option_type option) ]]; then
    out "## ${col_grn}option defaults${col_reset}:"
    filter_option_type option |
      while read -r name; do
        if ((piped)); then
          eval "echo \"$name=\$${name:-}\""
        else
          eval "echo -n \"$name=\$${name:-}  \""
        fi
      done
    out " "
    out " "
  fi

  if [[ -n $(filter_option_type list) ]]; then
    out "## ${col_grn}list options${col_reset}:"
    filter_option_type list |
      while read -r name; do
        if ((piped)); then
          eval "echo \"$name=(\${${name}[@]})\""
        else
          eval "echo -n \"$name=(\${${name}[@]})  \""
        fi
      done
    out " "
    out " "
  fi

  if [[ -n $(filter_option_type param) ]]; then
    if ((piped)); then
      debug "Skip parameters for .env files"
    else
      out "## ${col_grn}parameters${col_reset}:"
      filter_option_type param |
        while read -r name; do
          # shellcheck disable=SC2015
          ((piped)) && eval "echo \"$name=\\\"\${$name:-}\\\"\"" || eval "echo -n \"$name=\\\"\${$name:-}\\\"  \""
        done
      echo " "
    fi
  fi
}

filter_option_type() {
  list_options | grep "$1|" | cut -d'|' -f3 | sort | grep -v '^\s*$'
}

init_options() {
  local init_command
  init_command=$(list_options |
    grep -v "verbose|" |
    awk '
    BEGIN { FS="|"; OFS=" ";}
    $1 ~ /flag/   && $5 == "" {print $3 "=0; "}
    $1 ~ /flag/   && $5 != "" {print $3 "=\"" $5 "\"; "}
    $1 ~ /option/ && $5 == "" {print $3 "=\"\"; "}
    $1 ~ /option/ && $5 != "" {print $3 "=\"" $5 "\"; "}
    $1 ~ /list/ {print $3 "=(); "}
    $1 ~ /secret/ {print $3 "=\"\"; "}
    ')
  if [[ -n "$init_command" ]]; then
    eval "$init_command"
  fi
}

expects_single_params() { list_options | grep 'param|1|' >/dev/null; }
expects_optional_params() { list_options | grep 'param|?|' >/dev/null; }
expects_multi_param() { list_options | grep 'param|n|' >/dev/null; }

parse_options() {
  if [[ $# -eq 0 ]]; then
    show_usage >&2
    safe_exit
  fi

  ## first process all the -x --xxxx flags and options
  while true; do
    # flag <flag> is saved as $flag = 0/1
    # option <option> is saved as $option
    if [[ $# -eq 0 ]]; then
      ## all parameters processed
      break
    fi
    if [[ ! $1 == -?* ]]; then
      ## all flags/options processed
      break
    fi
    local save_option
    save_option=$(list_options |
      awk -v opt="$1" '
        BEGIN { FS="|"; OFS=" ";}
        $1 ~ /flag/   &&  "-"$2 == opt {print $3"=1"}
        $1 ~ /flag/   && "--"$3 == opt {print $3"=1"}
        $1 ~ /option/ &&  "-"$2 == opt {print $3"=$2; shift"}
        $1 ~ /option/ && "--"$3 == opt {print $3"=$2; shift"}
        $1 ~ /list/ &&  "-"$2 == opt {print $3"+=($2); shift"}
        $1 ~ /list/ && "--"$3 == opt {print $3"=($2); shift"}
        $1 ~ /secret/ &&  "-"$2 == opt {print $3"=$2; shift #noshow"}
        $1 ~ /secret/ && "--"$3 == opt {print $3"=$2; shift #noshow"}
        ')
    if [[ -n "$save_option" ]]; then
      if echo "$save_option" | grep shift >>/dev/null; then
        local save_var
        save_var=$(echo "$save_option" | cut -d= -f1)
        debug "$config_icon parameter: ${save_var}=$2"
      else
        debug "$config_icon flag: $save_option"
      fi
      eval "$save_option"
    else
      die "cannot interpret option [$1]"
    fi
    shift
  done

  ((help)) && (
    show_usage
    check_last_version
    out "                                  "
    echo "### TIPS & EXAMPLES"
    show_tips

  ) && safe_exit

  ## then run through the given parameters
  if expects_single_params; then
    single_params=$(list_options | grep 'param|1|' | cut -d'|' -f3)
    list_singles=$(echo "$single_params" | xargs)
    single_count=$(echo "$single_params" | count_words)
    debug "$config_icon Expect : $single_count single parameter(s): $list_singles"
    [[ $# -eq 0 ]] && die "need the parameter(s) [$list_singles]"

    for param in $single_params; do
      [[ $# -eq 0 ]] && die "need parameter [$param]"
      [[ -z "$1" ]] && die "need parameter [$param]"
      debug "$config_icon Assign : $param=$1"
      eval "$param=\"$1\""
      shift
    done
  else
    debug "$config_icon No single params to process"
    single_params=""
    single_count=0
  fi

  if expects_optional_params; then
    optional_params=$(list_options | grep 'param|?|' | cut -d'|' -f3)
    optional_count=$(echo "$optional_params" | count_words)
    debug "$config_icon Expect : $optional_count optional parameter(s): $(echo "$optional_params" | xargs)"

    for param in $optional_params; do
      debug "$config_icon Assign : $param=${1:-}"
      eval "$param=\"${1:-}\""
      shift
    done
  else
    debug "$config_icon No optional params to process"
    optional_params=""
    optional_count=0
  fi

  if expects_multi_param; then
    #debug "Process: multi param"
    multi_count=$(list_options | grep -c 'param|n|')
    multi_param=$(list_options | grep 'param|n|' | cut -d'|' -f3)
    debug "$config_icon Expect : $multi_count multi parameter: $multi_param"
    ((multi_count > 1)) && die "cannot have >1 'multi' parameter: [$multi_param]"
    ((multi_count > 0)) && [[ $# -eq 0 ]] && die "need the (multi) parameter [$multi_param]"
    # save the rest of the params in the multi param
    if [[ -n "$*" ]]; then
      debug "$config_icon Assign : $multi_param=$*"
      eval "$multi_param=( $* )"
    fi
  else
    multi_count=0
    multi_param=""
    [[ $# -gt 0 ]] && die "cannot interpret extra parameters"
  fi
}

require_binary(){
  local binary path_binary install_instructions words
  binary="$1"
  path_binary=$(command -v "$binary" 2>/dev/null)
  [[ -n "$path_binary" ]] && debug "️$require_icon required [$binary] -> $path_binary" && return 0
  words=$(echo "${2:-}" | wc -w)
  if ((force)) ; then
    announce "Installing $1 ..."
    case $words in
      0)  eval "$install_package $1" ;;
          # require_binary ffmpeg -- binary and package have the same name
      1)  eval "$install_package $2" ;;
          # require_binary convert imagemagick -- binary and package have different names
      *)  eval "${2:-}"
          # require_binary primitive "go get -u github.com/fogleman/primitive" -- non-standard package manager
    esac
  else
    case $words in
      0)  install_instructions="$install_package ${1:-}" ;;
      1)  install_instructions="$install_package ${2:-}" ;;
      *)  install_instructions="${2:-}"
    esac
    alert "$script_basename needs [$binary] but it cannot be found"
    alert "1) install package  : $install_instructions"
    alert "2) check path       : export PATH=\"[path of your binary]:\$PATH\""
    die   "Missing program/script [$binary]"
  fi
}

folder_prep() {
  if [[ -n "$1" ]]; then
    local folder="$1"
    local max_days=${2:-365}
    if [[ ! -d "$folder" ]]; then
      debug "$clean_icon Create folder : [$folder]"
      mkdir -p "$folder"
    else
      debug "$clean_icon Cleanup folder: [$folder] - delete files older than $max_days day(s)"
      find "$folder" -mtime "+$max_days" -type f -exec rm {} \;
    fi
  fi
}

count_words() { wc -w | awk '{ gsub(/ /,""); print}'; }

recursive_readlink() {
  [[ ! -L "$1" ]] && echo "$1" && return 0
  local file_folder
  local link_folder
  local link_name
  file_folder="$(dirname "$1")"
  # resolve relative to absolute path
  [[ "$file_folder" != /* ]] && link_folder="$(cd -P "$file_folder" &>/dev/null && pwd)"
  local symlink
  symlink=$(readlink "$1")
  link_folder=$(dirname "$symlink")
  link_name=$(basename "$symlink")
  [[ -z "$link_folder" ]] && link_folder="$file_folder"
  [[ "$link_folder" == \.* ]] && link_folder="$(cd -P "$file_folder" && cd -P "$link_folder" &>/dev/null && pwd)"
  debug "$info_icon Symbolic ln: $1 -> [$symlink]"
  recursive_readlink "$link_folder/$link_name"
}

lookup_script_data() {
  # shellcheck disable=SC2155
  readonly script_prefix=$(basename "${BASH_SOURCE[0]}" .sh)
  # shellcheck disable=SC2155
  readonly script_basename=$(basename "${BASH_SOURCE[0]}")
  # shellcheck disable=SC2155
  readonly execution_day=$(date "+%Y-%m-%d")
  #readonly execution_year=$(date "+%Y")

  script_install_path="${BASH_SOURCE[0]}"
  debug "$info_icon Script path: $script_install_path"
  script_install_path=$(recursive_readlink "$script_install_path")
  debug "$info_icon Linked path: $script_install_path"
  # shellcheck disable=SC2155
  readonly script_install_folder="$( cd -P "$( dirname "$script_install_path" )" && pwd )"
  debug "$info_icon In folder  : $script_install_folder"
  if [[ -f "$script_install_path" ]]; then
    script_hash=$(hash <"$script_install_path" 8)
    script_lines=$(awk <"$script_install_path" 'END {print NR}')
  else
    # can happen when script is sourced by e.g. bash_unit
    script_hash="?"
    script_lines="?"
  fi

  # get shell/operating system/versions
  shell_brand="sh"
  shell_version="?"
  [[ -n "${ZSH_VERSION:-}" ]] && shell_brand="zsh" && shell_version="$ZSH_VERSION"
  [[ -n "${BASH_VERSION:-}" ]] && shell_brand="bash" && shell_version="$BASH_VERSION"
  [[ -n "${FISH_VERSION:-}" ]] && shell_brand="fish" && shell_version="$FISH_VERSION"
  [[ -n "${KSH_VERSION:-}" ]] && shell_brand="ksh" && shell_version="$KSH_VERSION"
  debug "$info_icon Shell type : $shell_brand - version $shell_version"

  # shellcheck disable=SC2155
  readonly os_kernel=$(uname -s)
  os_version=$(uname -r)
  os_machine=$(uname -m)
  install_package=""
  case "$os_kernel" in
  CYGWIN* | MSYS* | MINGW*)
    os_name="Windows"
    ;;
  Darwin)
    os_name=$(sw_vers -productName)       # macOS
    os_version=$(sw_vers -productVersion) # 11.1
    install_package="brew install"
    ;;
  Linux | GNU*)
    if [[ $(command -v lsb_release) ]]; then
      # 'normal' Linux distributions
      os_name=$(lsb_release -i    | awk -F: '{$1=""; gsub(/^[\s\t]+/,"",$2); gsub(/[\s\t]+$/,"",$2); print $2}' ) # Ubuntu/Raspbian
      os_version=$(lsb_release -r | awk -F: '{$1=""; gsub(/^[\s\t]+/,"",$2); gsub(/[\s\t]+$/,"",$2); print $2}' ) # 20.04
    else
      # Synology, QNAP,
      os_name="Linux"
    fi
    [[ -x /bin/apt-cyg ]] && install_package="apt-cyg install"     # Cygwin
    [[ -x /bin/dpkg ]] && install_package="dpkg -i"                # Synology
    [[ -x /opt/bin/ipkg ]] && install_package="ipkg install"       # Synology
    [[ -x /usr/sbin/pkg ]] && install_package="pkg install"        # BSD
    [[ -x /usr/bin/pacman ]] && install_package="pacman -S"        # Arch Linux
    [[ -x /usr/bin/zypper ]] && install_package="zypper install"   # Suse Linux
    [[ -x /usr/bin/emerge ]] && install_package="emerge"           # Gentoo
    [[ -x /usr/bin/yum ]] && install_package="yum install"         # RedHat RHEL/CentOS/Fedora
    [[ -x /usr/bin/apk ]] && install_package="apk add"             # Alpine
    [[ -x /usr/bin/apt-get ]] && install_package="apt-get install" # Debian
    [[ -x /usr/bin/apt ]] && install_package="apt install"         # Ubuntu
    ;;

  esac
  debug "$info_icon System OS  : $os_name ($os_kernel) $os_version on $os_machine"
  debug "$info_icon Package mgt: $install_package"

  # get last modified date of this script
  script_modified="??"
  [[ "$os_kernel" == "Linux" ]] && script_modified=$(stat -c %y "$script_install_path" 2>/dev/null | cut -c1-16) # generic linux
  [[ "$os_kernel" == "Darwin" ]] && script_modified=$(stat -f "%Sm" "$script_install_path" 2>/dev/null)          # for MacOS

  debug "$info_icon Last modif : $script_modified"
  debug "$info_icon Script ID  : $script_lines lines / md5: $script_hash"
  debug "$info_icon Creation   : $script_created"
  debug "$info_icon Running as : $USER@$HOSTNAME"

  # if run inside a git repo, detect for which remote repo it is
  if git status &>/dev/null; then
  # shellcheck disable=SC2155
    readonly git_repo_remote=$(git remote -v | awk '/(fetch)/ {print $2}')
    debug "$info_icon git remote : $git_repo_remote"
  # shellcheck disable=SC2155
    readonly git_repo_root=$(git rev-parse --show-toplevel)
    debug "$info_icon git folder : $git_repo_root"
  else
    readonly git_repo_root=""
    readonly git_repo_remote=""
  fi

  # get script version from VERSION.md file - which is automatically updated by pforret/setver
  [[ -f "$script_install_folder/VERSION.md" ]] && script_version=$(cat "$script_install_folder/VERSION.md")
  # get script version from git tag file - which is automatically updated by pforret/setver
  [[ -n "$git_repo_root" ]] && [[ -n "$(git tag &>/dev/null)" ]] && script_version=$(git tag --sort=version:refname | tail -1)
}

prep_log_and_temp_dir() {
  tmp_file=""
  log_file=""
  if [[ -n "${tmp_dir:-}" ]]; then
    folder_prep "$tmp_dir" 1
    # tmp_file=$(mktemp "$tmp_dir/$execution_day.XXXXXX")
    # debug "$config_icon tmp_file: $tmp_file"
    # you can use this temporary file in your program
    # it will be deleted automatically if the program ends without problems
  fi
  if [[ -n "${log_dir:-}" ]]; then
    folder_prep "$log_dir" 30
    log_file="$log_dir/$script_prefix.$execution_day.log"
    debug "$config_icon log_file: $log_file"
  fi
}

import_env_if_any() {
  env_files=("$script_install_folder/.env" "$script_install_folder/$script_prefix.env" "./.env" "./$script_prefix.env")

  for env_file in "${env_files[@]}"; do
    if [[ -f "$env_file" ]]; then
      debug "$config_icon Read  dotenv: [$env_file]"
      clean_file=$(clean_dotenv "$env_file")
      # shellcheck disable=SC1090
      source "$clean_file" && rm "$clean_file"
    fi
  done
}

clean_dotenv(){
  local input="$1"
  local output="$1.__.sh"
  [[ ! -f "$input" ]] && die "Input file [$input] does not exist"
  debug "$clean_icon Clean dotenv: [$output]"
  < "$input" awk '
      function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
      function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
      function trim(s) { return rtrim(ltrim(s)); }
      /=/ { # skip lines with no equation
        $0=trim($0);
        if(substr($0,1,1) != "#"){ # skip comments
          equal=index($0, "=");
          key=trim(substr($0,1,equal-1));
          val=trim(substr($0,equal+1));
          if(match(val,/^".*"$/) || match(val,/^\047.*\047$/)){
            print key "=" val
          } else {
            print key "=\"" val "\""
          }
        }
      }
  ' > "$output"
  echo "$output"
}

initialise_output  # output settings
lookup_script_data # find installation folder

[[ $run_as_root == 1  ]] && [[ $UID -ne 0 ]] && die "user is $USER, MUST be root to run [$script_basename]"
[[ $run_as_root == -1 ]] && [[ $UID -eq 0 ]] && die "user is $USER, CANNOT be root to run [$script_basename]"

init_options       # set default values for flags & options
import_env_if_any  # overwrite with .env if any

if [[ $sourced -eq 0 ]]; then
  parse_options "$@"    # overwrite with specified options if any
  prep_log_and_temp_dir # clean up debug and temp folder
  main                  # run main program
  safe_exit             # exit and clean up
else
  # just disable the trap, don't execute main
  trap - INT TERM EXIT
fi
