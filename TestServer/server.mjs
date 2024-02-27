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

//
// Asset loading latency simulation for "load" event tests
//
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

//
// XHR latency simulation for networkidle tests
//
app.get('/xhr_latency/:ms/*.html', (req, res) => {
    const delay = parseInt(req.params.ms, 10);
    if (isNaN(delay)) {
        res.status(400).send('Invalid latency parameter');
        return;
    }

    const fileName = req.params[0];
    const fullPath = path.resolve(path.join('public', 'xhr_latency', fileName + '.html'));
    const fileContents = fs.readFileSync(fullPath, 'utf8');
    const modifiedContents = fileContents.replace('{{delay}}', delay.toString());
    res.contentType('text/html').send(modifiedContents);
});

// Middleware to apply latency to specific XHR requests
app.use('/xhr/', (req, __, next) => {
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

//

app.get('/xhr/fixed_string', (_, res) => {
    res.send('Fixed string');
});

// Test that we can read special headers set on responses.
app.get('/header_test', (_, res) => {
    res.set('X-Test-Header', 'Test');

    res.send('<html><body>Test</body></html>');
});

// Serve static files from the "public" directory
app.use(express.static('public'));

app.listen(port, () => {
    console.log(`Test server running at http://localhost:${port}`);
});
