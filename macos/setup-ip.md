# macOS M5 Max: static IP for the USB-C link

**[OWNER]** These steps run on the Mac, not the GX10. Values match
`config/link.conf` (`MAC_IP=192.168.20.17/24`, mask `255.255.255.0`). No
gateway/router and no DNS are set on this link.

1. List the network services and find the one for the Apple USB-C/Ethernet
   adapter created when the cable is plugged in:

   ```sh
   networksetup -listallnetworkservices
   ```

2. Set a manual IPv4 address on that service, with no router argument (the
   link has no gateway):

   ```sh
   networksetup -setmanual "<service>" 192.168.20.17 255.255.255.0
   ```

3. If the LAN also uses 172.16.0.0/24, the Mac would send 192.168.20.20
   over Wi-Fi/Ethernet. Pin the GX10 to the cable with a host route
   (`en3` is the cable interface whose `status` is `active`):

   ```sh
   sudo route -n add -host 192.168.20.20 -interface en3
   ```

   This route is lost on unplug or reboot; re-run it after reconnecting.

4. Verify the address and route took effect:

   ```sh
   ifconfig en3
   route -n get 192.168.20.20
   ```

5. To revert to DHCP (for example, before unplugging or re-testing):

   ```sh
   networksetup -setdhcp "<service>"
   ```

6. For bandwidth benchmarks (paired with `tests/bench.sh` on the GX10 side),
   start an iperf3 server:

   ```sh
   iperf3 -s
   ```
