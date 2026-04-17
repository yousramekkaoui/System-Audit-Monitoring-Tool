#! /bin/bash

OUTPUT=$1

echo -e "\n" >> "$OUTPUT"

echo -e "--- OS Name & Version ---\n" >> "$OUTPUT"
grep -E '^(NAME|VERSION)=' /etc/os-release >> "$OUTPUT" || true
echo -e "\n" >> "$OUTPUT"

echo -e "--- Kernel Version ---\n" >> "$OUTPUT"
uname -r >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "--- System Architecture ---\n" >> "$OUTPUT"
arch >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo "--- Installed Packages ---" >> "$OUTPUT"

echo "Total installed packages: $(apt list --installed 2>/dev/null | wc -l)" >> "$OUTPUT"
echo "These are the first lines of the very long list of the installed packages: " >> "$OUTPUT"

apt list --installed 2>/dev/null | head >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "--- Logged-in Users ---\n" >> "$OUTPUT"
who >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "--- Running Services ---\n" >> "$OUTPUT"
systemctl list-units --type=service --state=running --no-pager  >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "--- Active Processes ---\n" >> "$OUTPUT"
ps aux >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo "--- Open Ports ---" >> "$OUTPUT"
ports=$(ss -tuln) 

if [ -z "$ports" ]; then
  echo "No open ports found" >> "$OUTPUT"
else
  echo "$ports" >> "$OUTPUT"
fi

echo -e "--- System Uptime ---\n" >> "$OUTPUT"
uptime >> "$OUTPUT" 
echo -e "\n" >> "$OUTPUT"

echo -e "--- Current User ---\n" >> "$OUTPUT"
whoami >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "--- Disk Usage ---\n" >> "$OUTPUT"
df -h  >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

