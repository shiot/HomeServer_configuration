#!/bin/bash

# Container Configuration
# $1=ctTemplate (ubuntu/debian/turnkey-openvpn) - $2=hostname - $3=ContainerRootPasswort - $4=hdd size - $5=cpu cores - $6=RAM Swap/2 - $7=unprivileged 0/1 - $8=features (keyctl=1,nesting=1,mount=cifs)
containerSetup ubuntu $ctName $ctRootpw 4 1 512 1 ""

# Comes from Mainscript - start.sh --> Function containerSetup
ctID=$?

# Software that must be installed on the container - Space delimited
# example - containerSoftware="docker.io docker-compose"
containerSoftware="apt-transport-https"

# Start Container, because Container stoped aftrer creation
pct start $ctID
sleep 10

# echo [INFO] The container "CONTAINERNAME" is prepared for configuration
echo -e "$info $lng_lxc \"$ctName\" $lng_installlxc1"

# Install the packages specified as containerSoftware
for package in $containerSoftware; do
  # echo [INFO] "PACKAGENAME" will be installed
  echo -e "$info \"$package\" $lng_installlxc"
  pct exec $nextCTID -- bash -c "apt-get install -y $package > /dev/null 2>&1"
done

# Execute commands on containers
pct exec $ctID -- bash -ci "wget -qO - https://repos.influxdata.com/influxdb.key | apt-key add - > /dev/null 2>&1"
pct exec $ctID -- bash -ci "wget -qO - https://packages.grafana.com/gpg.key | apt-key add - > /dev/null 2>&1"
pct exec $ctID -- bash -ci "echo ""deb https://repos.influxdata.com/debian buster stable"" > /etc/apt/sources.list.d/influxdb.list"
pct exec $ctID -- bash -ci "echo ""deb https://packages.grafana.com/oss/deb stable main"" > /etc/apt/sources.list.d/grafana.list"
pct exec $ctID -- bash -ci "apt-get update > /dev/null 2>&1"
pct exec $ctID -- bash -ci "apt-get install -y influxdb grafana > /dev/null 2>&1"
pct exec $ctID -- bash -ci "mkdir -p /var/lib/grafana/dashboards"
pct exec $ctID -- bash -ci "wget -qO /var/lib/grafana/dashboards/proxmox.json $rawGitHubURL/container/$ctName/pveDashboard.json && chown grafana:grafana /var/lib/grafana/dashboards/proxmox.json"
pct exec $ctID -- bash -ci 'echo -e "[[udp]]\n enabled = true\n bind-address = \"0.0.0.0:8089\"\n database = \"proxmox\"\n batch-size = 1000\n batch-timeout = \"1s\"" >> /etc/influxdb/influxdb.conf'
pct exec $ctID -- bash -ci "sed -i 's+;default_home_dashboard_path =+default_home_dashboard_path = /var/lib/grafana/dashboards/proxmox.json+g' /etc/grafana/grafana.ini"
pct exec $ctID -- bash -ci "sed -n -i '$!N; s/\# enable anonymous access\n\;enabled = false/\# enable anonymous access\n\enabled = true/g;p' /etc/grafana/grafana.ini"
pct exec $ctID -- bash -ci "sed -i 's+;allow_embedding = false+allow_embedding = true+g' /etc/grafana/grafana.ini"
pct exec $ctID -- bash -ci 'echo -e "apiVersion: 1\n\ndatasources:\n  - name: Proxmox\n    type: influxdb\n    url: http://localhost:8086\n    access: proxy\n    database: proxmox" > /etc/grafana/provisioning/datasources/proxmox.yaml'
pct exec $ctID -- bash -ci 'echo -e "apiVersion: 1\n\nproviders:\n  - name: SmartHome-IoT\n    type: file\n    disableDeletion: true\n    updateIntervalSeconds: 60\n    options:\n      path: /var/lib/grafana/dashboards\n      foldersFromFilesStructure: true" > /etc/grafana/provisioning/dashboards/proxmox.yaml'
pct exec $ctID -- bash -ci "grafana-cli plugins install grafana-clock-panel > /dev/null 2>&1"
pct exec $ctID -- bash -ci "grafana-cli plugins install natel-discrete-panel > /dev/null 2>&1"
pct exec $ctID -- bash -ci "grafana-cli admin reset-admin-password changeme > /dev/null 2>&1"
pct exec $ctID -- bash -ci "systemctl stop grafana-server"
pct exec $ctID -- bash -ci "rm /var/log/grafana/grafana.log"
pct exec $ctID -- bash -ci "chown grafana:grafana /var/lib/grafana/*"
pct exec $ctID -- bash -ci "systemctl unmask influxdb.service > /dev/null 2>&1 && systemctl start influxdb > /dev/null 2>&1"
pct exec $ctID -- bash -ci "systemctl daemon-reload > /dev/null 2>&1 && systemctl enable grafana-server > /dev/null 2>&1 && systemctl start grafana-server > /dev/null 2>&1"
echo -e "influxdb: InfluxDB\n        port 8089\n        server $nextCTIP" > /etc/pve/status.cfg


# Container description in the Proxmox web interface
pct set $ctID --description $'Shell Login\nBenutzer: root\nPasswort: '"$ctRootpw"$'\n\nGrafana WebGUI\nAdresse: http://'"$nextCTIP"$':3000\nBenutzer: admin\nPasswort: changeme'

# echo [INFO] Create firewall rules for container "CONTAINERNAME"
echo -e "$info $lng_lxcfw \"$ctName\""

# Creates firewall rules for the container
# Create Firewallgroup - If a port should only be accessible from the local network - IN ACCEPT -source +network -p tcp -dport PORTNUMBER -log nolog
echo -e "[group $(echo $ctName|tr "[:upper:]" "[:lower:]")]\n\nIN ACCEPT -source +network -p tcp -dport 3000 -log nolog # Weboberfläche\n\n" >> $clusterfileFW

# Allow Firewallgroup
echo -e "[OPTIONS]\n\nenable: 1\n\n[RULES]\n\nGROUP $(echo $ctName|tr "[:upper:]" "[:lower:]")" > /etc/pve/firewall/$ctID.fw
