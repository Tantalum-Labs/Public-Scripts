#!/bin/bash
# Usage: ./dns_recon_parallel.sh domains.txt
# The domains.txt file should contain one domain per line.

# Set the maximum number of simultaneous processes.
MAX_PROCS=8

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
    
    # Run theHarvester and save the output.
    echo "Running theHarvester on $domain..."
    theHarvester -d "$domain" -b dnsdumpster,anubis,baidu,bing,brave,certspotter,crtsh,duckduckgo,otx,rapiddns,sitedossier,subdomaincenter,subdomainfinderc99,virustotal -l 1000 -s --screenshot "Results/$domain/screenshots" > "Results/$domain/theharvester.txt"

    # Run Nuclei and save the output.
    echo "Running nuclei on $domain..."
    /root/go/bin/nuclei -silent -headless -u "$domain" -t /root/.local/nuclei-templates/ -screenshot -screenshot-output "Results/$domain/screenshots" -o "Results/$domain/nuclei.txt" 2>&1 > /dev/null
    
    # Run sublist3r and save the output.
    echo "Running sublist3r on $domain..."
    sublist3r -d "$domain" -o "Results/$domain/sublist3r.txt" 2>&1 > /dev/null

    echo "Recon for $domain complete. Results saved in folder '$domain'."
}

amass_recon() {
    local domain="$1"
    # Run amass and save the output.
    echo "Running amass on $domain..."
    ./runAmass.sh $domain
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

# Loop over each domain in the file.
while IFS= read -r domain || [ -n "$domain" ]; do
    # Skip empty lines or lines starting with '#'
    if [[ -z "$domain" || "$domain" =~ ^# ]]; then
        continue
    fi

    # If we've reached our concurrency limit, wait for a job to finish.
    while [ "$(active_jobs)" -ge "1" ]; do
        sleep 1
    done

    # Start DNS recon in the background.
    amass_recon "$domain" &
done < "$domains_file"

wait

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
echo "...sublist3r..."
./collectSublisterResults.sh
echo "...theHarvester..."
./collectHavesterResults.sh
./collectHavesterIpResults.sh
echo "...amaas.."
./collectAmass.sh
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
