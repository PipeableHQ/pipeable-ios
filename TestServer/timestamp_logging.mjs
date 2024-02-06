function getFormattedTimestamp() {
    return new Date().toISOString();
}

export function timestampLoggingMiddleware(req, res, next) {
    const timestamp = getFormattedTimestamp();
    console.log(`[${timestamp}] Received: ${req.method} ${req.url}`);

    const originalSend = res.send;
    res.send = function (body) {
        const timestamp = getFormattedTimestamp();
        console.log(`[${timestamp}] Responded: ${req.method} ${req.url}`);
        originalSend.call(this, body);
    };
    next();
}
