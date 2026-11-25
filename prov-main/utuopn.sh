KEY="tu_key"; SECRET="tu_secret"; FW="https://10.0.1.254"; SRV="10.0.1.1"

for par in 801:80 4431:443 30001:3000; do
ext=${par%%:*}; int=${par##*:}
curl -sk -u "$KEY:$SECRET" -H "Content-Type: application/json" \
  -X POST $FW/api/firewall/d_nat/add_rule \
  -d '{"rule":{"interface":"wan","ipprotocol":"inet","protocol":"tcp","destination_net":"wanip","destination_port":"'$ext'","target":"'$SRV'","local-port":"'$int'","pass":"pass","descr":"Fwd '$ext' a '$int'"}}'
echo
done

curl -sk -u "$KEY:$SECRET" -X POST $FW/api/firewall/filter/apply