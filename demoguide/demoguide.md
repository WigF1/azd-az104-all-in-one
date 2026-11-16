[comment]: <> (please keep all comment items at the top of the markdown file)
[comment]: <> (please do not change the ***, as well as <div> placeholders for Note and Tip layout)
[comment]: <> (please keep the ### 1. and 2. titles as is for consistency across all demoguides)
[comment]: <> (section 1 provides a bullet list of resources + clarifying screenshots of the key resources details)
[comment]: <> (section 2 provides summarized step-by-step instructions on what to demo)


[comment]: <> (this is the section for the Note: item; please do not make any changes here)
***
### AZ-104 Demo all-in-one

<div style="background: lightgreen; 
            font-size: 14px; 
            color: black;
            padding: 5px; 
            border: 1px solid lightgray; 
            margin: 5px;">

**Note:** Below demo steps should be used **as a guideline** for doing your own demos. Please consider contributing to add additional demo steps.
</div>

[comment]: <> (this is the section for the Tip: item; consider adding a Tip, or remove the section between <div> and </div> if there is no tip)

***
### 1. What Resources are getting deployed

<img src="https://raw.githubusercontent.com/SQLtattoo/azd-az104-all-in-one/master/demoguide/images/az104allinone-diagram.png" alt="Solution diagram">
<br></br>

### 2. What can I demo from this scenario after deployment

- Hub and spoke network topology (spoke1 and spoke2 peered to the hub; workload VNet deliberately unpeered)
- Non-transitive peering and user-defined routes (an unassociated `custom-route-table` sends 0.0.0.0/0 to a non-existent NVA)
- Application Gateway (WAF_v2, Prevention mode, OWASP 3.2) in front of an App Service
- The App Service is locked down with access restrictions so it only accepts traffic from the Application Gateway's public IP; browsing its azurewebsites.net URL directly returns 403
- The 2 VMs behind the public Azure Load Balancer (web-lb) serve a page showing the VM's name, so you can demo the distribution. Use fresh connections (e.g. `curl.exe` in a loop) - a browser refresh reuses its connection and usually hits the same VM
- Inbound NAT rules on web-lb for RDP (ports 33891/33892) are blocked by the spoke1 NSG - a ready-made NSG troubleshooting demo with IP flow verify
- Private Link: a Private Link Service in front of a private Standard LB with an IIS VM (workload-vnet). A Private Endpoint in spoke2 (another region, not peered) reaches the IIS page
- Azure Bastion Developer (free), one per VM VNet, for secure VM access
- Key Vault (Azure RBAC model, deployer granted Key Vault Administrator) for Customer-Managed Keys demos
- VPN Gateway to show around the settings
- Recovery Services Vault to show around the settings (it can only protect VMs in its own region)
- Custom RBAC role (VM Support Engineer) and a VM governance policy initiative (definitions only - assign them live)
- Public DNS Zone to show around the settings
- Private DNS Zone with auto-registration, used to demonstrate name resolution across VNet peering by hostname i.e. ping, nslookup (enable ICMP in the Windows firewall first)
- Storage Account to demo Service Endpoint configuration
- Monitoring: VM Insights, alert rules, an action group and a Connection Monitor between the web VMs



[comment]: <> (this is the closing section of the demo steps. Please do not change anything here to keep the layout consistant with the other demoguides.)
<br></br>
***
<div style="background: lightgray; 
            font-size: 14px; 
            color: black;
            padding: 5px; 
            border: 1px solid lightgray; 
            margin: 5px;">

</div>
