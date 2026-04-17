#!/bin/bash

# This is the main script that ties everything together. It runs the hardware  and software audit scripts, builds both reports, emails them as .txt file attachments, and copies them to a remote machine over SSH.
# Run it manually like this: './main_audit.sh' , for cron/automated use: './main_audit.sh --auto'
# The first time you run it on any machine it will ask you a few questions (email, remote machine IP, etc.) and save your answers to audit.conf.
# Every run after that — including cron — just loads that file silently.


# PATHS AND SETTINGS

# Figure out where this script is located so we can find the other scripts next to it, no matter where the project folder is on the machine.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The two audit sub-scripts that do the actual data collection. each one takes a file path as its first argument and writes its output there.
HW_AUDIT_SCRIPT="$SCRIPT_DIR/hardware_audit.sh"
SW_AUDIT_SCRIPT="$SCRIPT_DIR/os_and_software_audit.sh"

# Everything audit-related lives under /var/log/sys_audit.This folder needs to be created once with sudo before the first run.
AUDIT_DIR="/var/log/sys_audit"

# Reports go into a subfolder so they stay separate from the log files.
REPORT_DIR="$AUDIT_DIR/reports"

# The config file stores the user's settings after the first-run setup.
# It lives next to the scripts so the whole project folder stays self-contained.
CONFIG_FILE="$SCRIPT_DIR/audit.conf"

# Two log files: one for errors, one for tracking when the script ran.
ERROR_LOG="$AUDIT_DIR/error.log"
EXEC_LOG="$AUDIT_DIR/execution.log"

# Email subject line — same every time.
EMAIL_SUBJECT="System Audit Reports"

# If the script is called with --auto it means cron is running it,
# so we skip all prompts and use the saved defaults instead.
MODE="manual"
[[ "$1" == "--auto" ]] && MODE="auto"

# Capture the current date and time once at the start so all filenames
# and log entries for this run share the exact same timestamp.
RUN_TS="$(date '+%Y-%m-%d_%H-%M-%S')"
RUN_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

# These will be filled in once the reports are generated.
FULL_REPORT_PATH=""
SHORT_REPORT_PATH=""

# These will be filled in from audit.conf (or from the setup wizard).
DEFAULT_EMAIL=""
EMAIL_SENDER=""
REMOTE_USER=""
REMOTE_HOST=""
REMOTE_DIR=""


# HELPER FUNCTIONS

# Writes an error message with a timestamp to the error log.
log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$ERROR_LOG"
}

# Writes a regular message with a timestamp to the execution log.
# We use this to track every major step the script takes.
log_exec() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$EXEC_LOG"
}

# Prints a message to the terminal, but only in manual mode.
# In auto/cron mode the terminal doesn't exist, so we stay silent.
print_step() {
    [[ "$MODE" == "manual" ]] && echo "$1"
}

# DIRECTORY CHECK

# Before doing anything, make sure the audit directory exists and we can
# write to it. If it doesn't exist we tell the user exactly what to run.
# After that one-time setup, no sudo is ever needed again — safe for cron.
ensure_report_dir() {
    if [[ ! -d "$AUDIT_DIR" ]]; then
        echo ""
        echo "  [!] The audit directory doesn't exist yet: $AUDIT_DIR"
        echo "      Run these three commands once to create it, then try again:"
        echo ""
        echo "        sudo mkdir -p $AUDIT_DIR"
        echo "        sudo chown -R \$USER:\$USER $AUDIT_DIR"
        echo "        sudo chmod 755 $AUDIT_DIR"
        echo ""
        exit 1
    fi

    if [[ ! -w "$AUDIT_DIR" ]]; then
        echo ""
        echo "  [!] We don't have write permission on $AUDIT_DIR."
        echo "      Fix it with: sudo chown -R \$USER:\$USER $AUDIT_DIR"
        echo ""
        exit 1
    fi

    # Create the reports subfolder if it's not there yet. No sudo needed
    # because we already own the parent directory.
    mkdir -p "$REPORT_DIR" 2>/dev/null

    # Make sure the log files exist so we can safely append to them later.
    touch "$ERROR_LOG" "$EXEC_LOG" 2>/dev/null
}


# ---------------------------------------------------------------------------
# FIRST-RUN SETUP AND CONFIG LOADING
# ---------------------------------------------------------------------------

# This runs only once — the very first time the script is used on a machine.
# It asks for the settings we need and saves them to audit.conf so we never
# have to ask again.
collect_config() {
    echo ""
    echo "============================================================"
    echo "  FIRST-TIME SETUP"
    echo "  Your answers will be saved to: $CONFIG_FILE"
    echo "  You won't be asked these again on this machine."
    echo "============================================================"
    echo ""

    # Ask for the sender email and keep asking until we get something.
    echo -n "  Sender email address (the one sending the reports): "
    read -r input_sender
    while [[ -z "$input_sender" ]]; do
        echo -n "  Can't be empty — please enter the sender email: "
        read -r input_sender
    done

    # Ask for the default recipient — this is what cron will use.
    echo -n "  Default recipient email (used automatically in cron mode): "
    read -r input_default_email
    while [[ -z "$input_default_email" ]]; do
        echo -n "  Can't be empty — please enter the recipient email: "
        read -r input_default_email
    done

    # Ask for the remote machine's IP address.
    echo -n "  Remote machine IP address: "
    read -r input_remote_host
    while [[ -z "$input_remote_host" ]]; do
        echo -n "  Can't be empty — please enter the IP address: "
        read -r input_remote_host
    done

    # Ask for the SSH username on the remote machine.
    echo -n "  SSH username on the remote machine: "
    read -r input_remote_user
    while [[ -z "$input_remote_user" ]]; do
        echo -n "  Can't be empty — please enter the username: "
        read -r input_remote_user
    done

    # Build the remote directory path from the username.
    local input_remote_dir="/home/${input_remote_user}/audit_reports"

    # Write everything to audit.conf.
    cat > "$CONFIG_FILE" <<EOF
# audit.conf — created automatically by main_audit.sh on first run.
# If you need to change any of these, just delete this file and run
# the script again — it will ask you everything fresh.

EMAIL_SENDER="$input_sender"
DEFAULT_EMAIL="$input_default_email"
REMOTE_HOST="$input_remote_host"
REMOTE_USER="$input_remote_user"
REMOTE_DIR="$input_remote_dir"
EOF

    echo ""
    echo "  Settings saved to $CONFIG_FILE"
    echo "============================================================"
    echo ""
}

# Loads the saved settings from audit.conf into our variables.
# If the file doesn't exist yet, it calls collect_config first.
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        collect_config
    fi

    # Pull the values from the file into the current shell session.
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # Make sure every required value is actually there.
    local missing=0
    for var in EMAIL_SENDER DEFAULT_EMAIL REMOTE_HOST REMOTE_USER REMOTE_DIR; do
        if [[ -z "${!var}" ]]; then
            echo "  [!] Missing value in config: $var"
            missing=1
        fi
    done

    if [[ $missing -eq 1 ]]; then
        echo "  [!] The config file looks incomplete. Delete $CONFIG_FILE and run again."
        exit 1
    fi
}


# ---------------------------------------------------------------------------
# GENERATE FULL REPORT
# ---------------------------------------------------------------------------

# Runs both audit sub-scripts and combines their output into one formatted
# report file. The file is named with the current timestamp.
generate_full_report() {
    local full_report="$REPORT_DIR/full_report-${RUN_TS}.txt"

    print_step "Generating full report ..."
    log_exec "Starting full report generation."

    # Use temp files to collect output from each sub-script separately.
    local hw_tmp sw_tmp
    hw_tmp="$(mktemp /tmp/hw_audit_XXXXXX.tmp)"
    sw_tmp="$(mktemp /tmp/sw_audit_XXXXXX.tmp)"

    # Run the hardware audit. It writes everything to hw_tmp.
    if bash "$HW_AUDIT_SCRIPT" "$hw_tmp" 2>>"$ERROR_LOG"; then
        log_exec "Hardware audit finished successfully."
    else
        log_error "Hardware audit ran into a problem (exit code $?)."
        print_step "  [!] Hardware audit had some errors — check $ERROR_LOG."
    fi

    # Run the software audit. It writes everything to sw_tmp.
    if bash "$SW_AUDIT_SCRIPT" "$sw_tmp" 2>>"$ERROR_LOG"; then
        log_exec "Software audit finished successfully."
    else
        log_error "Software audit ran into a problem (exit code $?)."
        print_step "  [!] Software audit had some errors — check $ERROR_LOG."
    fi

    # Now build the full report by combining both outputs with nice formatting.
    {
        echo "============================================================"
        echo "              FULL SYSTEM AUDIT REPORT"
        echo "============================================================"
        echo "  Hostname   : $(hostname)"
        echo "  Date/Time  : $RUN_DATE"
        echo "  Saved at   : $full_report"
        echo "  Mode       : $MODE"
        echo "============================================================"
        echo ""

        echo "============================================================"
        echo "  SECTION 1 — HARDWARE AUDIT"
        echo "============================================================"
        if [[ -s "$hw_tmp" ]]; then
            cat "$hw_tmp"
        else
            echo "  [!] No hardware data was collected."
            log_error "Hardware audit output came back empty."
        fi
        echo ""

        echo "============================================================"
        echo "  SECTION 2 — SOFTWARE & OS AUDIT"
        echo "============================================================"
        if [[ -s "$sw_tmp" ]]; then
            cat "$sw_tmp"
        else
            echo "  [!] No software data was collected."
            log_error "Software audit output came back empty."
        fi
        echo ""

        echo "============================================================"
        echo "  END OF FULL REPORT"
        echo "  Generated on $(hostname) at $RUN_DATE"
        echo "============================================================"
    } > "$full_report"

    # Clean up the temp files now that we're done with them.
    rm -f "$hw_tmp" "$sw_tmp"

    log_exec "Full report saved: $full_report"
    FULL_REPORT_PATH="$full_report"
}


# ---------------------------------------------------------------------------
# GENERATE SHORT REPORT
# ---------------------------------------------------------------------------

# Builds a concise one-page summary using quick commands.
# This is what you'd glance at for a fast overview of the system.
generate_short_report() {
    local short_report="$REPORT_DIR/short_report-${RUN_TS}.txt"

    print_step "Generating short report ..."
    log_exec "Starting short report generation."

    # The short report depends on the full report having been created first.
    if [[ -z "$FULL_REPORT_PATH" || ! -f "$FULL_REPORT_PATH" ]]; then
        log_error "Can't generate short report — full report is missing."
        print_step "  [!] Short report skipped because the full report wasn't created."
        return 1
    fi

    {
        echo "============================================================"
        echo "         SHORT SYSTEM AUDIT REPORT (SUMMARY)"
        echo "============================================================"
        echo "  Hostname   : $(hostname)"
        echo "  Date/Time  : $RUN_DATE"
        echo "  Full report: $FULL_REPORT_PATH"
        echo "============================================================"
        echo ""

        echo "[ OS SUMMARY ]"
        echo "  OS      : $(grep '^PRETTY_NAME' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
        echo "  Kernel  : $(uname -r)"
        echo "  Arch    : $(uname -m)"
        echo "  Uptime  : $(uptime -p 2>/dev/null || uptime)"
        echo ""

        echo "[ HARDWARE SUMMARY ]"
        echo "  CPU     : $(lscpu 2>/dev/null | grep 'Model name' | sed 's/Model name\s*:\s*//' | xargs)"
        echo "  Cores   : $(nproc 2>/dev/null)"
        echo "  RAM     : $(free -h 2>/dev/null | awk '/^Mem:/{print "Total: "$2"  Free: "$4}')"
        echo "  Disks   :"
        df -h 2>/dev/null | grep -v tmpfs \
            | awk 'NR>1 {printf "    %-20s %5s used of %5s  (%s)\n", $6, $3, $2, $5}'
        echo ""

        echo "[ NETWORK SUMMARY ]"
        ip -br addr 2>/dev/null | awk '{printf "  %-12s %-10s %s\n", $1, $2, $3}'
        echo ""

        echo "[ TOP 5 PROCESSES BY CPU ]"
        ps aux --sort=-%cpu 2>/dev/null \
            | awk 'NR==1{printf "  %s\n",$0} NR>1 && NR<=6{printf "  %s\n",$0}'
        echo ""

        echo "[ LOGGED-IN USERS ]"
        who 2>/dev/null | awk '{printf "  %s\n", $0}'
        echo ""

        echo "[ LISTENING PORTS ]"
        ss -tuln 2>/dev/null | grep LISTEN | awk '{printf "  %s\n", $0}' | head -15
        echo ""

        echo "============================================================"
        echo "  END OF SHORT REPORT"
        echo "  For full details see: $FULL_REPORT_PATH"
        echo "============================================================"
    } > "$short_report"

    log_exec "Short report saved: $short_report"
    SHORT_REPORT_PATH="$short_report"
}


# ---------------------------------------------------------------------------
# SEND EMAIL
# ---------------------------------------------------------------------------

# Sends both report files as .txt attachments to the recipient.
# In manual mode it asks who to send to (with the saved default as an option).
# In auto/cron mode it just uses the saved default and sends silently.
send_email() {
    local recipient

    if [[ "$MODE" == "auto" ]]; then
        recipient="$DEFAULT_EMAIL"
    else
        echo ""
        echo -n "  Enter recipient email or press Enter for default [$DEFAULT_EMAIL]: "
        read -r user_input
        if [[ -z "$user_input" ]]; then
            recipient="$DEFAULT_EMAIL"
        else
            recipient="$user_input"
        fi
    fi

    log_exec "Sending email to: $recipient"

    # We use mutt because it properly handles .txt file attachments.
    # The recipient will see a short message and two attached .txt files
    # they can open — the full report and the short report.
    if command -v mutt &>/dev/null; then
        echo "Please find attached the system audit reports for $(hostname) — generated on $RUN_DATE." \
            | mutt -s "$EMAIL_SUBJECT" \
                   -e "set from=$EMAIL_SENDER" \
                   -a "$FULL_REPORT_PATH" \
                   -a "$SHORT_REPORT_PATH" \
                   -- "$recipient" 2>>"$ERROR_LOG"

    # If mutt isn't available, use mailx with MIME attachment support.
    # This still sends the files as proper attachments, not inline text.
    elif command -v mailx &>/dev/null; then
        mailx -s "$EMAIL_SUBJECT" \
              -r "$EMAIL_SENDER" \
              -a "$FULL_REPORT_PATH" \
              -a "$SHORT_REPORT_PATH" \
              "$recipient" \
              <<< "Please find attached the system audit reports for $(hostname) — generated on $RUN_DATE." \
              2>>"$ERROR_LOG"

    else
        log_error "No mail client found. Tried mutt and mailx. Email not sent."
        print_step "  [!] No mail client available (need mutt or mailx). Email not sent."
        return 1
    fi

    if [[ $? -eq 0 ]]; then
        log_exec "Email sent successfully to: $recipient"
        print_step "  Email sent successfully to: $recipient"
    else
        log_error "Email failed for: $recipient"
        print_step "  [!] Email sending failed. Check $ERROR_LOG for details."
        return 1
    fi
}


# ---------------------------------------------------------------------------
# SEND TO REMOTE MACHINE
# ---------------------------------------------------------------------------

# Copies both report files to the remote machine over SSH.
# We check if the remote machine is online first — if it's off we just
# log it and move on instead of hanging.
# Key-based SSH is required (no password prompts — essential for cron).
send_to_remote() {
    print_step "  Sending reports to remote machine ($REMOTE_USER@$REMOTE_HOST) ..."
    log_exec "Attempting to transfer reports to: $REMOTE_HOST"

    # Send one ping to see if the remote machine is up before trying SSH.
    if ! ping -c 1 -W 3 "$REMOTE_HOST" &>/dev/null; then
        log_error "Remote machine $REMOTE_HOST didn't respond to ping. Skipping transfer."
        print_step "  [!] Remote machine ($REMOTE_HOST) is OFF or unreachable. Skipping remote transfer."
        return 1
    fi

    # Make sure the destination folder exists on the remote machine.
    # We use -p so it doesn't fail if it already exists.
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "${REMOTE_USER}@${REMOTE_HOST}" \
        "mkdir -p ${REMOTE_DIR}" 2>>"$ERROR_LOG"

    if [[ $? -ne 0 ]]; then
        log_error "Couldn't create remote directory $REMOTE_DIR on $REMOTE_HOST."
        print_step "  [!] Failed to create remote directory. Is SSH key-based auth set up?"
        return 1
    fi

    # Copy both report files over. BatchMode=yes ensures it never asks
    # for a password — if the key isn't set up it fails immediately.
    scp -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o BatchMode=yes \
        "$FULL_REPORT_PATH" "$SHORT_REPORT_PATH" \
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" 2>>"$ERROR_LOG"

    if [[ $? -eq 0 ]]; then
        log_exec "Reports transferred to ${REMOTE_HOST}:${REMOTE_DIR}/"
        print_step "  Reports sent to remote machine: ${REMOTE_HOST}:${REMOTE_DIR}/"
    else
        log_error "SCP transfer to $REMOTE_HOST failed."
        print_step "  [!] Transfer to remote machine failed. Check $ERROR_LOG."
        return 1
    fi
}


# ---------------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------------

main() {
    # Make sure the audit directory is ready before we do anything else.
    ensure_report_dir

    # Load the saved config — or run first-time setup if it doesn't exist yet.
    load_config

    log_exec "===== Run started | Mode: $MODE | Host: $(hostname) ====="

    print_step ""
    print_step "============================================================"
    print_step "  Linux System Audit — NSCS 2025/2026"
    print_step "  Execution started: $RUN_DATE"
    print_step "  Mode: $MODE"
    print_step "============================================================"

    # Make sure the two sub-scripts are there and executable before we start.
    if [[ ! -x "$HW_AUDIT_SCRIPT" ]]; then
        log_error "Hardware audit script missing or not executable: $HW_AUDIT_SCRIPT"
        print_step "  [!] Can't find or run $HW_AUDIT_SCRIPT — aborting."
        exit 1
    fi
    if [[ ! -x "$SW_AUDIT_SCRIPT" ]]; then
        log_error "Software audit script missing or not executable: $SW_AUDIT_SCRIPT"
        print_step "  [!] Can't find or run $SW_AUDIT_SCRIPT — aborting."
        exit 1
    fi

    # Step 1 — collect all the data and build the full report
    generate_full_report

    # Step 2 — build the short summary report
    generate_short_report

    # Step 3 — email both reports as .txt attachments
    send_email

    # Step 4 — copy both reports to the remote machine
    send_to_remote

    log_exec "===== Run completed successfully | $RUN_DATE ====="

    print_step ""
    print_step "============================================================"
    print_step "  Script executed successfully."
    print_step "  Reports saved in : $REPORT_DIR"
    print_step "  Error log        : $ERROR_LOG"
    print_step "  Execution log    : $EXEC_LOG"
    print_step "============================================================"
    print_step ""
}

main
