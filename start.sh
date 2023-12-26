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
    ASSETS_ENCODED="eyJpbnN0YWxsZXJfYWNjb3VudF9hcC1zb3V0aC0xIjogIjA4ODgxOTU0NDUxNyIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9hcC1zb3V0aC0xIjogIjA4ODgxOTU0NDUxNyIsICJhcC1zb3V0aC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1hcC1zb3V0aC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1hcC1zb3V0aC0xIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfYXAtbm9ydGhlYXN0LTIiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2FwLW5vcnRoZWFzdC0yIjogIjA4ODgxOTU0NDUxNyIsICJhcC1ub3J0aGVhc3QtMiI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktYXAtbm9ydGhlYXN0LTIiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWFwLW5vcnRoZWFzdC0yIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfYXAtZWFzdC0xIjogIjMzMzQ1OTYyODYzMCIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9hcC1lYXN0LTEiOiAiMzMzNDU5NjI4NjMwIiwgImFwLWVhc3QtMSI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktYXAtZWFzdC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1hcC1lYXN0LTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9ldS13ZXN0LTIiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2V1LXdlc3QtMiI6ICIwODg4MTk1NDQ1MTciLCAiZXUtd2VzdC0yIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1ldS13ZXN0LTIiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWV1LXdlc3QtMiIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X2FwLW5vcnRoZWFzdC0zIjogIjA4ODgxOTU0NDUxNyIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9hcC1ub3J0aGVhc3QtMyI6ICIwODg4MTk1NDQ1MTciLCAiYXAtbm9ydGhlYXN0LTMiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWFwLW5vcnRoZWFzdC0zIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1hcC1ub3J0aGVhc3QtMyIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X3VzLXdlc3QtMSI6ICIwODg4MTk1NDQ1MTciLCAiaW50ZXJuYWxfaW5zdGFsbGVyX2FjY291bnRfdXMtd2VzdC0xIjogIjA4ODgxOTU0NDUxNyIsICJ1cy13ZXN0LTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LXVzLXdlc3QtMSIsICJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1oYXNoZXMtdXMtd2VzdC0xIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfY2EtY2VudHJhbC0xIjogIjA4ODgxOTU0NDUxNyIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9jYS1jZW50cmFsLTEiOiAiMDg4ODE5NTQ0NTE3IiwgImNhLWNlbnRyYWwtMSI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktY2EtY2VudHJhbC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1jYS1jZW50cmFsLTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9zYS1lYXN0LTEiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X3NhLWVhc3QtMSI6ICIwODg4MTk1NDQ1MTciLCAic2EtZWFzdC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1zYS1lYXN0LTEiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLXNhLWVhc3QtMSIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X2V1LW5vcnRoLTEiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2V1LW5vcnRoLTEiOiAiMDg4ODE5NTQ0NTE3IiwgImV1LW5vcnRoLTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWV1LW5vcnRoLTEiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWV1LW5vcnRoLTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9hcC1zb3V0aGVhc3QtMSI6ICIwODg4MTk1NDQ1MTciLCAiaW50ZXJuYWxfaW5zdGFsbGVyX2FjY291bnRfYXAtc291dGhlYXN0LTEiOiAiMDg4ODE5NTQ0NTE3IiwgImFwLXNvdXRoZWFzdC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1hcC1zb3V0aGVhc3QtMSIsICJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1oYXNoZXMtYXAtc291dGhlYXN0LTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF91cy1lYXN0LTIiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X3VzLWVhc3QtMiI6ICIwODg4MTk1NDQ1MTciLCAidXMtZWFzdC0yIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS11cy1lYXN0LTIiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLXVzLWVhc3QtMiIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X2V1LXdlc3QtMSI6ICIwODg4MTk1NDQ1MTciLCAiaW50ZXJuYWxfaW5zdGFsbGVyX2FjY291bnRfZXUtd2VzdC0xIjogIjA4ODgxOTU0NDUxNyIsICJldS13ZXN0LTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWV1LXdlc3QtMSIsICJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1oYXNoZXMtZXUtd2VzdC0xIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfYXAtc291dGhlYXN0LTIiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2FwLXNvdXRoZWFzdC0yIjogIjA4ODgxOTU0NDUxNyIsICJhcC1zb3V0aGVhc3QtMiI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktYXAtc291dGhlYXN0LTIiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWFwLXNvdXRoZWFzdC0yIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfYXAtc291dGhlYXN0LTMiOiAiMTQ5OTAyMDY2Nzg5IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2FwLXNvdXRoZWFzdC0zIjogIjE0OTkwMjA2Njc4OSIsICJhcC1zb3V0aGVhc3QtMyI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktYXAtc291dGhlYXN0LTMiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWFwLXNvdXRoZWFzdC0zIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfdXMtd2VzdC0yIjogIjA4ODgxOTU0NDUxNyIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF91cy13ZXN0LTIiOiAiMDg4ODE5NTQ0NTE3IiwgInVzLXdlc3QtMiI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktdXMtd2VzdC0yIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy11cy13ZXN0LTIiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9ldS1jZW50cmFsLTEiOiAiMDg4ODE5NTQ0NTE3IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2V1LWNlbnRyYWwtMSI6ICIwODg4MTk1NDQ1MTciLCAiZXUtY2VudHJhbC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1ldS1jZW50cmFsLTEiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWV1LWNlbnRyYWwtMSIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X2FwLW5vcnRoZWFzdC0xIjogIjA4ODgxOTU0NDUxNyIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9hcC1ub3J0aGVhc3QtMSI6ICIwODg4MTk1NDQ1MTciLCAiYXAtbm9ydGhlYXN0LTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWFwLW5vcnRoZWFzdC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1hcC1ub3J0aGVhc3QtMSIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X3VzLWVhc3QtMSI6ICIwODg4MTk1NDQ1MTciLCAiaW50ZXJuYWxfaW5zdGFsbGVyX2FjY291bnRfdXMtZWFzdC0xIjogIjA4ODgxOTU0NDUxNyIsICJ1cy1lYXN0LTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LXVzLWVhc3QtMSIsICJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1oYXNoZXMtdXMtZWFzdC0xIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfZXUtd2VzdC0zIjogIjA4ODgxOTU0NDUxNyIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9ldS13ZXN0LTMiOiAiMDg4ODE5NTQ0NTE3IiwgImV1LXdlc3QtMyI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktZXUtd2VzdC0zIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1ldS13ZXN0LTMiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9ldS1zb3V0aC0xIjogIjc0NDg5MzczOTA2MCIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9ldS1zb3V0aC0xIjogIjc0NDg5MzczOTA2MCIsICJldS1zb3V0aC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1ldS1zb3V0aC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1ldS1zb3V0aC0xIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfbWUtc291dGgtMSI6ICI3NzIyOTQwNjk0NjIiLCAiaW50ZXJuYWxfaW5zdGFsbGVyX2FjY291bnRfbWUtc291dGgtMSI6ICI3NzIyOTQwNjk0NjIiLCAibWUtc291dGgtMSI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktbWUtc291dGgtMSIsICJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1oYXNoZXMtbWUtc291dGgtMSIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X2FmLXNvdXRoLTEiOiAiMTcwODk5NTU5NzQ4IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2FmLXNvdXRoLTEiOiAiMTcwODk5NTU5NzQ4IiwgImFmLXNvdXRoLTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWFmLXNvdXRoLTEiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWFmLXNvdXRoLTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9ldS1jZW50cmFsLTIiOiAiODY0OTIyNDcwMjY4IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2V1LWNlbnRyYWwtMiI6ICI4NjQ5MjI0NzAyNjgiLCAiZXUtY2VudHJhbC0yIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1ldS1jZW50cmFsLTIiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWV1LWNlbnRyYWwtMiIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X2V1LXNvdXRoLTIiOiAiMzEyMjA0MjQyMzg4IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2V1LXNvdXRoLTIiOiAiMzEyMjA0MjQyMzg4IiwgImV1LXNvdXRoLTIiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWV1LXNvdXRoLTIiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWV1LXNvdXRoLTIiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9hcC1zb3V0aC0yIjogIjUzNTA5MTU4ODA4OSIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9hcC1zb3V0aC0yIjogIjUzNTA5MTU4ODA4OSIsICJhcC1zb3V0aC0yIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1hcC1zb3V0aC0yIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1hcC1zb3V0aC0yIiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfYXAtc291dGhlYXN0LTQiOiAiMDEzNjQ3ODM4NTUyIiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X2FwLXNvdXRoZWFzdC00IjogIjAxMzY0NzgzODU1MiIsICJhcC1zb3V0aGVhc3QtNCI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktYXAtc291dGhlYXN0LTQiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLWFwLXNvdXRoZWFzdC00IiwgImxhdGVzdCJdLCAiaW5zdGFsbGVyX2FjY291bnRfaWwtY2VudHJhbC0xIjogIjA1MDU3Mzc5MDg2NSIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF9pbC1jZW50cmFsLTEiOiAiMDUwNTczNzkwODY1IiwgImlsLWNlbnRyYWwtMSI6IFsiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaWwtY2VudHJhbC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy1pbC1jZW50cmFsLTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF9tZS1jZW50cmFsLTEiOiAiNTA0MTQ0NTA2MTg4IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X21lLWNlbnRyYWwtMSI6ICI1MDQxNDQ1MDYxODgiLCAibWUtY2VudHJhbC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS1tZS1jZW50cmFsLTEiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLW1lLWNlbnRyYWwtMSIsICJsYXRlc3QiXSwgImluc3RhbGxlcl9hY2NvdW50X3VzLWdvdi13ZXN0LTEiOiAiMjk2MjM5MTAwMjM5IiwgImludGVybmFsX2luc3RhbGxlcl9hY2NvdW50X3VzLWdvdi13ZXN0LTEiOiAiMjk2MjM5MTAwMjM5IiwgInVzLWdvdi13ZXN0LTEiOiBbImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LXVzLWdvdi13ZXN0LTEiLCAiYXdzLWVsYXN0aWMtZGlzYXN0ZXItcmVjb3ZlcnktaGFzaGVzLXVzLWdvdi13ZXN0LTEiLCAibGF0ZXN0Il0sICJpbnN0YWxsZXJfYWNjb3VudF91cy1nb3YtZWFzdC0xIjogIjI5NjIzOTEwMDIzOSIsICJpbnRlcm5hbF9pbnN0YWxsZXJfYWNjb3VudF91cy1nb3YtZWFzdC0xIjogIjI5NjIzOTEwMDIzOSIsICJ1cy1nb3YtZWFzdC0xIjogWyJhd3MtZWxhc3RpYy1kaXNhc3Rlci1yZWNvdmVyeS11cy1nb3YtZWFzdC0xIiwgImF3cy1lbGFzdGljLWRpc2FzdGVyLXJlY292ZXJ5LWhhc2hlcy11cy1nb3YtZWFzdC0xIiwgImxhdGVzdCJdfQ=="
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
  LIVECD_VERSION_HASH_URL=$(echo $LIVECD_HASH_URL | sed s/latest/ed7074e004c794b039bce007cbf7d33f898e05e1/)

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
