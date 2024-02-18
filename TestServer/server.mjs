import path from 'path';
import express from 'express';
import { timestampLoggingMiddleware } from './timestamp_logging.mjs';

const app = express();
const port = 3000;

app.use(timestampLoggingMiddleware);

// Wait the response for :sec seconds to test timeout handling for
// domcontentloaded. A test for the domcontentloaded event.
app.get('/goto/timeout/:sec', (req, res) => {
    const ms = parseInt(req.params.sec) * 1_000;

    setTimeout(() => {
        res.send(`Waited for ${ms}ms`);
    }, ms);
});

// Simulate latency not on the html, but on the assets.
// This way domcontentloaded is fast, but the load event is slowed down.
let assetsLatency = 0;

// Dynamic route to set latency and serve the requested file
app.get('/load_latency/:sec/*', (req, res, next) => {
    // Set script latency based on URL parameter
    const sec = parseInt(req.params.sec, 10);
    if (isNaN(sec)) {
        next();
        return;
    }

    assetsLatency = sec * 1000; // Convert seconds to milliseconds

    // Extract the file path from the URL
    const filePath = req.params[0]; // This captures everything after the latency parameter

    // Serve the file from the public directory
    const fullPath = path.resolve(path.join('public', 'load_latency', filePath));
    res.sendFile(fullPath);
});

// Middleware to apply latency to specific script requests
app.use('/load_latency/assets/', (_, __, next) => {
    if (assetsLatency > 0) {
        setTimeout(() => {
            next();
        }, assetsLatency);
    } else {
        next();
    }
});

// Serve static files from the "public" directory
app.use(express.static('public'));

app.listen(port, () => {
    console.log(`Test server running at http://localhost:${port}`);
});
