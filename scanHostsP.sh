#!/bin/bash
# Usage: ./scan_hosts_parallel.sh hosts.txt
# The hosts.txt file should contain one hostname/IP per line.

# Concurrency limit: maximum number of simultaneous nmap scans.
MAX_PROCS=15

# Function to count active background jobs.
function active_jobs {
    jobs -r | wc -l
}

# Check if input file is provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <hosts_file>"
    exit 1
fi

hosts_file="$1"

# Check if the file exists.
if [ ! -f "$hosts_file" ]; then
    echo "Error: File '$hosts_file' not found."
    exit 1
fi

# Extract the top 1000 ports
NMAP_T_PORTS=$(awk '$2 ~ /tcp/ { split($2, a, "/"); print a[1], $3 }' /usr/share/nmap/nmap-services | sort -k2 -rn  | head -n 1000  | awk '{print $1}' | tr '\n' ' '  | sed 's/ *$//'  | sed 's/ \+/,/g')
NMAP_U_PORTS="53,67,68,69,123,137,138,161,162,500,88,514,5353,5355,1900,3702"

# Extract the ports found by shodan
SHODAN_T_PORTS=$(grep '^T:' Results/Shodan_Ports_Discovery.txt | sed 's/^T://')
SHODAN_U_PORTS=$(grep '^U:' Results/Shodan_Ports_Discovery.txt | sed 's/^U://')

T_PORTS=$(echo "${NMAP_T_PORTS},${SHODAN_T_PORTS}" | tr ',' '\n' | sort -n | uniq | paste -sd, - | sed 's/^,//')
U_PORTS=$(echo "${NMAP_U_PORTS},${SHODAN_U_PORTS}" | tr ',' '\n' | sort -n | uniq | paste -sd, - | sed 's/^,//')

# Loop over each host in the file.
while IFS= read -r host || [ -n "$host" ]; do
    # Skip empty lines or lines starting with #
    if [[ -z "$host" || "$host" =~ ^# ]]; then
        continue
    fi

    # Wait if we've reached the concurrency limit.
    while [ "$(active_jobs)" -ge "$MAX_PROCS" ]; do
        sleep 1
    done

    echo "Starting scan for host: $host"

    # Construct output filename (replace any non-alphanumeric characters with underscores).
    mkdir -p Results/$host
    output_file="Results/$host/${host//[^a-zA-Z0-9_.-]/_}_scan.xml"

    # Run nmap in a separate background process.
    nseScripts="banner,http-headers,http-title,http-enum,ssl-cert,http-methods,ftp-anon,smb-enum-shares"
    nmap -Pn -T4 -sS -sU -sV -p U:${U_PORTS},T:${T_PORTS} --version-all --script=${nseScripts} -oX "$output_file" "$host" &
done < "$hosts_file"

# Wait for all background processes to finish.
wait

echo "All scans complete."
