#!/bin/bash

echo "Running subzy against all domains and discovered subdomains..."
/root/go/bin/subzy run --https --vuln --targets "Results/All_Domains.txt" 2>&1 > "Results/Subzy_Domain_Takeover.txt"
subjack -w ./Results/All_Domains.txt -t 100 -timeout 30 -o ./Results/Subjack_Domain_Takeover.txt -ssl
python3 /root/dnsReaper-2.0.2/main.py file --filename ./Results/All_Domains.txt --out ./Results/DNSReaper_Domain_Takeover.txt
