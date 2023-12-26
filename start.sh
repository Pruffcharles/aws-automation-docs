WHITE='\033[1;37m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
LG='\033[0;37m'
NC='\033[0m'

build_args() {
  if [ ! -z "${AWS_REGION+x}" ]; then
    ARGS+=(--region $AWS_REGION)
  fi
  if [ ! -z "${AWS_ACCESS_KEY+x}" ]; then
    ARGS+=(--aws-access-key-id $AWS_ACCESS_KEY)
  fi
  if [ ! -z "${AWS_SECRET_KEY+x}" ]; then
    ARGS+=(--aws-secret-access-key $AWS_SECRET_KEY)
  fi
  if [ ! -z "${AWS_SESSION_TOKEN+x}" ]; then
    ARGS+=(--aws-session-token $AWS_SESSION_TOKEN)
  fi
  if [ ! -z "${AWS_DRS_ENDPOINT+x}" ]; then
    if [ ! -z "${AWS_DRS_ENDPOINT}" ]; then
      ARGS+=(--endpoint $AWS_DRS_ENDPOINT)
    else
      ARGS+=(--default-endpoint)
    fi
  fi
  if [ ! -z "${RECOVERY_INSTANCE_ID+x}" ]; then
    ARGS+=(--recovery-instance-id $RECOVERY_INSTANCE_ID)
  fi
  if [ ! -z "${DEVICE_MAPPING+x}" ]; then
    ARGS+=(--device-mapping $DEVICE_MAPPING)
  fi
  if [ ! -z "${NO_PROMPT+x}" ]; then
    ARGS+=(--no-prompt)
  fi
}



can_download_file() {
  TEMP_FILE=$(mktemp)
  trap 'rm "$TEMP_FILE"' EXIT
  wget --header x-amz-expected-bucket-owner:${INSTALLER_ACCOUNT} --quiet --timeout=20 --tries=1 -O $TEMP_FILE $MANIFEST_HASH_URL

  if [ $? == 0 ]; then
    return 0
  fi
  return 1
}

check_hashes() {
  if [ $(sha512sum /home/ec2-user/failback_assets.tar.gz | awk {'print $1'}) != $(cat /home/ec2-user/failback_assets.tar.gz.sha512) ]; then
    echo -e "${RED}Failed to validate Failback Client executable, wrong sha512 hash!${NC}"
    exit 1
  fi
}

check_if_DHCP_worked() {
  if can_download_file; then
    return 0
  else
    return 1
  fi
}

collect_asset_info() {
  while [ -z $ASSETS_INFO ]; do
    while [ -z $AWS_REGION ]; do
      echo -e "${WHITE}Enter AWS region to fail back from: ${NC}"
      read -r AWS_REGION
    done
    ASSETS_ENCODED="ENCODED_ASSETS_PLACEHOLDER"
    INSTALLER_ACCOUNT=$(python -c "import sys, json, base64; installer_account =  json.loads(base64.b64decode('$ASSETS_ENCODED').decode())['installer_account_'+'$AWS_REGION']; print(installer_account)")
    ASSETS_INFO=$(python -c "import sys, json, base64; reg_data = json.loads(base64.b64decode('$ASSETS_ENCODED').decode())['$AWS_REGION']; print(reg_data[0] + ',' + reg_data[1] + ',' + reg_data[2])")
    if [ $? -ne 0 ]; then
      echo -e "${RED}Bad or unsupported region, please retry${NC}"
      ASSETS_INFO=""
      AWS_REGION=""
    fi
  done

  IFS=, read ASSETS_BUCKET HASHES_BUCKET KEY_PREF <<< $ASSETS_INFO
  if [ $? -ne 0 ]; then
    echo -e "${RED}Internal error parsing assets s3 info${NC}"
    exit 1
  fi

  MANIFEST_URL="https://"${ASSETS_BUCKET}".s3."${AWS_REGION}".amazonaws.com/"${KEY_PREF}"/manifest.json"
  MANIFEST_HASH_URL="https://"${HASHES_BUCKET}".s3."${AWS_REGION}".amazonaws.com/"${KEY_PREF}"/manifest.json.sha512"
}

download_manifest() {
  # There is a chance that we may be downloading the manifest and hash files during their update, which is not an atomic operation.
  # Therefore, we need to wait until the files are updated.
  timeout=60
  start_time=$(date +%s)

  while true; do
    TEMP_FILE=$(mktemp)
    wget --header x-amz-expected-bucket-owner:${INSTALLER_ACCOUNT} --quiet --timeout=20 -O $TEMP_FILE "$MANIFEST_URL"
    MANIFEST_HASH_CALC=$(sha512sum $TEMP_FILE | awk '{{print $1}}')
    MANIFEST=$(<"$TEMP_FILE")
    rm $TEMP_FILE
    MANIFEST_HASH=$(wget --header x-amz-expected-bucket-owner:${INSTALLER_ACCOUNT} --quiet --timeout=20 -O - "$MANIFEST_HASH_URL")

    [[ $MANIFEST_HASH_CALC == $MANIFEST_HASH ]] && break

    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))

    [ $elapsed_time -ge $timeout ] && { echo -e "${RED}ERROR: Manifest download timed out.${NC}"; exit 1; }
    sleep 5
  done

  ASSETS_VERSION=$(python -c "import json; installer_version = json.loads('''$MANIFEST''')['installerVersion']; print(installer_version)")

  [[ -z $ASSETS_VERSION ]] && { echo -e "${RED}ERROR: Failed to retrieve assets version.${NC}"; exit 1; }

  ASSETS_KEY_PREF=$(python -c "path_parts = '''$KEY_PREF'''.split('/'); path_parts[-1] = '''$ASSETS_VERSION'''; print('/'.join(path_parts))")
  ASSETS_URL="https://"${ASSETS_BUCKET}".s3."${AWS_REGION}".amazonaws.com/"${ASSETS_KEY_PREF}"/failback_assets/failback_assets.tar.gz"
  HASH_URL="https://"${HASHES_BUCKET}".s3."${AWS_REGION}".amazonaws.com/"${ASSETS_KEY_PREF}"/failback_assets/failback_assets.tar.gz.sha512"
}

configure_network() {
  # EXPECT TO GET VALUES FOR IPADDR, NETMASK, GATEWAY, DNS and PROXY (DNS and PROXY could be blank)
  if [ -z "${DNS}" ]; then
    DNS=127.0.1.1  # default LiveCD DNS configuration
  fi
  echo "nameserver ${DNS}" | sudo tee /etc/resolv.conf &> /dev/null

  if [ -n "${PROXY}" ]; then
    echo https_proxy="${PROXY}" | sudo tee -a /etc/environment &> /dev/null
    export https_proxy="${PROXY}"
    echo Defaults env_keep = "https_proxy" | sudo tee -a /etc/sudoers &> /dev/null
  fi

  if [ -n "${IPADDR}" ]; then
    sudo systemctl stop network &> /dev/null
    for tmpif in $(ls /sys/class/net)
    do
      if [ "${tmpif}" != 'lo' ] ; then
        echo trying "${tmpif}"
        sudo ifconfig "${tmpif}" "${IPADDR}" netmask "${NETMASK}"
        sudo route add default gw "${GATEWAY}" "${tmpif}"
        if can_download_file; then
          break;
        fi
        sudo ifconfig "${tmpif}" "0.0.0.0"
      fi
    done
  else
    sudo dhclient
  fi
}

configure_s3_endpoint() {
  if [ $S3_ENDPOINT_IP ]; then
    TEMP_FILE=\`mktemp\`
    echo "address=/s3."${AWS_REGION}".amazonaws.com/"${S3_ENDPOINT_IP}"" > $TEMP_FILE
    sudo chown root:root $TEMP_FILE
    sudo chmod 644 $TEMP_FILE
    sudo mv $TEMP_FILE /etc/dnsmasq.d/s3_endpoint

    TEMP_FILE=\`mktemp\`
    echo "nameserver 127.0.0.1" > $TEMP_FILE
    grep -v "127.0.0.1" /etc/resolv.conf >> $TEMP_FILE
    sudo chown root:root $TEMP_FILE
    sudo chmod 644 $TEMP_FILE
    sudo mv $TEMP_FILE /etc/resolv.conf

    sudo systemctl restart dnsmasq
  fi
}

prompt_for_network() {
  echo -n -e "${WHITE}Enter Static IP address ${LG}(leave empty for DHCP): ${NC}"
  read -r IPADDR
  if [ -n "${IPADDR}" ]; then
    sudo systemctl stop network &> /dev/null
    echo -n -e "${WHITE}Enter Subnet Mask: ${NC}"
    read -r NETMASK
    echo -n -e "${WHITE}Enter Default Gateway: ${NC}"
    read -r GATEWAY
  else
    sudo systemctl restart network &> /dev/null
  fi
  echo -n -e "${WHITE}Enter DNS Server IP ${LG}(leave empty if not relevant): ${NC}"
  read -r DNS
  echo -n -e "${WHITE}Enter Web Proxy ${LG}(leave empty if not relevant): ${NC}"
  read -r PROXY
}

prompt_for_s3_endpoint() {
  # Endpoint ENV var is not set, prompt for user input
  if [ -z ${S3_ENDPOINT+s3} ]; then
    while : ; do
      echo  -e "${WHITE}Enter a custom s3 endpoint ${LG}(leave empty if not relevant): ${NC}"
        read -r S3_ENDPOINT
        if [ -z $S3_ENDPOINT ]; then
          break
        fi
        S3_ENDPOINT_IP=`dig +short ${S3_ENDPOINT} | head -n1`
        if [ $S3_ENDPOINT_IP ]; then
          configure_s3_endpoint
          echo -e "${GREEN}Custom s3 VPC endpoint configured${NC}"
          break
        fi
        echo -e "${RED}Custom s3 endpoint failed DNS resolution, please retry${NC}"
    done
  elif [ ! -z ${S3_ENDPOINT} ]; then
    S3_ENDPOINT_IP=`dig +short ${S3_ENDPOINT} | head -n1`
    if [ $S3_ENDPOINT_IP ]; then
      echo $S3_ENDPOINT_IP
      configure_s3_endpoint
      echo -e "${GREEN}Custom s3 VPC endpoint configured${NC}"
    else
      echo -e "${RED}Custom s3 endpoint failed DNS resolution, please check your DNS settings, or the supplied endpoint.${NC}"
      exit 1
    fi
  fi
}

retrieve_one_asset() {
  wget --header x-amz-expected-bucket-owner:${INSTALLER_ACCOUNT} --quiet --timeout=20 --tries=1 $1 -O /home/ec2-user/$2
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download $3${NC}"
    exit 1
  fi
}

retrieve_assets() {
  retrieve_one_asset $ASSETS_URL failback_assets.tar.gz "Failback Client assets"
  retrieve_one_asset $HASH_URL failback_assets.tar.gz.sha512 "Failback Client assets hash"
}

check_for_new_live_cd() {
  LIVECD_URL="https://"${ASSETS_BUCKET}".s3."${AWS_REGION}".amazonaws.com/"${KEY_PREF}"/failback_livecd/aws-failback-livecd-64bit.iso"
  LIVECD_HASH_URL="https://"${HASHES_BUCKET}".s3."${AWS_REGION}".amazonaws.com/"${KEY_PREF}"/failback_livecd/aws-failback-livecd-64bit.iso.sha512"
  LIVECD_VERSION_HASH_URL=$(echo $LIVECD_HASH_URL | sed s/latest/VERSION_HASH_PLACEHOLDER/)

  retrieve_one_asset $LIVECD_HASH_URL failback_client_latest.sha512 "latest Failback Client hash"
  retrieve_one_asset $LIVECD_VERSION_HASH_URL failback_client_version.sha512 "Failback Client hash for this version"

  diff -q /home/ec2-user/failback_client_latest.sha512 /home/ec2-user/failback_client_version.sha512
  if [ $? -ne 0 ]; then
    echo -e "${RED}WARNING: A newer version of the Failback Client ISO has been released here: ${LIVECD_URL} , please download and use the newest version"
    read -p "Press Enter to continue..."
  fi
}

start_replicator() {
  retrieve_assets
  check_hashes
  echo -e "${BLUE}Running Failback Client executable...${NC}"
  cd /home/ec2-user
  tar -xzf ./failback_assets.tar.gz
  chmod +x /home/ec2-user/jre/bin/*
  chmod +x /home/ec2-user/failback_entry
  ARGS=()
  build_args
  sudo /home/ec2-user/failback_entry "${ARGS[@]}"
  failback_exit_code=$?
  if [ $failback_exit_code -eq 0 ]; then
    livecd_device=$(blkid --label DRSFAILBACK)
    sudo eject -m $livecd_device
    sudo shutdown -r now
  elif [ $failback_exit_code -eq 1 ]; then
    echo -e "${RED}Unexpected error during failback, please see ${GREEN}failback.log.  ${NC}"
  fi
}

wait_for_dhcp_worked() {
  local ntries=10  # 10 times * 3 seconds = total 30 seconds of waiting for DHCP
  while true; do
    if [ $ntries = 0 ]; then
      return 1
    else
      sleep 3
      (( ntries-- ));
      # shellcheck disable=SC2009
      if ps -A | grep -q dhclient; then
        sleep 1
        if check_if_DHCP_worked; then
          return 0;
        fi
      fi
    fi
  done
}

MEM=$(grep MemTotal /proc/meminfo | awk '/[0-9]/ {print $2}')
if [ "$MEM" -lt "3800000" ]; then
    echo "Running the failback requires at least 4GiB of RAM"
    exit 1
fi

collect_asset_info

prompt_for_s3_endpoint

if [ "$CONFIG_NETWORK" == 1 ]; then
  # we are manually configuring network. Check all relevant values exist
  if [ -n "$IPADDR" ] && [ -n "$NETMASK" ] && [ -n "$GATEWAY" ] && [ -n "$DNS" ]; then
    configure_network
  else
    # values are missing, and we are using CONFIG_NETWORK, so display error and exit
    echo -e "${RED}ERROR: Needed data is missing in order to set up the network. Please check your network configuration ${NC}"
    exit 1
  fi
else
  if ! check_if_DHCP_worked; then
    if  wait_for_dhcp_worked; then
      sleep 1
    else
      while ! can_download_file; do
        prompt_for_network
        configure_network
        sleep 1
      done
    fi
  fi
fi

download_manifest
check_for_new_live_cd
start_replicator
