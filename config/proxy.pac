// Full-machine routing: send HTTPS (and other PAC-routed) traffic via authenticated proxy.
// Localhost stays DIRECT. Server-side Squid still requires auth and CONNECT :443 only.

// TLS Squid https_port: try HTTPS first (Chrome), then PROXY (Firefox).
var PROXY_HOST = "HTTPS proxy-dev.nogap.ai:443; PROXY proxy-dev.nogap.ai:443";

function isLocalHost(host) {
    if (!host) {
        return true;
    }
    host = host.toLowerCase();
    if (host === "localhost" || host === "127.0.0.1" || host === "::1") {
        return true;
    }
    if (host.endsWith(".local")) {
        return true;
    }
    return false;
}

function FindProxyForURL(url, host) {
    if (isPlainHostName(host)) {
        if (isLocalHost(host)) {
            return "DIRECT";
        }
        return PROXY_HOST;
    }
    if (isLocalHost(host)) {
        return "DIRECT";
    }
    return PROXY_HOST;
}
