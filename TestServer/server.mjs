import fs from 'fs';
import path from 'path';
import express from 'express';
import { timestampLoggingMiddleware } from './timestamp_logging.mjs';

const app = express();
const port = 3000;

app.use(timestampLoggingMiddleware);

// Wait the response for :sec seconds to test timeout handling for
// domcontentloaded. A test for the domcontentloaded event.
app.get('/goto/timeout/:ms', (req, res) => {
    const ms = parseInt(req.params.ms);

    setTimeout(() => {
        res.send(`Waited for ${ms}ms`);
    }, ms);
});

// Simulate latency not on the html, but on the assets.
// This way domcontentloaded is fast, but the load event is slowed down.

// Dynamic route to set latency and serve the requested file
app.get('/load_latency/:ms/*.html', (req, res) => {
    // Set script latency based on URL parameter
    const delay = parseInt(req.params.ms, 10);
    if (isNaN(delay)) {
        res.status(400).send('Invalid latency parameter');
        return;
    }

    const fileName = req.params[0];
    // Serve the file from the public directory
    const fullPath = path.resolve(path.join('public', 'load_latency', fileName + '.html'));
    const fileContents = fs.readFileSync(fullPath, 'utf8');
    const modifiedContents = fileContents.replace('{{delay}}', delay.toString());
    res.contentType('text/html').send(modifiedContents);
});

// Middleware to apply latency to specific script requests
app.use('/load_latency/assets/', (req, __, next) => {
    // parse ?delay= from req
    const delay = parseInt(req.query.delay, 10);
    if (isNaN(delay)) {
        next();
        return;
    }

    setTimeout(() => {
        next();
    }, delay);
});

// Serve static files from the "public" directory
app.use(express.static('public'));

app.listen(port, () => {
    console.log(`Test server running at http://localhost:${port}`);
});
