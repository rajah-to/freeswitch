# Default build: self-signed dev cert
docker build -t qwixpbx .

# Custom cert subject
docker build --build-arg CERT_CN=pbx.acme.com --build-arg CERT_O="Acme" -t qwixpbx .

# Production: mount your own cert at runtime
docker run \
  -v /etc/letsencrypt/live/pbx.acme.com/fullchain.pem:/etc/freeswitch/tls/wss.pem:ro \
  -v /etc/letsencrypt/live/pbx.acme.com/fullchain.pem:/etc/freeswitch/tls/agent.pem:ro \
  -v /etc/letsencrypt/live/pbx.acme.com/fullchain.pem:/etc/freeswitch/tls/cafile.pem:ro \
  qwixpbx


  # default build with self-signed cert
  docker run -d --name qwixpbx --cap-add=SYS_NICE \
  -e DOMAIN=10.0.0.178 \
  -p 5060:5060/udp -p 5060:5060/tcp \
  -p 5080:5080/udp -p 5080:5080/tcp \
  -p 8021:8021/tcp \
  -p 16384-16484:16384-16484/udp \
  qwixpbx



  # Custom cert domain
docker run -d \
  --name qwixpbx \
  --cap-add=SYS_NICE \
  -e CERT_CN=pbx.acme.com \
  -e CERT_O="Acme Corp" \
  -e CERT_C=CA \
  -p 5060:5060/udp \
  -p 5060:5060/tcp \
  -p 5080:5080/udp \
  -p 5080:5080/tcp \
  -p 8021:8021/tcp \
  -p 16384-16484:16384-16484/udp \
  qwixpbx

# Production — mount your own TLS cert
docker run -d \
  --name qwixpbx \
  --cap-add=SYS_NICE \
  -v /etc/letsencrypt/live/pbx.acme.com/wss.pem:/etc/freeswitch/tls/wss.pem:ro \
  -p 5060:5060/udp \
  -p 5060:5060/tcp \
  -p 5080:5080/udp \
  -p 5080:5080/tcp \
  -p 8021:8021/tcp \
  -p 16384-16484:16384-16484/udp \
  qwixpbx

# Debug build
docker run -d \
  --name qwixpbx \
  --cap-add=SYS_NICE \
  -p 5060:5060/udp \
  -p 5060:5060/tcp \
  -p 5080:5080/udp \
  -p 5080:5080/tcp \
  -p 8021:8021/tcp \
  -p 16384-16484:16384-16484/udp \
  qwixpbx:debug



  ### Debugging
  # 1. fs_cli — FreeSWITCH console (most useful)
docker exec -it qwixpbx fs_cli

# 2. Shell inside the container
docker exec -it qwixpbx /bin/bash

# 3. View live FreeSWITCH logs
docker logs -f qwixpbx


# 1. Restart the container (restarts FS process)
docker restart qwixpbx

# 2. Restart FS from inside fs_cli (graceful — waits for calls to finish)
docker exec -it qwixpbx fs_cli -x "fsctl restart"

# 3. Restart FS immediately via fs_cli (drops active calls)
docker exec -it qwixpbx fs_cli -x "fsctl restart asap"


# Reload SIP profiles (most common — after sip_profiles/ changes)
docker exec -it qwixpbx fs_cli -x "sofia profile internal restart"
docker exec -it qwixpbx fs_cli -x "sofia profile external restart"
docker exec -it qwixpbx fs_cli -x "sofia profile internal rescan"  # reload without dropping calls

# Reload a specific module (after autoload_configs/ changes)
docker exec -it qwixpbx fs_cli -x "reload mod_sofia"
docker exec -it qwixpbx fs_cli -x "reload mod_dialplan_xml"
docker exec -it qwixpbx fs_cli -x "reload mod_lua"

# Reload XML config (after any XML changes)
docker exec -it qwixpbx fs_cli -x "reloadxml"

docker exec -it qwixpbx fs_cli -x "module_exists mod_lua"
docker exec -it qwixpbx fs_cli -x "show modules" | grep lua


# Change a specific value
sed -i 's|old_value|new_value|' /etc/freeswitch/vars.xml

# Run as root
docker exec -it -u root qwixpbx apt -y update
 docker exec -it -u root qwixpbx apt -y install -y vim-tiny

# Then back in your freeswitch shell
vi /etc/freeswitch/vars.xml