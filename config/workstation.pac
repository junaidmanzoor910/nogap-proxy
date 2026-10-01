// Laptop PAC: all public sites via local forwarder → EC2 Squid (auth on forwarder).
// Destinations to localhost / 127.0.0.1 / ::1 / *.local stay DIRECT (local inbound).

// 3129 avoids Ubuntu system squid default on 3128 (not the EC2 forwarder).
var LOCAL_FORWARDER = "PROXY 127.0.0.1:3129";

function isLocalHost(host) {
    if (!host) {
        return true;
    }
    host = host.toLowerCase();
    if (host === "localhost" || host === "127.0.0.1" || host === "::1" || host === "0.0.0.0" || host === "host.docker.internal") {
        return true;
    }
    if (host.startsWith("127.")) {
        return true;
    }
    if (host.endsWith(".local") || host.endsWith(".internal")) {
        return true;
    }
    return false;
}

function FindProxyForURL(url, host) {
    if (isLocalHost(host)) {
        return "DIRECT";
    }
    return LOCAL_FORWARDER;
}
