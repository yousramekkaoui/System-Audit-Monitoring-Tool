#! /bin/bash

OUTPUT=$1 

echo -e "\n" >> "$OUTPUT"
echo -e "---Hostname---\n" >> "$OUTPUT"
hostname >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "---CPU Information---\n" >> "$OUTPUT"
lscpu >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "---GPU Information---\n" >> "$OUTPUT"
lspci | grep -i vga >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "----RAM Details----\n" >> "$OUTPUT"
free -h >> "$OUTPUT" 
echo -e "\n" >> "$OUTPUT"

echo -e "---Disk Information---\n" >> "$OUTPUT"
lsblk >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "---Network Interfaces---\n" >> "$OUTPUT"
ifconfig -a >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "---MAC Address----\n" >> "$OUTPUT"
cat /sys/class/net/*/address >> "$OUTPUT" #since some modersn linux systems use enp0s3 instead of eth0
#it is safer to use a wildcard to print the mac address
echo -e "\n" >> "$OUTPUT"

echo -e "---IP Address----\n" >> "$OUTPUT"
hostname -i >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "---Motherboard Information---\n" >> "$OUTPUT"

if sudo -n dmidecode -t baseboard >> "$OUTPUT" 2>/dev/null; then
    :
else
    echo "WARNING: Motherboard info requires root privileges (dmidecode)" >> "$OUTPUT"
fi

echo -e "\n" >> "$OUTPUT"
echo -e "---BIOS Details---\n" >> "$OUTPUT"
sudo dmidecode -t bios >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

echo -e "---USB Devices---\n" >> "$OUTPUT"
lsusb >> "$OUTPUT"
echo -e "\n" >> "$OUTPUT"

