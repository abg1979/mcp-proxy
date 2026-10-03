// Inspect the request before proxying; response bodies remain unbuffered.
async function classify(r) {
    r.variables.mcp_notification = '0';
    if (r.method !== 'POST') {
        return;
    }

    try {
        const message = JSON.parse(await r.readRequestText());
        if (message !== null && typeof message === 'object'
            && !Array.isArray(message) && message.jsonrpc === '2.0'
            && typeof message.method === 'string' && message.method.length > 0
            && !Object.prototype.hasOwnProperty.call(message, 'id')) {
            r.variables.mcp_notification = '1';
        }
    } catch (_) {
        // Let the upstream handle malformed requests without changing its reply.
    }
}

function normalize(r) {
    // Only an explicit Content-Length: 0 proves emptiness before headers are sent.
    // Leave unknown-length/chunked replies, JSON-RPC requests, and errors intact.
    if (r.variables.mcp_notification === '1' && r.status === 200
        && r.headersOut['Content-Length'] === '0') {
        r.status = 202;
        delete r.headersOut['Content-Type'];
        r.log('Normalized empty MCP notification response from 200 to 202');
    }
}

export default {classify, normalize};
