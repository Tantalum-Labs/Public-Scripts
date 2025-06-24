#!/bin/bash
# Usage: ./dns_recon_parallel.sh domains.txt
# The domains.txt file should contain one domain per line.

# Set the maximum number of simultaneous processes.
MAX_PROCS=3
ulimit -n 50000

# Function to count the number of active background jobs.
active_jobs() {
    jobs -r | wc -l
}

# Function to perform DNS recon on a single domain.
dns_recon() {
    local domain="$1"
    
    echo "Processing domain: $domain"
    
    # Create a folder for the domain.
    mkdir -p "Results/$domain"
    mkdir -p "Results/$domain/screenshots"
    
    # Run Nuclei and save the output.
    echo "Running nuclei on $domain..."
    touch Results/$domain/nuclei-raw.txt
    /usr/bin/nuclei -headless -u "$domain" -as -o "Results/$domain/nuclei.txt" 2>&1 | tee -p "Results/$domain/nuclei-raw.txt"
    
    echo "Recon for $domain complete. Results saved in folder '$domain'."
}

# Check if an input file was provided.
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <domains_file>"
    exit 1
fi

domains_file="$1"

# Check if the domains file exists.
if [ ! -f "$domains_file" ]; then
    echo "Error: File '$domains_file' not found."
    exit 1
fi

while IFS= read -r domain || [ -n "$domain" ]; do
    # Skip empty lines or lines starting with '#'
    if [[ -z "$domain" || "$domain" =~ ^# ]]; then
        continue
    fi

    # If we've reached our concurrency limit, wait for a job to finish.
    while [ "$(active_jobs)" -ge "$MAX_PROCS" ]; do
        sleep 1
    done

    # Start DNS recon in the background.
    dns_recon "$domain" &
done < "$domains_file"

wait

echo "Collecting domains..."
echo "...Aggregating and deduplicating domains..."
./collectSubdomains.sh
echo "...Adding original domains..."
./collectAllDomains.sh domains.txt
echo "...Aggregating and deduplicating ips..."
./collectIps.sh
echo "...Shodan searches..."
./shodanScan.sh ./Results/Combined_IP_Discovery.txt
echo "...Shodan processing..."
./collectShodanPorts.sh

echo "Running subzy against all domains and discovered subdomains..."
/root/go/bin/subzy run --https --vuln --targets "Results/All_Domains.txt" 2>&1 > "Results/Domain_Takeover.txt"

echo "All domains processed."
echo "scanHostsP next"
