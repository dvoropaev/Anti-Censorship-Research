# Architecture

The benchmark consists of 3 isolated parts:

- `remote-side` - acts as HTTP servers for the benchmark
- `middle-box` - acts as a VPN endpoint host, either WireGuard or TrustTunnel
- `local-side` - acts as a benchmark running host, can establish tunnels to the server
  residing on the remote side through the VPN endpoint

## How to run

### Single host

1) Build docker images

   ```shell
   cd ./bench
   ./single_host.sh build
   ```

   The client repo defaults to `https://github.com/TrustTunnel/TrustTunnelClient.git`.
   To use a different client repo:

   ```shell
   ./single_host.sh build --client=<trusttunnel_client_repo_url>
   ```

   To see the full set of available options run:

   ```shell
   ./single_host.sh --help
   ```

2) Run the benchmark

   ```shell
   ./single_host.sh run
   ```

   This command runs all the parts of the benchmark on the current host.

### Separate hosts

Assume IP addresses of `host_1`, `host_2` and `host_3` are 1.1.1.1, 2.2.2.2 and 3.3.3.3 respectively.

1) Running `host_1` as a remote side

   ```shell
   scp Dockerfile user@1.1.1.1:~
   scp -r remote-side user@1.1.1.1:~
   ssh user@1.1.1.1
   docker build -t bench-common .
   docker build -t bench-rs ./remote-side
   docker run -d -p 8080:8080 -p 5201:5201 -p 5201:5201/udp bench-rs
   ```

2) Running `host_2` as a middle box

   The endpoint is built from the repository root. Clone the project on the
   middle-box host:

   ```shell
   ssh user@2.2.2.2
   git clone <TrustTunnel.git> ~/trusttunnel-endpoint
   cd ~/trusttunnel-endpoint
   docker build -t bench-common bench/
   ```

    - WireGuard

       ```shell
       docker build -t bench-mb-wg bench/middle-box/wireguard
       docker run -d \
         --cap-add=NET_ADMIN --cap-add=SYS_MODULE --device=/dev/net/tun \
         -p 51820:51820/udp \
         bench-mb-wg
       ```

    - TrustTunnel

       ```shell
       docker build \
         --build-arg ENDPOINT_HOSTNAME=endpoint.bench \
         -f bench/middle-box/trusttunnel-rust/Dockerfile \
         -t bench-mb-ag .
       docker run -d \
         -p 4433:4433 -p 4433:4433/udp \
         bench-mb-ag
       ```

3) Run the benchmark from `host_3`

   ```shell
   scp Dockerfile user@3.3.3.3:~
   git clone <TrustTunnelClient.git> ./local-side/trusttunnel/trusttunnel-client
   scp -r local-side user@3.3.3.3:~
   ssh user@3.3.3.3
   docker build -t bench-common .
   docker build -t bench-ls ./local-side
   ```

   - No VPN

      ```shell
      ./local-side/bench.sh no-vpn bridge 1.1.1.1 results/no-vpn
      ```

   - WireGuard

      ```shell
      docker build -t bench-ls-wg ./local-side/wireguard
      ./local-side/bench.sh wg bridge 1.1.1.1 results/wg 2.2.2.2
      ```

   - TrustTunnel

      ```shell
      docker build \
        --build-arg CLIENT_DIR=trusttunnel-client \
        -t bench-ls-ag ./local-side/trusttunnel
      ./local-side/bench.sh ag bridge 1.1.1.1 results/ag 2.2.2.2 endpoint.bench
      ```
